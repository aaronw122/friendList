import XCTest
@testable import FriendList

final class SpotifyAppendTests: XCTestCase {
    private let tokenJSON = #"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#

    func testAppendBatchesAtHundredBoundaryAndCommitsEach() async throws {
        let http = RecordingHTTP { req in
            req.url!.path == "/api/token" ? .ok(self.tokenJSON) : .ok("")
        }
        let service = makeService(http: http)
        let uris = (0..<250).map { "spotify:track:\($0)" }

        var committed: [[String]] = []
        let added = try await service.appendTracks(playlistID: "pl", trackURIs: uris) { committed.append($0) }

        XCTAssertEqual(added, 250)
        XCTAssertEqual(committed.map(\.count), [100, 100, 50])
        XCTAssertEqual(committed.flatMap { $0 }, uris)
    }

    func testFailedBatchDoesNotCommitAndStopsRun() async {
        let itemsCall = Counter()
        let http = RecordingHTTP { req in
            if req.url!.path == "/api/token" { return .ok(self.tokenJSON) }
            return itemsCall.next() == 0 ? .ok("") : .init(status: 500, body: "server error")
        }
        let service = makeService(http: http)
        let uris = (0..<200).map { "spotify:track:\($0)" }

        var committed: [[String]] = []
        do {
            _ = try await service.appendTracks(playlistID: "pl", trackURIs: uris) { committed.append($0) }
            XCTFail("expected the failed batch to throw")
        } catch {
            // A 5xx on a POST is not retried, so the second batch surfaces the error.
        }

        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.count, 100)
    }

    func testInvalidGrantMapsToExpiredWithoutRetry() async {
        let http = RecordingHTTP { _ in .init(status: 400, body: #"{"error":"invalid_grant"}"#) }
        let auth = SpotifyAuth(clientID: "cid", http: http, loadRefreshToken: { "rt" }, saveRefreshToken: { _ in })

        do {
            _ = try await auth.validAccessToken()
            XCTFail("expected a reconnect error")
        } catch let SpotifyError.needsReconnect(reason) {
            XCTAssertEqual(reason, .expired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertEqual(http.requests.count, 1)
    }

    func test403PublicPlaylistMapsToSkip() async {
        let http = RecordingHTTP { _ in .init(status: 403, body: #"{"error":{"status":403,"message":"Insufficient scope"}}"#) }
        let client = SpotifyClient(tokenProvider: { "t" }, http: http)
        do {
            try await client.addItems(playlistID: "pl", uris: ["spotify:track:1"])
            XCTFail("expected a 403 to throw")
        } catch SpotifyError.playlistPublic {
        } catch {
            XCTFail("expected playlistPublic, got \(error)")
        }
    }

    func test403FullPlaylistMapsToSkip() async {
        let http = RecordingHTTP { _ in
            .init(status: 403, body: #"{"error":{"status":403,"message":"You can't add more than 10000 tracks to a playlist."}}"#)
        }
        let client = SpotifyClient(tokenProvider: { "t" }, http: http)
        do {
            try await client.addItems(playlistID: "pl", uris: ["spotify:track:1"])
            XCTFail("expected a 403 to throw")
        } catch SpotifyError.playlistFull {
        } catch {
            XCTFail("expected playlistFull, got \(error)")
        }
    }

    func testSharedAuthBuiltOnceAcrossAppends() async throws {
        let authBuilds = Counter()
        let tokenCalls = Counter()
        let http = RecordingHTTP { req in
            if req.url!.path == "/api/token" { tokenCalls.next(); return .ok(self.tokenJSON) }
            return .ok("")
        }
        let service = SpotifyService(
            http: http,
            clientIDSource: { "cid" },
            makeAuth: { id, transport in
                authBuilds.next()
                return SpotifyAuth(clientID: id, http: transport, loadRefreshToken: { "rt" }, saveRefreshToken: { _ in })
            })

        _ = try await service.appendTracks(playlistID: "pl", trackURIs: ["spotify:track:1"]) { _ in }
        _ = try await service.appendTracks(playlistID: "pl", trackURIs: ["spotify:track:2"]) { _ in }

        XCTAssertEqual(authBuilds.count, 1)
        XCTAssertEqual(tokenCalls.count, 1)
    }

    private func makeService(http: SpotifyHTTP) -> SpotifyService {
        SpotifyService(
            http: http,
            clientIDSource: { "cid" },
            makeAuth: { id, transport in
                SpotifyAuth(clientID: id, http: transport, loadRefreshToken: { "rt" }, saveRefreshToken: { _ in })
            })
    }
}

private struct StubResponse {
    let status: Int
    let body: String
    static func ok(_ body: String) -> StubResponse { StubResponse(status: 200, body: body) }
    init(status: Int, body: String) { self.status = status; self.body = body }
}

private final class RecordingHTTP: SpotifyHTTP, @unchecked Sendable {
    private let handler: (URLRequest) -> StubResponse
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    init(_ handler: @escaping (URLRequest) -> StubResponse) { self.handler = handler }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); recorded.append(request); lock.unlock()
        let stub = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        return (Data(stub.body.utf8), response)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = value; value += 1; return v }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
