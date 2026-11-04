import Foundation

/// How a to-do reads on screen. The server writes calendar follow-ups as
/// "Follow up with luke.mcfarland@bigwedgegolf.com after “Wedge x Gitwork”"; nobody should have
/// to read an email address to know who that is.
enum Display {
    struct Lines: Equatable {
        var title: String
        var subtitle: String?
    }

    /// "luke.mcfarland@bigwedgegolf.com" → "Luke McFarland". Anything that isn't an address is
    /// returned as it is.
    static func person(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let at = s.firstIndex(of: "@"), at != s.startIndex else { return s }
        let local = s[..<at].split(whereSeparator: { ".-_+".contains($0) || $0.isNumber })
        let words = local.map(String.init).filter { $0.count > 1 }
        guard !words.isEmpty else { return s }
        // A single run of letters ("nasirjavediit") can't be split into a name; keep it readable.
        return words.map(capitalisedName).joined(separator: " ")
    }

    /// "luke@bigwedgegolf.com" → "bigwedgegolf.com". Domains can't be split into words reliably
    /// ("bigwedgegolf"), so the domain is shown as it is. Personal mail services say nothing.
    static func organisation(ofEmail raw: String) -> String? {
        guard let at = raw.firstIndex(of: "@") else { return nil }
        let host = raw[raw.index(after: at)...].lowercased()
        let personal = ["gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "icloud.com", "me.com", "yahoo.com", "live.com"]
        return personal.contains(host) || host.isEmpty ? nil : host
    }

    private static func capitalisedName(_ w: String) -> String {
        let lower = w.lowercased()
        // Mc/Mac surnames: "mcfarland" → "McFarland".
        if lower.hasPrefix("mc"), lower.count > 3 {
            return "Mc" + lower.dropFirst(2).prefix(1).uppercased() + lower.dropFirst(3)
        }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    static func lines(for c: Commitment) -> Lines {
        let pattern = #"^Follow up with (.+?) after [“"](.+)[”"]$"#
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: c.title, range: NSRange(c.title.startIndex..., in: c.title)),
           let whoR = Range(m.range(at: 1), in: c.title), let meetR = Range(m.range(at: 2), in: c.title) {
            let who = String(c.title[whoR])
            let meeting = String(c.title[meetR])
            let name = who.contains("@") ? person(who) : who
            let org = who.contains("@") ? organisation(ofEmail: who) : nil
            let after = "After “\(meeting)”"
            return Lines(title: "Follow up with \(name)", subtitle: [org, after].compactMap { $0 }.joined(separator: " · "))
        }
        // "[Handover] Confirm DPA signed" → "Confirm DPA signed", with "Handover" as the subtitle.
        if c.title.hasPrefix("["), let close = c.title.firstIndex(of: "]") {
            let tag = c.title[c.title.index(after: c.title.startIndex)..<close].trimmingCharacters(in: .whitespaces)
            let rest = c.title[c.title.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !tag.isEmpty, !rest.isEmpty, tag.count <= 30 { return Lines(title: rest, subtitle: tag) }
        }
        return Lines(title: c.title, subtitle: nil)
    }
}
