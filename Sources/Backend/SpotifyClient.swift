import Foundation

protocol SpotifyHTTP: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTP: SpotifyHTTP {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.http(-1, "no response") }
        return (data, http)
    }
}

/// Spotify's /items endpoint accepts at most 100 URIs; a 404 requires the legacy /tracks fallback.
struct SpotifyClient {
    let tokenProvider: () async throws -> String
    var http: SpotifyHTTP = URLSessionHTTP()
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
            do {
                try await requestVoid("POST", "/playlists/\(playlistID)/items", body: body)
            } catch let SpotifyError.http(code, _) where code == 404 {
                try await requestVoid("POST", "/playlists/\(playlistID)/tracks", body: body)
            }
        } catch let SpotifyError.http(code, responseBody) where code == 403 {
            throw Self.classify403(responseBody)
        }
    }

    /// With only playlist-modify-private scope, the 403 body distinguishes public playlists from full playlists.
    static func classify403(_ body: String) -> SpotifyError {
        let lower = body.lowercased()
        if lower.contains("10000") || lower.contains("maximum") || lower.contains("exceed") || lower.contains("add more than") {
            return .playlistFull
        }
        return .playlistPublic
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

        let (data, httpResponse) = try await http.data(for: req)

        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 429 where attempt < 3:
            // A 429 is unapplied, so retrying any HTTP method is safe.
            let retry = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
            try await Task.sleep(nanoseconds: UInt64((retry + 0.2) * 1_000_000_000))
            return try await send(method, path, body: body, attempt: attempt + 1)
        case 500..<600 where attempt < 3 && method == "GET":
            // Retry only GET on 5xx because replaying a possibly applied POST can duplicate data.
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            return try await send(method, path, body: body, attempt: attempt + 1)
        default:
            throw SpotifyError.http(httpResponse.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}
