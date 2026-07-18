//
//  AiProvider.swift
//  SwiftTermApp
//
//  Provider configurations for the AI layer: Anthropic, OpenAI and
//  OpenAI-compatible endpoints, and Google Gemini.  Non-secret settings are
//  stored in UserDefaults, API keys go to the keychain (same conventions as
//  host passwords, see KeychainTools.swift).
//

import Foundation
import Security

/// The kind of API surface a provider speaks.  "Compatible" endpoints
/// (proxies, self-hosted gateways) use the same kind with a custom base URL.
enum AiProviderKind: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    var defaultBaseUrl: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-8"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .anthropic: return ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]
        case .openai: return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        case .gemini: return ["gemini-2.5-pro", "gemini-2.5-flash"]
        }
    }
}

/// One configured provider.  The API key is not part of this struct — it
/// lives in the keychain, addressed by `id`.
struct AiProviderConfig: Codable, Identifiable, Equatable {
    var id = UUID ()
    var name: String
    var kind: AiProviderKind
    var baseUrl: String
    var model: String

    /// A fresh config pre-filled with the kind's defaults
    static func makeDefault (kind: AiProviderKind, name: String? = nil) -> AiProviderConfig {
        AiProviderConfig (name: name ?? kind.displayName,
                          kind: kind,
                          baseUrl: kind.defaultBaseUrl,
                          model: kind.defaultModel)
    }

    /// True when the base URL is not the stock endpoint for the kind
    var isCustomEndpoint: Bool {
        baseUrl != kind.defaultBaseUrl
    }
}

/// What language the model should answer in
enum AiAnswerLanguage: String, Codable, CaseIterable, Identifiable {
    /// Follow the question, falling back to the language of the terminal output
    case auto
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Match my question"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// Appended to every system prompt
    var instruction: String {
        switch self {
        case .auto:
            return "Answer in the language the user's question is written in, defaulting to the language of the output."
        case .english:
            return "Always answer in English, even when the output or question is in another language."
        case .chinese:
            return "总是用中文回答，即使输出或问题是其他语言。Technical identifiers (commands, paths, error strings) stay in their original form."
        }
    }
}

/// Keychain query for AI provider API keys, mirroring getHostPasswordQuery
func getAiApiKeyQuery (id: String, password: String?, fetch: Bool = false, split: Bool = false, forDelete: Bool = false) -> (CFDictionary, CFDictionary) {
    return _getPassphraseQuery (kind: "SwiftTermAppAiApiKey", value: id, password: password, fetch: fetch, split: split, forDelete: forDelete)
}

/// Holds the list of configured AI providers and which one is active.
/// Configs persist in UserDefaults, keys in the keychain.
class AiProviderStore: ObservableObject {
    static let shared = AiProviderStore ()

    let defaults = UserDefaults (suiteName: "SwiftTermApp")
    static let providersKey = "aiProviders"
    static let activeKey = "aiActiveProviderId"

    @Published var providers: [AiProviderConfig] {
        didSet { save () }
    }

    @Published var activeProviderId: UUID? {
        didSet {
            defaults?.set (activeProviderId?.uuidString, forKey: AiProviderStore.activeKey)
        }
    }

    static let languageKey = "aiAnswerLanguage"
    static let explainLinesKey = "aiExplainLines"
    static let diagnoseLinesKey = "aiDiagnoseLines"

    @Published var answerLanguage: AiAnswerLanguage {
        didSet { defaults?.set (answerLanguage.rawValue, forKey: AiProviderStore.languageKey) }
    }

    /// Buffer lines sent when nothing is selected
    @Published var explainLines: Int {
        didSet { defaults?.set (explainLines, forKey: AiProviderStore.explainLinesKey) }
    }

    @Published var diagnoseLines: Int {
        didSet { defaults?.set (diagnoseLines, forKey: AiProviderStore.diagnoseLinesKey) }
    }

    init () {
        if let raw = defaults?.string (forKey: AiProviderStore.languageKey),
           let lang = AiAnswerLanguage (rawValue: raw) {
            answerLanguage = lang
        } else {
            answerLanguage = .auto
        }
        let explain = defaults?.integer (forKey: AiProviderStore.explainLinesKey) ?? 0
        explainLines = explain > 0 ? explain : 80
        let diagnose = defaults?.integer (forKey: AiProviderStore.diagnoseLinesKey) ?? 0
        diagnoseLines = diagnose > 0 ? diagnose : 150

        if let data = defaults?.data (forKey: AiProviderStore.providersKey),
           let decoded = try? JSONDecoder ().decode ([AiProviderConfig].self, from: data) {
            providers = decoded
        } else {
            providers = []
        }
        if let idStr = defaults?.string (forKey: AiProviderStore.activeKey), let id = UUID (uuidString: idStr) {
            activeProviderId = id
        } else {
            activeProviderId = nil
        }
    }

    func save () {
        if let data = try? JSONEncoder ().encode (providers) {
            defaults?.set (data, forKey: AiProviderStore.providersKey)
        }
    }

    /// The provider requests should go to, nil if none configured/selected
    var active: AiProviderConfig? {
        guard let id = activeProviderId else { return nil }
        return providers.first { $0.id == id }
    }

    func upsert (_ config: AiProviderConfig) {
        if let idx = providers.firstIndex (where: { $0.id == config.id }) {
            providers [idx] = config
        } else {
            providers.append (config)
        }
        // First provider added becomes active automatically
        if activeProviderId == nil {
            activeProviderId = config.id
        }
    }

    func remove (_ config: AiProviderConfig) {
        deleteApiKey (for: config)
        providers.removeAll { $0.id == config.id }
        if activeProviderId == config.id {
            activeProviderId = providers.first?.id
        }
    }

    // MARK: keychain-backed API keys

    func apiKey (for config: AiProviderConfig) -> String {
        let (query, _) = getAiApiKeyQuery (id: config.id.uuidString, password: nil, fetch: true)
        var itemCopy: AnyObject?
        let status = SecItemCopyMatching (query, &itemCopy)
        if status != 0 {
            return ""
        }
        if let d = itemCopy as? Data {
            return String (bytes: d, encoding: .utf8) ?? ""
        }
        return ""
    }

    @discardableResult
    func setApiKey (for config: AiProviderConfig, key: String) -> OSStatus {
        if key.isEmpty {
            deleteApiKey (for: config)
            return errSecSuccess
        }
        let (query, _) = getAiApiKeyQuery (id: config.id.uuidString, password: key)
        let status = SecItemAdd (query, nil)
        if status == errSecDuplicateItem {
            let (query2, update) = getAiApiKeyQuery (id: config.id.uuidString, password: key, split: true)
            return SecItemUpdate (query2, update)
        }
        return status
    }

    func deleteApiKey (for config: AiProviderConfig) {
        let (query, _) = getAiApiKeyQuery (id: config.id.uuidString, password: nil, forDelete: true)
        SecItemDelete (query)
    }
}
