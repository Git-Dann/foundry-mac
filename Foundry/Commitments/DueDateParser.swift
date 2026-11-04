import Foundation

/// Reads a due date off the end of a quick-add line: "Send Acme the deck fri" → ("Send Acme the
/// deck", Friday 17:00). Only the END of the line is read, and only words that can mean nothing
/// else, so a title like "Call Monday.com" or "Review the 3 options" is left alone.
///
/// Understood: today, tonight, tomorrow/tmrw, mon…sun (and full names), "next mon", "next week",
/// "in N days/weeks", "eod", "eow", and "23 nov" / "nov 23". Dates land at 17:00 local; "tonight"
/// at 20:00. A bare weekday means the next one after today (on a Friday, "fri" is next Friday).
enum DueDateParser {
    struct Result: Equatable {
        var title: String
        var dueAt: Date?
        /// The words that were read as the date, for the "Due Friday" hint under the field.
        var matched: String?
    }

    static let defaultHour = 17

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return Result(title: trimmed, dueAt: nil, matched: nil) }

        // Longest phrase first: 3 words ("in 3 days"), then 2 ("next fri", "23 nov"), then 1.
        for length in [3, 2, 1] where words.count > length {
            let tail = Array(words.suffix(length))
            let phrase = tail.joined(separator: " ").lowercased().trimmingCharacters(in: .punctuationCharacters)
            if let date = date(for: phrase, now: now, calendar: calendar) {
                words.removeLast(length)
                // Drop a dangling connective: "Send the deck by fri" → "Send the deck".
                if let last = words.last?.lowercased(), ["by", "on", "due", "for", "before"].contains(last), words.count > 1 {
                    words.removeLast()
                }
                return Result(title: words.joined(separator: " "), dueAt: date, matched: tail.joined(separator: " "))
            }
        }
        return Result(title: trimmed, dueAt: nil, matched: nil)
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    static func date(for phrase: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Date, hour: Int = defaultHour) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }
        func plusDays(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today)! }
        func nextWeekday(_ weekday: Int, skipThisWeek: Bool = false) -> Date {
            var from = today
            if skipThisWeek, let weekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end {
                // "next fri" means the Friday of next week, whatever day it is now.
                from = weekEnd.addingTimeInterval(-1)
            }
            return calendar.nextDate(after: from, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)!
        }

        let parts = phrase.split(separator: " ").map(String.init)
        switch parts.count {
        case 1:
            let w = parts[0]
            switch w {
            case "today", "eod": return at(today)
            case "tonight": return at(today, hour: 20)
            case "tomorrow", "tmrw", "tmr", "tomorow": return at(plusDays(1))
            case "eow": return at(nextWeekdayOrToday(6, today: today, calendar: calendar))
            default:
                if let wd = weekdays[w] { return at(nextWeekday(wd)) }
                return nil
            }
        case 2:
            let (a, b) = (parts[0], parts[1])
            if a == "next", b == "week" { return at(nextWeekday(calendar.firstWeekday, skipThisWeek: true)) }
            if a == "next", let wd = weekdays[b] { return at(nextWeekday(wd, skipThisWeek: true)) }
            if let day = Int(a), let month = months[b] { return dayMonth(day, month, now: now, calendar: calendar).map { at($0) } }
            if let month = months[a], let day = Int(b) { return dayMonth(day, month, now: now, calendar: calendar).map { at($0) } }
            return nil
        case 3:
            guard parts[0] == "in", let n = Int(parts[1]), (1...365).contains(n) else { return nil }
            switch parts[2] {
            case "day", "days": return at(plusDays(n))
            case "week", "weeks": return at(plusDays(7 * n))
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func nextWeekdayOrToday(_ weekday: Int, today: Date, calendar: Calendar) -> Date {
        if calendar.component(.weekday, from: today) == weekday { return today }
        return calendar.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)!
    }

    /// "23 nov": this year's, or next year's once this year's has passed.
    private static func dayMonth(_ day: Int, _ month: Int, now: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        for y in [year, year + 1] {
            var c = DateComponents(year: y, month: month, day: day)
            c.hour = 0
            guard let d = calendar.date(from: c), calendar.component(.day, from: d) == day else { return nil }
            if d >= calendar.startOfDay(for: now) { return d }
        }
        return nil
    }
}
