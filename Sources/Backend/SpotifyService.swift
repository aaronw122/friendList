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
}

actor SpotifyService: SpotifyProviding {
    private var auth: SpotifyAuth?

    func savedClientID() -> String? {
        Keychain.get(account: Keychain.Account.clientID)
    }

    func restoreSession() async throws -> SpotifySession? {
        guard let clientID = Keychain.get(account: Keychain.Account.clientID),
              !clientID.isEmpty,
              let refreshToken = Keychain.get(account: Keychain.Account.refreshToken),
              !refreshToken.isEmpty else { return nil }

        let auth = SpotifyAuth(clientID: clientID)
        let client = SpotifyClient { try await auth.validAccessToken() }
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
        let auth = SpotifyAuth(clientID: clientID)
        try await auth.authorize(scopes: SpotifyConfig.scopes)
        self.auth = auth

        let client = SpotifyClient { try await auth.validAccessToken() }
        let me = try await client.me()
        return me.display_name ?? me.id
    }

    func createPlaylist(name: String,
                        description: String,
                        trackURIs: [String],
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult {
        guard let auth else { throw SpotifyError.notAuthenticated }
        let client = SpotifyClient { try await auth.validAccessToken() }

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
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
