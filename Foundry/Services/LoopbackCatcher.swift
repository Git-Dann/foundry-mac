import Foundation
import Network

/// A one-shot loopback HTTP listener that captures the OAuth `code` Google redirects to
/// `http://127.0.0.1:<port>` after consent in the user's default browser. Handles exactly the
/// first request, replies with a friendly page, and resolves with the code (or throws on error /
/// timeout). Used by the PKCE desktop flow — no custom URL scheme, no embedded browser.
final class LoopbackCatcher: @unchecked Sendable {
    private var listener: NWListener?
    private let lock = NSLock()
    private var finished = false

    /// Start listening on an OS-assigned localhost port; returns that port.
    func start() async throws -> UInt16 {
        // Bind to 127.0.0.1 ONLY — this listener exists solely to catch the browser's local
        // OAuth redirect; it must never be reachable from other devices on the network.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: AppError.network("Couldn't open a local sign-in port."))
                    }
                case .failed(let error):
                    continuation.resume(throwing: AppError.network(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: AppError.cancelled)
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Await the redirect and extract `code` (or throw on `error` / timeout).
    func awaitCode(timeout: TimeInterval = 300) async throws -> String {
        guard let listener else { throw AppError.network("Sign-in listener not started.") }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.receiveFirstRequest(listener: listener) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AppError.authenticationFailed("Google sign-in timed out.")
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func resolveOnce(_ continuation: CheckedContinuation<String, Error>, _ result: Result<String, Error>) {
        lock.lock()
        let shouldResume = !finished
        if shouldResume { finished = true }
        lock.unlock()
        guard shouldResume else { return }
        switch result {
        case .success(let code): continuation.resume(returning: code)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private func receiveFirstRequest(listener: NWListener) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                // Only ever handle the very first connection (ignore favicon etc.).
                listener.newConnectionHandler = nil
                connection.start(queue: .global(qos: .userInitiated))
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    let body = "<!doctype html><html><head><meta charset='utf-8'><title>Foundry</title></head><body style='font-family:-apple-system,sans-serif;text-align:center;padding:64px;color:#0F172A'><h2>Connected to Google Calendar</h2><p>You can close this tab and return to Foundry.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })

                    guard let data, let request = String(data: data, encoding: .utf8) else {
                        self.resolveOnce(continuation, .failure(AppError.authenticationFailed("Empty sign-in redirect.")))
                        return
                    }
                    // First line: "GET /?code=...&scope=... HTTP/1.1"
                    guard let requestLine = request.split(separator: "\r\n").first,
                          let pathField = requestLine.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: "http://127.0.0.1\(pathField)") else {
                        self.resolveOnce(continuation, .failure(AppError.authenticationFailed("Malformed sign-in redirect.")))
                        return
                    }
                    if let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                        self.resolveOnce(continuation, .success(code))
                    } else if let errorCode = components.queryItems?.first(where: { $0.name == "error" })?.value {
                        self.resolveOnce(continuation, .failure(AppError.authenticationFailed("Google sign-in failed (\(errorCode)).")))
                    } else {
                        self.resolveOnce(continuation, .failure(AppError.authenticationFailed("No authorization code in redirect.")))
                    }
                }
            }
        }
    }
}
