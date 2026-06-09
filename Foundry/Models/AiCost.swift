import Foundation

/// Real billed AI spend (today + month-to-date) from the provider Cost APIs.
///
/// Mirrors the web `AiCostSummary` returned by `GET /api/admin/ai-cost` (Super-Admin only;
/// the Mac app reaches it with the per-user JWT). The endpoint never throws to the client —
/// each provider carries its own `status` so the UI renders gracefully — but the *route* is
/// 403 for non-super-admins, which callers treat as "spend unavailable".
struct AiCostSummary: Codable, Sendable {
    var providers: [ProviderCost]
    /// True when at least one provider has an admin key configured server-side.
    var configured: Bool
    var fetchedAt: String

    var hasError: Bool { providers.contains { $0.status == .error } }
    var totalToday: Double { providers.reduce(0) { $0 + $1.today } }
    var totalMonthToDate: Double { providers.reduce(0) { $0 + $1.monthToDate } }

    /// The shared currency code when every provider agrees (USD in practice), else nil.
    var commonCurrency: String? {
        let codes = Set(providers.map(\.currency))
        return codes.count == 1 ? codes.first : providers.first?.currency
    }
}

struct ProviderCost: Codable, Sendable, Identifiable {
    enum Provider: String, Codable, Sendable {
        case anthropic = "ANTHROPIC"
        case openai = "OPENAI"
        case unknown = "UNKNOWN"

        // Tolerate a future provider value without failing the whole decode.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Provider(rawValue: raw) ?? .unknown
        }
    }

    enum Status: String, Codable, Sendable {
        case ok
        case notConfigured = "not_configured"
        case error
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    var provider: Provider
    var status: Status
    var today: Double
    var monthToDate: Double
    var currency: String
    var modelLabel: String?
    var error: String?

    var id: String { provider.rawValue }

    var providerLabel: String {
        switch provider {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .unknown: return "Provider"
        }
    }
}
