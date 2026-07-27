import Foundation
import Network

/// A one-shot local HTTP listener on `127.0.0.1:<port>` that catches the OAuth
/// redirect. Because Spotify rejects custom URL schemes for new apps, the
/// authorize URL opens in the user's browser and Spotify redirects back to this
/// loopback address; we read the `?code=…&state=…` off the first request line,
/// return a small "you can close this tab" page, and tear the listener down.
final class LoopbackAuthServer {
    private let port: UInt16
    private var listener: NWListener?

    // Continuation state, guarded so we resume exactly once (redirect / failure /
    // cancellation all race).
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var finished = false

    init(port: UInt16) { self.port = port }

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

    /// Resume exactly once and always tear the listener down.
    private func finish(_ params: [String: String]?, _ error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let cont = continuation
        continuation = nil
        lock.unlock()

        listener?.cancel()
        if let params { cont?.resume(returning: params) }
        else { cont?.resume(throwing: error ?? AuthServerError.timedOut) }
    }

    /// Start listening and resume when the *auth* redirect arrives (or on failure
    /// or Task cancellation — e.g. the caller's timeout). Returns the parsed query
    /// parameters (e.g. `["code": …, "state": …]`).
    func waitForRedirect() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                if finished { lock.unlock(); cont.resume(throwing: CancellationError()); return }
                continuation = cont
                lock.unlock()

                do {
                    let params = NWParameters.tcp
                    params.allowLocalEndpointReuse = true
                    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                        finish(nil, AuthServerError.listenerFailed("bad port")); return
                    }
                    let listener = try NWListener(using: params, on: nwPort)
                    self.listener = listener

                    listener.stateUpdateHandler = { [weak self] state in
                        if case .failed(let error) = state {
                            self?.finish(nil, AuthServerError.listenerFailed(error.localizedDescription))
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        connection.start(queue: .global(qos: .userInitiated))
                        Self.readRequestLine(connection) { query in
                            Self.respondAndClose(connection)
                            // Ignore favicon/probe/preconnect requests that reach the
                            // port first — only the redirect carrying code/error counts.
                            if query["code"] != nil || query["error"] != nil {
                                self?.finish(query, nil)
                            }
                        }
                    }
                    listener.start(queue: .global(qos: .userInitiated))
                } catch {
                    finish(nil, AuthServerError.listenerFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            finish(nil, CancellationError())
        }
    }

    // Read enough bytes to capture the HTTP request line and parse its query.
    private static func readRequestLine(_ conn: NWConnection, _ done: @escaping ([String: String]) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n", maxSplits: 1).first else {
                done([:]); return
            }
            // "GET /auth-callback?code=…&state=… HTTP/1.1"
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { done([:]); return }
            done(parseQuery(String(parts[1])))
        }
    }

    private static func parseQuery(_ target: String) -> [String: String] {
        guard let queryPart = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return [:] }
        var result: [String: String] = [:]
        for pair in queryPart.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            result[String(key)] = value.removingPercentEncoding ?? value
        }
        return result
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
