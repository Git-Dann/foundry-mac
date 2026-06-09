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
