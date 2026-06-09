import Foundation

/// Workspace AI-provider configuration (GET /api/settings/integrations — bare object). Keys are
/// MASKED by the server; `*KeySource` says whether the value comes from an env var or the DB.
struct SettingsIntegrations: Decodable, Sendable {
    let aiProvider: String
    let anthropicKeyMasked: String?
    let anthropicKeySource: String?
    let anthropicModel: String?
    let openaiKeyMasked: String?
    let openaiKeySource: String?
    let openaiModel: String?
    let geminiKeyMasked: String?
    let geminiKeySource: String?
    let geminiModel: String?
    let localLlmUrl: String?
    let localLlmModel: String?
}

/// PUT /api/settings/integrations — only the fields you set are sent.
struct IntegrationsUpdate: Encodable, Sendable {
    var aiProvider: String?
    var anthropicApiKey: String?
    var anthropicModel: String?
    var openaiApiKey: String?
    var openaiModel: String?
    var geminiApiKey: String?
    var geminiModel: String?
    var localLlmUrl: String?
    var localLlmModel: String?

    enum CodingKeys: String, CodingKey {
        case aiProvider, anthropicApiKey, anthropicModel, openaiApiKey, openaiModel, geminiApiKey, geminiModel, localLlmUrl, localLlmModel
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(aiProvider, forKey: .aiProvider)
        try c.encodeIfPresent(anthropicApiKey, forKey: .anthropicApiKey)
        try c.encodeIfPresent(anthropicModel, forKey: .anthropicModel)
        try c.encodeIfPresent(openaiApiKey, forKey: .openaiApiKey)
        try c.encodeIfPresent(openaiModel, forKey: .openaiModel)
        try c.encodeIfPresent(geminiApiKey, forKey: .geminiApiKey)
        try c.encodeIfPresent(geminiModel, forKey: .geminiModel)
        try c.encodeIfPresent(localLlmUrl, forKey: .localLlmUrl)
        try c.encodeIfPresent(localLlmModel, forKey: .localLlmModel)
    }
}

/// The four AI providers selectable in Settings.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic = "ANTHROPIC", openai = "OPENAI", gemini = "GEMINI", local = "LOCAL"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .local: return "Local"
        }
    }
}
