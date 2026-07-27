import Foundation

/// Thin Spotify Web API client. Endpoints are the current (post-Feb-2026) ones:
/// create = `POST /v1/me/playlists`, add = `POST /v1/playlists/{id}/items` in
/// batches of ≤100 URIs. The add path falls back to the legacy `/tracks` on a 404,
/// since the `/tracks`→`/items` rename is the single external claim the whole
/// feature rests on — cheap insurance if a given account is still on the old path.
struct SpotifyClient {
    let tokenProvider: () async throws -> String
    private let base = URL(string: "https://api.spotify.com/v1")!

    struct Me: Decodable { let id: String; let display_name: String? }
    struct CreatedPlaylist: Decodable {
        let id: String
        let external_urls: ExternalURLs
        struct ExternalURLs: Decodable { let spotify: String }
    }

    func me() async throws -> Me {
        try await request("GET", "/me", body: nil, decode: Me.self)
    }

    func createPlaylist(name: String, description: String, isPublic: Bool = false) async throws -> CreatedPlaylist {
        let body = try JSONSerialization.data(withJSONObject: [
            "name": name.isEmpty ? "friendList" : name,
            "description": description,
            "public": isPublic,
        ])
        return try await request("POST", "/me/playlists", body: body, decode: CreatedPlaylist.self)
    }

    /// Append up to 100 URIs. Tries `/items`, falls back to `/tracks` on 404.
    func addItems(playlistID: String, uris: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["uris": uris])
        do {
            try await requestVoid("POST", "/playlists/\(playlistID)/items", body: body)
        } catch let SpotifyError.http(code, _) where code == 404 {
            try await requestVoid("POST", "/playlists/\(playlistID)/tracks", body: body)
        }
    }

    /// Set the playlist cover. Body is a base64 JPEG string (not JSON), `image/jpeg`;
    /// returns 202 and the cover lands a few seconds later. Needs `ugc-image-upload`.
    func uploadImage(playlistID: String, base64JPEG: String) async throws {
        _ = try await send("PUT", "/playlists/\(playlistID)/images",
                           body: Data(base64JPEG.utf8), contentType: "image/jpeg")
    }

    // MARK: - Transport

    private func request<T: Decodable>(_ method: String, _ path: String, body: Data?, decode: T.Type) async throws -> T {
        let data = try await send(method, path, body: body)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SpotifyError.decoding(error.localizedDescription) }
    }

    private func requestVoid(_ method: String, _ path: String, body: Data?) async throws {
        _ = try await send(method, path, body: body)
    }

    /// Send with bearer auth, honoring 429 `Retry-After` and retrying 5xx briefly.
    /// `contentType` defaults to JSON; the image endpoint overrides it to `image/jpeg`.
    private func send(_ method: String, _ path: String, body: Data?,
                      contentType: String = "application/json", attempt: Int = 0) async throws -> Data {
        let token = try await tokenProvider()
        var req = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.http(-1, "no response") }

        switch http.statusCode {
        case 200..<300:
            return data
        case 429 where attempt < 3:
            // Rate-limited means the request did NOT apply, so retrying any method
            // is safe.
            let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(nanoseconds: UInt64((retry + 0.2) * 1_000_000_000))
            return try await send(method, path, body: body, contentType: contentType, attempt: attempt + 1)
        case 500..<600 where attempt < 3 && method == "GET":
            // Only retry idempotent GETs on 5xx. A POST (create playlist / add items)
            // may have applied server-side before the error, so a blind retry would
            // duplicate playlists or tracks.
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            return try await send(method, path, body: body, contentType: contentType, attempt: attempt + 1)
        default:
            throw SpotifyError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}
