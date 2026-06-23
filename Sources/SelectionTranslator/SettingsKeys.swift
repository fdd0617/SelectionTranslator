enum SettingsKeys {
    static let provider = "translation_provider"
    static let apiURL = "openai_api_url"
    static let model = "openai_model"
    static let automaticTranslationEnabled = "automatic_translation_enabled"

    static func apiURL(for provider: TranslationProvider) -> String {
        switch provider {
        case .openAICompatible:
            return apiURL
        case .anthropicNative:
            return "anthropic_api_url"
        }
    }

    static func model(for provider: TranslationProvider) -> String {
        switch provider {
        case .openAICompatible:
            return model
        case .anthropicNative:
            return "anthropic_model"
        }
    }
}
