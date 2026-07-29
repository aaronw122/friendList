import Foundation
import AppKit

enum ReconnectReason: Sendable, Equatable {
    case expired
}

enum SpotifyError: LocalizedError {
    case stateMismatch
    case authDenied(String)
    case noRefreshToken
    case http(Int, String)
    case decoding(String)
    case notAuthenticated
    case sessionExpired
    case needsReconnect(reason: ReconnectReason)
    case playlistPublic
    case playlistFull

    var errorDescription: String? {
        switch self {
        case .stateMismatch:      return "Authorization response failed a security check (state mismatch)."
        case .authDenied(let m):  return "Spotify denied authorization: \(m)"
        case .noRefreshToken:     return "Not connected to Spotify — please authorize again."
        case .http(let c, let m): return "Spotify API error \(c): \(m)"
        case .decoding(let m):    return "Unexpected Spotify response: \(m)"
        case .notAuthenticated:   return "Not connected to Spotify."
        case .sessionExpired:     return "Your Spotify session expired — please authorize again."
        case .needsReconnect:     return "Your Spotify authorization expired — please reconnect."
        case .playlistPublic:     return "This playlist is public; make it private to keep syncing."
        case .playlistFull:       return "This playlist is full (Spotify's 10,000-track limit)."
        }
    }

    var isAuthenticationFailure: Bool {
        switch self {
        case .noRefreshToken, .notAuthenticated, .authDenied, .sessionExpired, .needsReconnect:
            return true
        case .http(let code, _):
            return code == 401 || code == 403
        case .stateMismatch, .decoding, .playlistPublic, .playlistFull:
            return false
        }
    }
}

extension Error {
    var isSpotifyAuthenticationFailure: Bool {
        (self as? SpotifyError)?.isAuthenticationFailure == true
    }
}

actor SpotifyAuth {
    private let clientID: String
    private let http: SpotifyHTTP
    private let loadRefreshToken: @Sendable () -> String?
    private let saveRefreshToken: @Sendable (String) -> Void
    private var accessToken: String?
    private var expiresAt: Date = .distantPast
    private var refreshInFlight: Task<Void, Error>?

    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private let authorizeBase = "https://accounts.spotify.com/authorize"

    init(clientID: String,
         http: SpotifyHTTP = URLSessionHTTP(),
         loadRefreshToken: @escaping @Sendable () -> String? = { Keychain.get(account: Keychain.Account.refreshToken) },
         saveRefreshToken: @escaping @Sendable (String) -> Void = { Keychain.set($0, account: Keychain.Account.refreshToken) }) {
        self.clientID = clientID
        self.http = http
        self.loadRefreshToken = loadRefreshToken
        self.saveRefreshToken = saveRefreshToken
    }

    // MARK: Interactive authorization (PKCE + loopback)

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
        // Start the loopback listener before opening the browser to avoid missing a fast redirect.
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

    func validAccessToken() async throws -> String {
        if let token = accessToken, Date() < expiresAt.addingTimeInterval(-60) {
            return token
        }
        try await refreshCoalesced()
        guard let token = accessToken else { throw SpotifyError.notAuthenticated }
        return token
    }

    /// Concurrent callers share one refresh task so the rotating token is spent once.
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
        if let rt = token.refresh_token, !rt.isEmpty {
            saveRefreshToken(rt)
        }
    }

    private func performRefresh() async throws {
        guard let stored = loadRefreshToken(), !stored.isEmpty else {
            throw SpotifyError.noRefreshToken
        }
        let form: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": stored,
            "client_id": clientID,
        ]
        let token: TokenResponse
        do {
            token = try await postToken(form)
        } catch let SpotifyError.http(code, body) where code == 400 || code == 401 {
            // invalid_grant means the six-month refresh-token lifetime expired and requires reconnecting.
            if code == 400, body.lowercased().contains("invalid_grant") {
                throw SpotifyError.needsReconnect(reason: .expired)
            }
            throw SpotifyError.sessionExpired
        }
        apply(token)
        // Spotify may omit refresh_token, so retain the stored token unless a replacement is returned.
        if let rt = token.refresh_token, !rt.isEmpty {
            saveRefreshToken(rt)
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

        let (data, response) = try await http.data(for: req)
        guard (200..<300).contains(response.statusCode) else {
            throw SpotifyError.http(response.statusCode, String(decoding: data, as: UTF8.self))
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
