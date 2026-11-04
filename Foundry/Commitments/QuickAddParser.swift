import Foundation

/// The full quick-add grammar, TickTick-style, on top of `DueDateParser`:
///
///   Call Valu about the quote #sales !! ~Clients every week fri 3pm
///
/// `#tag` adds a tag, `!` `!!` `!!!` set priority, `~List` puts it in a list (by name, any case;
/// "~Big_Wedge" for spaces), `every …` repeats it, `someday` / `tonight` / `this evening` plan it,
/// a time ("3pm", "15:30") sets the time of the date. Tokens can sit anywhere in the line; the
/// date words are read off the end, as before. What's left is the title.
enum QuickAddParser {
    struct Result: Equatable {
        var title: String
        var dueAt: Date?
        var tags: [String] = []
        var priority = 0
        var listName: String?
        var recurrence: Recurrence?
        var startAt: Date?
        var evening = false
        var someday = false
        /// What was understood, for the hint under the field: ["Fri 15:00", "#sales", "High", …].
        var chips: [String] = []
    }

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        var r = Result(title: "")
        var words: [String] = []
        let raw = input.split(whereSeparator: \.isWhitespace).map(String.init)
        var i = 0
        var time: (h: Int, m: Int)?
        while i < raw.count {
            let w = raw[i]
            let lower = w.lowercased()
            if w.hasPrefix("#"), w.count > 1 {
                let tag = String(w.dropFirst()).lowercased().trimmingCharacters(in: .punctuationCharacters)
                if !tag.isEmpty, !r.tags.contains(tag) { r.tags.append(tag) }
            } else if w.allSatisfy({ $0 == "!" }), (1...3).contains(w.count) {
                r.priority = w.count
            } else if w.hasPrefix("~"), w.count > 1 {
                r.listName = String(w.dropFirst()).replacingOccurrences(of: "_", with: " ")
            } else if lower == "every", i + 1 < raw.count, let (rule, used) = recurrence(Array(raw[(i + 1)...])) {
                r.recurrence = rule
                i += used
            } else if lower == "someday" {
                r.someday = true
            } else if lower == "tonight" || (lower == "this" && i + 1 < raw.count && raw[i + 1].lowercased() == "evening") {
                r.evening = true
                r.startAt = calendar.startOfDay(for: now)
                if lower == "this" { i += 1 }
            } else if let t = parseTime(lower) {
                time = t
            } else {
                words.append(w)
            }
            i += 1
        }
        // Dates are read off the end of what's left, as the plain quick add always did.
        let dated = DueDateParser.parse(words.joined(separator: " "), now: now, calendar: calendar)
        r.title = dated.title
        r.dueAt = dated.dueAt
        if let time {
            let base = r.dueAt ?? (time.h * 60 + time.m > calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
                                   ? now : calendar.date(byAdding: .day, value: 1, to: now)!)
            r.dueAt = calendar.date(bySettingHour: time.h, minute: time.m, second: 0, of: base)
        }
        if r.someday { r.startAt = nil; r.evening = false }

        if let d = r.dueAt { r.chips.append(DueText.string(d, now: now, calendar: calendar)) }
        if r.evening { r.chips.append("This Evening") }
        if r.someday { r.chips.append("Someday") }
        if let rule = r.recurrence { r.chips.append(rule.title) }
        if r.priority > 0 { r.chips.append((Priority(rawValue: r.priority) ?? .none).title + " priority") }
        r.chips += r.tags.map { "#" + $0 }
        if let l = r.listName { r.chips.append("→ " + l) }
        return r
    }

    /// "3pm", "3:30pm", "15:30", "9am" → (hour, minute). Bare numbers are not times.
    static func parseTime(_ w: String) -> (h: Int, m: Int)? {
        let s = w.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: ":")))
        var body = s
        var meridiem: String?
        for m in ["am", "pm"] where body.hasSuffix(m) { meridiem = m; body = String(body.dropLast(2)) }
        let parts = body.split(separator: ":").map(String.init)
        guard (1...2).contains(parts.count), let h = Int(parts[0]) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) : 0
        guard let m, (0...59).contains(m) else { return nil }
        if let meridiem {
            guard (1...12).contains(h) else { return nil }
            return ((h % 12) + (meridiem == "pm" ? 12 : 0), m)
        }
        guard parts.count == 2, (0...23).contains(h) else { return nil }
        return (h, m)
    }

    /// Words after "every": "day", "weekday", "week", "2 weeks", "month", "year", "fortnight",
    /// "monday" (weekly). Returns the rule and how many words it used.
    static func recurrence(_ w: [String]) -> (Recurrence, Int)? {
        let a = w.first?.lowercased().trimmingCharacters(in: .punctuationCharacters) ?? ""
        switch a {
        case "day": return (.daily, 1)
        case "weekday": return (.weekdays, 1)
        case "week": return (.weekly, 1)
        case "fortnight": return (.fortnightly, 1)
        case "month": return (.monthly, 1)
        case "year": return (.yearly, 1)
        case "mon", "monday", "tue", "tuesday", "wed", "wednesday", "thu", "thursday", "fri", "friday", "sat", "saturday", "sun", "sunday":
            return (.weekly, 0) // "every friday": weekly; the weekday stays for the date reader.
        default:
            guard let n = Int(a), (1...365).contains(n), w.count > 1 else { return nil }
            let unit = w[1].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let u: Recurrence.Unit? = unit.hasPrefix("day") ? .day : unit.hasPrefix("week") ? .week : unit.hasPrefix("month") ? .month : nil
            guard let u else { return nil }
            return (n == 1 ? (u == .day ? .daily : u == .week ? .weekly : .monthly) : .every(n, u), 2)
        }
    }
}
