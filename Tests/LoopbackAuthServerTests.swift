import XCTest
@testable import FriendList

final class LoopbackAuthServerTests: XCTestCase {
    private let goodState = "expected-state"

    private func makeServer(port: UInt16) -> LoopbackAuthServer {
        LoopbackAuthServer(port: port, path: "/auth-callback", expectedState: goodState)
    }

    /// GET a loopback URL, retrying briefly so tests don't race the listener coming up.
    private func get(_ url: String) async throws {
        let u = URL(string: url)!
        var lastError: Error?
        for _ in 0..<40 {
            do { _ = try await URLSession.shared.data(from: u); return }
            catch { lastError = error; try await Task.sleep(nanoseconds: 50_000_000) }
        }
        XCTFail("could not reach \(url): \(lastError.map(String.init(describing:)) ?? "?")")
    }

    func testTimeoutTearsDownRedirectWait() async throws {
        let server = makeServer(port: 18461)
        try server.start()
        defer { server.stop() }

        let began = Date()
        do {
            _ = try await withTimeout(seconds: 0.3) { try await server.waitForRedirect() }
            XCTFail("expected timeout")
        } catch {
            guard case LoopbackAuthServer.AuthServerError.timedOut = error else {
                return XCTFail("expected timedOut, got \(error)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 3, "timeout must not deadlock on the redirect wait")
    }

    func testTaskCancellationTearsDownRedirectWait() async throws {
        let server = makeServer(port: 18462)
        try server.start()
        defer { server.stop() }

        let waiter = Task { try await server.waitForRedirect() }
        try await Task.sleep(nanoseconds: 100_000_000)
        waiter.cancel()
        do {
            _ = try await waiter.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
    }

    func testForgedStateAndWrongPathIgnoredUntilRealRedirect() async throws {
        let port: UInt16 = 18463
        let server = makeServer(port: port)
        try server.start()
        defer { server.stop() }
        let waiter = Task { try await server.waitForRedirect() }

        try await get("http://127.0.0.1:\(port)/auth-callback?code=forged&state=wrong")
        try await get("http://127.0.0.1:\(port)/auth-callback?code=forged")
        try await get("http://127.0.0.1:\(port)/elsewhere?code=forged&state=\(goodState)")
        try await get("http://127.0.0.1:\(port)/auth-callback?code=real&state=\(goodState)")

        let params = try await waiter.value
        XCTAssertEqual(params["code"], "real")
        XCTAssertEqual(params["state"], goodState)
    }

    func testErrorRedirectWithMatchingStateStillAccepted() async throws {
        let port: UInt16 = 18464
        let server = makeServer(port: port)
        try server.start()
        defer { server.stop() }
        let waiter = Task { try await server.waitForRedirect() }

        try await get("http://127.0.0.1:\(port)/auth-callback?error=access_denied&state=\(goodState)")

        let params = try await waiter.value
        XCTAssertEqual(params["error"], "access_denied")
    }

    func testRedirectArrivingBeforeWaitIsBuffered() async throws {
        let port: UInt16 = 18465
        let server = makeServer(port: port)
        try server.start()
        defer { server.stop() }

        try await get("http://127.0.0.1:\(port)/auth-callback?code=early&state=\(goodState)")

        let params = try await server.waitForRedirect()
        XCTAssertEqual(params["code"], "early")
    }
}
