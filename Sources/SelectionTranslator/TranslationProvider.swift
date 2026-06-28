import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable {
    case openAICompatible = "openai_compatible"
    case anthropicNative = "anthropic_native"
    case deepLX = "deeplx"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI 兼容"
        case .anthropicNative:
            return "Anthropic 原生"
        case .deepLX:
            return "DeepLX"
        }
    }

    var defaultAPIURL: String {
        switch self {
        case .openAICompatible:
            return OpenAITranslator.defaultAPIURL
        case .anthropicNative:
            return AnthropicTranslator.defaultAPIURL
        case .deepLX:
            return DeepLXTranslator.defaultAPIURL
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible:
            return OpenAITranslator.defaultModel
        case .anthropicNative:
            return AnthropicTranslator.defaultModel
        case .deepLX:
            return DeepLXTranslator.defaultModel
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openAICompatible, .anthropicNative:
            return true
        case .deepLX:
            return false
        }
    }

    var supportsModelSelection: Bool {
        switch self {
        case .openAICompatible, .anthropicNative:
            return true
        case .deepLX:
            return false
        }
    }

    static func savedValue() -> TranslationProvider {
        guard let value = UserDefaults.standard.string(forKey: SettingsKeys.provider),
              let provider = TranslationProvider(rawValue: value)
        else {
            return .openAICompatible
        }
        return provider
    }
}
