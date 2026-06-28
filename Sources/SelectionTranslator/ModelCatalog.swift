import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String

    var displayName: String { id }
}

final class ModelCatalog {
    private let session: URLSession

    init(timeout: TimeInterval = 12) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 3
        self.session = URLSession(configuration: configuration)
    }

    private struct OpenAIModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private struct AnthropicModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }

        let data: [Model]
    }

    func fetchModels(provider: TranslationProvider, apiURL: String, apiKey: String) async throws -> [ModelInfo] {
        switch provider {
        case .openAICompatible:
            return try await fetchOpenAICompatibleModels(apiURL: apiURL, apiKey: apiKey)
        case .anthropicNative:
            return try await fetchAnthropicModels(apiURL: apiURL, apiKey: apiKey)
        case .deepLX:
            return []
        }
    }

    private func fetchOpenAICompatibleModels(apiURL: String, apiKey: String) async throws -> [ModelInfo] {
        let url = try APIEndpointValidator.normalizedOpenAIModelsURL(from: apiURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await data(for: request, providerName: "OpenAI", url: url)
        try validateHTTPResponse(response, data: data, providerName: "OpenAI", url: url)

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return uniqueSortedModels(decoded.data.map(\.id))
    }

    private func fetchAnthropicModels(apiURL: String, apiKey: String) async throws -> [ModelInfo] {
        let url = try AnthropicTranslator.normalizedModelsURL(from: apiURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await data(for: request, providerName: "Anthropic", url: url)
        try validateHTTPResponse(response, data: data, providerName: "Anthropic", url: url)

        let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
        return uniqueSortedModels(decoded.data.map(\.id))
    }

    private func data(for request: URLRequest, providerName: String, url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw OpenAITranslatorError.networkError("\(providerName) 模型列表请求失败：\(networkReason(for: error))\n请求地址：\(url.absoluteString)")
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, providerName: String, url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranslatorError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = responseText?.isEmpty == false ? "\n响应内容：\(responseText!)" : ""
            throw OpenAITranslatorError.apiError("\(providerName) 模型列表请求失败：HTTP \(httpResponse.statusCode)\n请求地址：\(url.absoluteString)\(detail)")
        }
    }

    private func uniqueSortedModels(_ ids: [String]) -> [ModelInfo] {
        Array(Set(ids))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
            .map(ModelInfo.init(id:))
    }

    private func networkReason(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            return "请求超时"
        case .notConnectedToInternet:
            return "网络未连接"
        case .cannotFindHost:
            return "找不到服务器"
        case .cannotConnectToHost:
            return "无法连接服务器"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            return "HTTPS 证书校验失败"
        case .cancelled:
            return "请求已取消"
        default:
            return error.localizedDescription
        }
    }
}
