import Foundation

/// Spotify rejects post-2025-04 custom schemes and localhost; native PKCE uses a 127.0.0.1 loopback with no secret.
enum SpotifyConfig {
    /// Spotify requires an exact registered redirect URI, so the loopback port cannot be ephemeral.
    static let loopbackPort: UInt16 = 8888
    static let redirectPath = "/auth-callback"
    static let redirectURI = "http://127.0.0.1:8888/auth-callback"

    /// Request only playlist-modify-private because dedup is local and requires no library reads.
    static let scopes = ["playlist-modify-private"]

    /// Open login before the dashboard because logged-out dashboard visits redirect to marketing.
    static let loginURL = URL(string: "https://accounts.spotify.com/login")!
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    static let appName = "friendList"
    static let appDescription = "personal use"
}
