import Foundation

struct SpotifyPlaylistResult: Sendable {
    let id: String
    let url: String
    let added: Int
}

struct SpotifySession: Sendable, Equatable {
    let clientID: String
    let displayName: String
}

protocol SpotifyProviding: Sendable {
    func savedClientID() async -> String?
    func restoreSession() async throws -> SpotifySession?
    func connect(clientID: String) async throws -> String
    func createPlaylist(name: String,
                        description: String,
                        trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult
    /// Silent append; throws SpotifyError.needsReconnect/.playlistPublic/.playlistFull, commits each landed batch via onBatchAdded.
    func appendTracks(playlistID: String,
                      trackURIs: [String],
                      onBatchAdded: ([String]) -> Void) async throws -> Int
}

actor SpotifyService: SpotifyProviding {
    private var auth: SpotifyAuth?
    private let http: SpotifyHTTP
    private let clientIDSource: @Sendable () -> String?
    private let makeAuth: @Sendable (String, SpotifyHTTP) -> SpotifyAuth

    init(http: SpotifyHTTP = URLSessionHTTP(),
         clientIDSource: @escaping @Sendable () -> String? = { Keychain.get(account: Keychain.Account.clientID) },
         makeAuth: @escaping @Sendable (String, SpotifyHTTP) -> SpotifyAuth = { SpotifyAuth(clientID: $0, http: $1) }) {
        self.http = http
        self.clientIDSource = clientIDSource
        self.makeAuth = makeAuth
    }

    func savedClientID() -> String? {
        clientIDSource()
    }

    func restoreSession() async throws -> SpotifySession? {
        guard let clientID = clientIDSource(),
              !clientID.isEmpty,
              let refreshToken = Keychain.get(account: Keychain.Account.refreshToken),
              !refreshToken.isEmpty else { return nil }

        let auth = makeAuth(clientID, http)
        let client = SpotifyClient(tokenProvider: { try await auth.validAccessToken() }, http: http)
        let me = try await client.me()
        self.auth = auth
        return SpotifySession(clientID: clientID, displayName: me.display_name ?? me.id)
    }

    func connect(clientID: String) async throws -> String {
        // Changing the client ID invalidates its authenticated session and stored tokens.
        if Keychain.get(account: Keychain.Account.clientID) != clientID {
            Keychain.clearTokens()
            Keychain.set(clientID, account: Keychain.Account.clientID)
        }
        let auth = makeAuth(clientID, http)
        try await auth.authorize(scopes: SpotifyConfig.scopes)
        self.auth = auth

        let client = SpotifyClient(tokenProvider: { try await auth.validAccessToken() }, http: http)
        let me = try await client.me()
        return me.display_name ?? me.id
    }

    func createPlaylist(name: String,
                        description: String,
                        trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        guard let auth else { throw SpotifyError.notAuthenticated }
        let client = SpotifyClient(tokenProvider: { try await auth.validAccessToken() }, http: http)

        progress(0.05, "Creating the playlist on Spotify…")
        let playlist = try await client.createPlaylist(name: name, description: description)

        let batches = trackURIs.chunked(100)
        var added = 0
        if batches.isEmpty {
            progress(1, "Done")
        }
        for (i, batch) in batches.enumerated() {
            try await client.addItems(playlistID: playlist.id, uris: batch)
            added += batch.count
            let frac = 0.1 + 0.85 * Double(i + 1) / Double(batches.count)
            progress(frac, "Adding tracks… \(added)/\(trackURIs.count)")
        }
        progress(1, "Done")
        return SpotifyPlaylistResult(id: playlist.id, url: playlist.external_urls.spotify, added: added)
    }

    /// Headless append: no interactive authorize, commits each landed batch via onBatchAdded so a mid-run 5xx keeps earlier tracks.
    func appendTracks(playlistID: String,
                      trackURIs: [String],
                      onBatchAdded: ([String]) -> Void) async throws -> Int {
        let auth = try sharedAuth()
        let client = SpotifyClient(tokenProvider: { try await auth.validAccessToken() }, http: http)

        var added = 0
        for batch in trackURIs.chunked(100) {
            try await client.addItems(playlistID: playlistID, uris: batch)
            added += batch.count
            onBatchAdded(batch)
        }
        return added
    }

    /// Reuses the cached auth or builds one from the keychain and assigns it back, so a single rotating refresh token is never spent twice.
    private func sharedAuth() throws -> SpotifyAuth {
        if let auth { return auth }
        guard let clientID = clientIDSource(), !clientID.isEmpty else { throw SpotifyError.notAuthenticated }
        let auth = makeAuth(clientID, http)
        self.auth = auth
        return auth
    }
}

struct FakeSpotify: SpotifyProviding {
    func savedClientID() async -> String? { nil }
    func restoreSession() async throws -> SpotifySession? { nil }
    func connect(clientID: String) async throws -> String { "Preview User" }
    func createPlaylist(name: String, description: String, trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        progress(0.5, "Adding tracks…")
        progress(1, "Done")
        return SpotifyPlaylistResult(id: "preview", url: "https://open.spotify.com/playlist/preview", added: trackURIs.count)
    }
    func appendTracks(playlistID: String, trackURIs: [String], onBatchAdded: ([String]) -> Void) async throws -> Int {
        for batch in trackURIs.chunked(100) { onBatchAdded(batch) }
        return trackURIs.count
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
