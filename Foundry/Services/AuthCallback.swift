import Foundation

/// Parses the `foundry://auth-callback` deep link the web sign-in bridge redirects to.
/// The token arrives in the URL fragment (`#token=…`, preferred) or query (`?token=…`).
enum AuthCallback {
    static let scheme = "foundry"

    static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    static func token(from url: URL) -> String? { value(named: "token", in: url) }
    static func errorCode(from url: URL) -> String? { value(named: "error", in: url) }

    static func value(named name: String, in url: URL) -> String? {
        if let fragment = url.fragment, let v = parse(fragment, key: name) { return v }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == name })?.value {
            return v
        }
        return nil
    }

    private static func parse(_ encoded: String, key: String) -> String? {
        for pair in encoded.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == key {
                return kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return nil
    }
}
