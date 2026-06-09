import Foundation

enum OpenAITranslatorError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case apiError(String)
    case missingContent

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "API URL 无效：\(value)"
        case .invalidResponse:
            return "OpenAI 返回了无法识别的响应。"
        case .apiError(let message):
            return message
        case .missingContent:
            return "OpenAI 响应中没有译文。"
        }
    }
}

final class OpenAITranslator {
    static let defaultAPIURL = "https://api.openai.com/v1/chat/completions"
    static let defaultModel = "gpt-4.1-mini"

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    func translateToChinese(_ text: String, apiURL: String, apiKey: String, model: String) async throws -> String {
        let url = try chatCompletionsURL(from: apiURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(
                    role: "system",
                    content: """
                    You translate English technical text into concise, natural Simplified Chinese.
                    Preserve code, commands, file paths, variable names, product names, error codes, URLs, and stack trace frames exactly when possible.
                    If the text already contains Chinese, keep it natural and only translate the English parts.
                    Return only the Chinese translation or explanation, with no preamble.
                    """
                ),
                .init(role: "user", content: text)
            ],
            temperature: 0.2
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslatorError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OpenAITranslatorError.apiError("\(errorResponse.error.message)\n请求地址：\(url.absoluteString)")
            }

            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = responseText?.isEmpty == false ? "\n响应内容：\(responseText!)" : ""
            throw OpenAITranslatorError.apiError("OpenAI 请求失败：HTTP \(httpResponse.statusCode)\n请求地址：\(url.absoluteString)\(detail)")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw OpenAITranslatorError.missingContent
        }

        return content
    }

    private func chatCompletionsURL(from value: String) throws -> URL {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue), let scheme = components.scheme, !scheme.isEmpty, components.host != nil else {
            throw OpenAITranslatorError.invalidURL(trimmedValue)
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        }

        guard let url = components.url else {
            throw OpenAITranslatorError.invalidURL(trimmedValue)
        }
        return url
    }
}
