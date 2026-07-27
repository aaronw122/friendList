import Foundation
import AppKit

enum SpotifyError: LocalizedError {
    case stateMismatch
    case authDenied(String)
    case noRefreshToken
    case http(Int, String)
    case decoding(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .stateMismatch:      return "Authorization response failed a security check (state mismatch)."
        case .authDenied(let m):  return "Spotify denied authorization: \(m)"
        case .noRefreshToken:     return "Not connected to Spotify — please authorize again."
        case .http(let c, let m): return "Spotify API error \(c): \(m)"
        case .decoding(let m):    return "Unexpected Spotify response: \(m)"
        case .notAuthenticated:   return "Not connected to Spotify."
        }
    }
}

/// Token lifecycle for Authorization Code + PKCE. Serializes refreshes (single-use
/// rotating refresh tokens) and — critically — only overwrites the stored refresh
/// token when Spotify actually returns a new one; overwriting with an absent field
/// permanently bricks auth.
actor SpotifyAuth {
    private let clientID: String
    private var accessToken: String?
    private var expiresAt: Date = .distantPast
    private var refreshInFlight: Task<Void, Error>?

    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let authorizeBase = "https://accounts.spotify.com/authorize"

    init(clientID: String) {
        self.clientID = clientID
    }

    // MARK: Interactive authorization (PKCE + loopback)

    /// Run the full browser authorization and store the resulting refresh token.
    func authorize(scopes: [String]) async throws {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.makeState()

        var comps = URLComponents(string: authorizeBase)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "state", value: state),
        ]
        let authorizeURL = comps.url!

        let server = LoopbackAuthServer(port: SpotifyConfig.loopbackPort)
        // Start listening, THEN open the browser, so we can't miss a fast redirect.
        let redirectTask = Task { try await server.waitForRedirect() }
        defer { redirectTask.cancel() }
        await MainActor.run { _ = NSWorkspace.shared.open(authorizeURL) }

        let params = try await withTimeout(seconds: 300) { try await redirectTask.value }

        if let err = params["error"] { throw SpotifyError.authDenied(err) }
        guard params["state"] == state else { throw SpotifyError.stateMismatch }
        guard let code = params["code"] else { throw SpotifyError.authDenied("no code returned") }

        try await exchangeCode(code, verifier: verifier)
    }

    // MARK: Token access

    /// A valid (non-expired) access token, refreshing if necessary.
    func validAccessToken() async throws -> String {
        if let token = accessToken, Date() < expiresAt.addingTimeInterval(-60) {
            return token
        }
        try await refreshCoalesced()
        guard let token = accessToken else { throw SpotifyError.notAuthenticated }
        return token
    }

    /// Coalesce concurrent refreshes onto a single in-flight Task. Actors are
    /// reentrant across `await`, so without this two callers past expiry could each
    /// read and SPEND the same single-use rotating refresh token, invalidating the
    /// grant. Everyone awaits the same Task, so the token is spent once.
    private func refreshCoalesced() async throws {
        if let inFlight = refreshInFlight {
            try await inFlight.value
            return
        }
        let task = Task { try await performRefresh() }
        refreshInFlight = task
        do {
            try await task.value
            refreshInFlight = nil
        } catch {
            refreshInFlight = nil
            throw error
        }
    }

    // MARK: Internals

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let form: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        let token = try await postToken(form)
        apply(token)
        // First authorization always returns a refresh token.
        if let rt = token.refresh_token, !rt.isEmpty {
            Keychain.set(rt, account: Keychain.Account.refreshToken)
        }
    }

    private func performRefresh() async throws {
        guard let stored = Keychain.get(account: Keychain.Account.refreshToken), !stored.isEmpty else {
            throw SpotifyError.noRefreshToken
        }
        let form: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": stored,
            "client_id": clientID,
        ]
        let token = try await postToken(form)
        apply(token)
        // GUARD: only overwrite the stored refresh token when a NEW one is present.
        // Spotify's refresh response often omits it; overwriting with nil bricks auth.
        if let rt = token.refresh_token, !rt.isEmpty {
            Keychain.set(rt, account: Keychain.Account.refreshToken)
        }
    }

    private func apply(_ token: TokenResponse) {
        accessToken = token.access_token
        expiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in))
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
    }

    private func postToken(_ form: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyError.http(-1, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        catch { throw SpotifyError.decoding(error.localizedDescription) }
    }

    private func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// Race an async operation against a timeout.
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw LoopbackAuthServer.AuthServerError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
