import Foundation

/// Single source of truth for the Spotify OAuth contract.
/// Auth model: Authorization Code + PKCE (NO client secret — a distributed native
/// app cannot keep one secret).
///
/// Redirect: **loopback** `http://127.0.0.1:<port>/auth-callback`, caught by a
/// local `NWListener` (see `LoopbackAuthServer`). We do NOT use a custom scheme:
/// Spotify empirically rejects custom schemes at `/authorize` for apps created
/// after 2025-04-09 (`INVALID_CLIENT: Insecure redirect URI`); only HTTPS and the
/// `127.0.0.1`/`[::1]` loopback literals are accepted (`localhost` is also banned).
enum SpotifyConfig {
    /// The loopback port must match the URI registered in the Spotify dashboard
    /// exactly, so it is fixed (not ephemeral).
    static let loopbackPort: UInt16 = 8888
    static let redirectPath = "/auth-callback"
    static let redirectURI = "http://127.0.0.1:8888/auth-callback"

    /// Least-privilege scope: just create/append the private playlist.
    /// Dedup is in-app (a song sent twice in the chat is added once) — so we do
    /// NOT read the user's playlists or Liked Songs. Dropped vs the handoff:
    /// playlist-modify-public, playlist-read-private, user-library-read, ugc-image-upload.
    static let scopes = ["playlist-modify-private"]

    /// Logging in and opening the dashboard are two separate steps on purpose:
    /// hitting the dashboard URL while logged out bounces to Spotify's marketing
    /// homepage, not a login. So we send the user to the real login form first;
    /// because both open in the same default browser, the session carries over
    /// and the dashboard then loads their account (no clever `?continue=` deep
    /// link that Spotify can silently break).
    static let loginURL = URL(string: "https://accounts.spotify.com/login")!
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    /// Exact values we tell the user to enter when creating their app.
    static let appName = "friendList"
    static let appDescription = "personal use"
}
