import Foundation

enum Formatters {
    static func currency(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        return formatter.string(from: amount as NSNumber) ?? "\(amount) \(code)"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func medium(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Human duration from milliseconds: "820ms", "4.2s", "3m 12s".
    static func duration(ms: Double) -> String {
        guard ms.isFinite, ms > 0 else { return "—" }
        let seconds = ms / 1000
        if seconds < 1 { return String(format: "%.0fms", ms) }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let whole = Int(seconds.rounded())
        return "\(whole / 60)m \(whole % 60)s"
    }

    /// A 0–1 fraction as a whole-number percentage: 0.62 → "62%".
    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", (fraction.isFinite ? fraction : 0) * 100)
    }
}

extension Error {
    /// User-facing message for any thrown error.
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// `nil` when the trimmed string is empty — handy for optional API fields.
    var nilIfEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}
