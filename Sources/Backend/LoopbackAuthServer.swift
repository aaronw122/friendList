import Foundation
import Network

/// Spotify rejects custom schemes for new apps, so OAuth returns through a one-shot 127.0.0.1 listener.
final class LoopbackAuthServer: @unchecked Sendable {
    private let port: UInt16
    private let path: String
    private let expectedState: String
    private var listener: NWListener?

    // Redirect, failure, and cancellation can race, so the continuation must resume exactly once.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var pending: Result<[String: String], Error>?
    private var finished = false

    init(port: UInt16, path: String, expectedState: String) {
        self.port = port
        self.path = path
        self.expectedState = expectedState
    }

    enum AuthServerError: LocalizedError {
        case listenerFailed(String)
        case timedOut
        var errorDescription: String? {
            switch self {
            case .listenerFailed(let m): return "Local callback server failed: \(m)"
            case .timedOut: return "Timed out waiting for Spotify to redirect back."
            }
        }
    }

    private func finish(_ outcome: Result<[String: String], Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        // Buffer a result that lands before waitForRedirect registers its continuation.
        if cont == nil { pending = outcome }
        lock.unlock()

        listener?.cancel()
        cont?.resume(with: outcome)
    }

    /// Start listening before the browser opens so a fast redirect can't be missed.
    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AuthServerError.listenerFailed("bad port")
        }
        // Loopback-only bind: nothing off-machine can ever reach the callback socket.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener: NWListener
        do { listener = try NWListener(using: params) }
        catch { throw AuthServerError.listenerFailed(error.localizedDescription) }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.finish(.failure(AuthServerError.listenerFailed(error.localizedDescription)))
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.readRequestTarget(connection) { target in
                Self.respondAndClose(connection)
                guard let self else { return }
                let (reqPath, query) = Self.splitTarget(target)
                // Only the redirect path carrying our own state counts; forged requests can't abort the flow.
                guard reqPath == self.path, query["state"] == self.expectedState else { return }
                if query["code"] != nil || query["error"] != nil {
                    self.finish(.success(query))
                }
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    /// Tear down the listener and resume any waiter; safe to call more than once.
    func stop() {
        finish(.failure(CancellationError()))
    }

    /// Wait for the auth redirect; task cancellation tears the wait down immediately.
    func waitForRedirect() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                if let result = pending {
                    pending = nil
                    lock.unlock()
                    cont.resume(with: result)
                    return
                }
                if finished { lock.unlock(); cont.resume(throwing: CancellationError()); return }
                continuation = cont
                lock.unlock()
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private static func readRequestTarget(_ conn: NWConnection, _ done: @escaping (String) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n", maxSplits: 1).first else {
                done(""); return
            }
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { done(""); return }
            done(String(parts[1]))
        }
    }

    private static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        let pieces = target.split(separator: "?", maxSplits: 1)
        let path = pieces.first.map(String.init) ?? ""
        guard pieces.count > 1 else { return (path, [:]) }
        var result: [String: String] = [:]
        for pair in pieces[1].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            result[String(key)] = value.removingPercentEncoding ?? value
        }
        return (path, result)
    }

    private static func respondAndClose(_ conn: NWConnection) {
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>FriendList</title></head>
        <body style="font-family:-apple-system,system-ui;text-align:center;padding-top:80px;color:#3A352E">
        <h2>FriendList is connected 🎵</h2>
        <p>You can close this tab and return to the app.</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
