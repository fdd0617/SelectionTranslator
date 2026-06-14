import Foundation

enum APIEndpointValidator {
    static func normalizedChatCompletionsURL(from value: String) throws -> URL {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty,
              components.host != nil
        else {
            throw OpenAITranslatorError.invalidURL(trimmedValue)
        }

        guard scheme == "https" else {
            throw OpenAITranslatorError.insecureURL(trimmedValue)
        }

        components.scheme = scheme

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        }

        guard let url = components.url else {
            throw OpenAITranslatorError.invalidURL(trimmedValue)
        }
        return url
    }

    static func normalizedChatCompletionsURLString(from value: String) throws -> String {
        try normalizedChatCompletionsURL(from: value).absoluteString
    }
}
