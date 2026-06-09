import Foundation

/// Transport-agnostic request description. Mirrors the iOS app's `APIRequest`.
struct APIRequest {
    var url: URL
    var method: String = "GET"
    var headers: [String: String] = [:]
    var queryItems: [URLQueryItem] = []
    var body: Data?
}

/// Thin async/await wrapper over `URLSession`. Mirrors the iOS app's `NetworkClient` so the
/// Mac client behaves identically against the live API, with richer error surfacing (it
/// extracts the API's `{ "error": "…" }` message and preserves the HTTP status for 401 handling).
final class NetworkClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func execute<T: Decodable>(_ request: APIRequest, decoder: JSONDecoder = .foundry) async throws -> T {
        let data = try await executeData(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding("Couldn't read the server response: \(error.localizedDescription)")
        }
    }

    func executeWithoutResponse(_ request: APIRequest) async throws {
        _ = try await executeData(request)
    }

    @discardableResult
    func executeData(_ request: APIRequest) async throws -> Data {
        var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        if !request.queryItems.isEmpty {
            components?.queryItems = request.queryItems
        }
        guard let url = components?.url else {
            throw AppError.network("Invalid URL for request.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }
        if request.body != nil, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AppError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("Unexpected response from the server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = Self.decodeErrorMessage(from: data)
                ?? (String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "")
            throw AppError.http(status: http.statusCode, message: message)
        }
        return data
    }

    /// Foundry API errors are `{ "error": "message", "details"?: … }`.
    private static func decodeErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["error"] as? String
    }
}
