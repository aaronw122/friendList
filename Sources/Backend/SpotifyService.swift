import Foundation

/// Result of creating + populating a playlist.
struct SpotifyPlaylistResult: Sendable {
    let id: String
    let url: String
    let added: Int
}

/// M2 seam the UI talks to. Sendable so it can live on the state object and be
/// called from async UI tasks.
protocol SpotifyProviding: Sendable {
    /// Interactive PKCE login for the given client id; returns the display name.
    func connect(clientID: String) async throws -> String
    /// Create a private playlist and append the (already de-duplicated) track URIs
    /// in ≤100 batches, reporting progress as (fraction, label). If
    /// `coverImageBase64` is non-nil, set it as the cover after the tracks are in —
    /// a best-effort step that never fails the creation.
    func createPlaylist(name: String,
                        description: String,
                        trackURIs: [String],
                        coverImageBase64: String?,
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> SpotifyPlaylistResult
}

/// Real implementation. An actor because it caches the authenticated session
/// (`SpotifyAuth`) between the connect step and the later create step.
actor SpotifyService: SpotifyProviding {
    private var auth: SpotifyAuth?

    func connect(clientID: String) async throws -> String {
        // Changing the client id invalidates any stored tokens.
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
                        coverImageBase64: String?,
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

        // Cover is best-effort — a failed upload must not fail the playlist. But
        // cancellation (user hit Back) is rethrown, else we'd falsely report success.
        if let coverImageBase64 {
            progress(0.98, "Setting the cover image…")
            do {
                try await client.uploadImage(playlistID: playlist.id, base64JPEG: coverImageBase64)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                NSLog("friendList: cover image upload failed (non-fatal): \(error.localizedDescription)")
            }
        }

        progress(1, "Done")
        return SpotifyPlaylistResult(id: playlist.id, url: playlist.external_urls.spotify, added: added)
    }
}

/// Preview / no-network fake.
struct FakeSpotify: SpotifyProviding {
    func connect(clientID: String) async throws -> String { "Preview User" }
    func createPlaylist(name: String, description: String, trackURIs: [String],
                        coverImageBase64: String?,
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
