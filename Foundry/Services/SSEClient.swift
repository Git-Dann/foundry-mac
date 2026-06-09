import Foundation

/// Minimal Server-Sent Events reader.
///
/// Yields the JSON string from each `data:` line of a `text/event-stream` response. Ignores SSE
/// comment keepalives (`: ping`) and `event:` / `id:` lines — the Foundry streams carry a `type`
/// discriminator *inside* the JSON payload instead. Cancelling the consuming `Task` tears down the
/// underlying URLSession byte stream via `onTermination`.
enum SSEClient {
    static func dataLines(
        for request: URLRequest,
        session: URLSession = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw AppError.http(status: http.statusCode, message: "Stream failed (\(http.statusCode)).")
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if !payload.isEmpty { continuation.yield(payload) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
