import Foundation

/// Turns a source's failure message into a sentence a person can act on. The server passes some
/// AI provider errors through as raw JSON ("The AI read failed: 400 {…}").
enum SourceProblem {
    static func plain(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.contains("credit balance is too low") || lower.contains("insufficient_quota") || lower.contains("billing") {
            return "Foundry's AI credit has run out. An admin needs to top it up."
        }
        if lower.contains("authentication_error") || lower.contains("invalid x-api-key") || lower.contains("invalid api key") {
            return "Foundry's AI key isn't valid. An admin needs to update it in Foundry Settings → Integrations."
        }
        if lower.contains("rate_limit") || lower.contains("overloaded") || lower.contains(" 429 ") || lower.contains(" 529 ") {
            return "The AI service was busy. Foundry will try again on the next read."
        }
        // Otherwise keep the server's words, but never show a JSON blob.
        if let brace = text.firstIndex(of: "{") {
            let prefix = text[..<brace].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #":?\s*\d{3}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            let inner = innerMessage(String(text[brace...]))
            let joined = [prefix, inner].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ": ")
            return clip(joined.isEmpty ? "This source couldn't be read." : joined)
        }
        return clip(text)
    }

    /// The deepest "message" in a JSON error body.
    static func innerMessage(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func find(_ v: Any) -> String? {
            if let d = v as? [String: Any] {
                if let e = d["error"], let m = find(e) { return m }
                return d["message"] as? String
            }
            return nil
        }
        return find(obj)
    }

    private static func clip(_ s: String) -> String { s.count > 220 ? String(s.prefix(217)) + "…" : s }

    /// "Sent email and Slack are paused. <reason>". Nil when every source worked.
    static func summary(_ sources: [String: CommitmentSourceStatus]) -> String? {
        let failed = CommitmentSettings.Toggle.offered.compactMap { t -> (String, String)? in
            guard let s = sources[t.rawValue], !s.ok else { return nil }
            return (t.title, plain(s.message))
        }
        guard !failed.isEmpty else { return nil }
        let names = ListFormatter.localizedString(byJoining: failed.map(\.0))
        let reasons = Set(failed.map(\.1))
        return reasons.count == 1
            ? "\(names) \(failed.count == 1 ? "is" : "are") paused. \(reasons.first!)"
            : "\(names) \(failed.count == 1 ? "is" : "are") paused. See Settings → Sources."
    }
}
