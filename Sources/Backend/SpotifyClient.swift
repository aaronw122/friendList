import Foundation

/// Uses post-Feb-2026 /items endpoints in ≤100-URI batches, falling back to legacy /tracks on 404.
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

    func addItems(playlistID: String, uris: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["uris": uris])
        do {
            try await requestVoid("POST", "/playlists/\(playlistID)/items", body: body)
        } catch let SpotifyError.http(code, _) where code == 404 {
            try await requestVoid("POST", "/playlists/\(playlistID)/tracks", body: body)
        }
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

    private func send(_ method: String, _ path: String, body: Data?, attempt: Int = 0) async throws -> Data {
        let token = try await tokenProvider()
        var req = URLRequest(url: base.appendingPathComponent(String(path.dropFirst())))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.http(-1, "no response") }

        switch http.statusCode {
        case 200..<300:
            return data
        case 429 where attempt < 3:
            // A 429 means the request was not applied, so retrying any method is safe.
            let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(nanoseconds: UInt64((retry + 0.2) * 1_000_000_000))
            return try await send(method, path, body: body, attempt: attempt + 1)
        case 500..<600 where attempt < 3 && method == "GET":
            // Retry only GET on 5xx; replaying a possibly applied POST could duplicate playlists or tracks.
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            return try await send(method, path, body: body, attempt: attempt + 1)
        default:
            throw SpotifyError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}
