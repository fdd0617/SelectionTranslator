import Foundation

enum DeepLXTranslatorError: LocalizedError {
    case invalidURL(String)
    case insecureURL(String)
    case invalidResponse
    case apiError(String)
    case missingContent

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "DeepLX API URL 无效：\(value)"
        case .insecureURL(let value):
            return "DeepLX 远程 API URL 必须使用 HTTPS：\(value)"
        case .invalidResponse:
            return "DeepLX 返回了无法识别的响应。"
        case .apiError(let message):
            return message
        case .missingContent:
            return "DeepLX 响应中没有译文。"
        }
    }
}

final class DeepLXTranslator {
    static let defaultAPIURL = "http://127.0.0.1:1188/translate"
    static let defaultModel = "deeplx"

    private let session: URLSession

    init(timeout: TimeInterval = 12) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 3
        self.session = URLSession(configuration: configuration)
    }

    private struct TranslateRequest: Encodable {
        let text: String
        let sourceLang: String
        let targetLang: String

        enum CodingKeys: String, CodingKey {
            case text
            case sourceLang = "source_lang"
            case targetLang = "target_lang"
        }
    }

    private struct TranslateResponse: Decodable {
        let code: Int?
        let message: String?
        let data: String?
        let alternatives: [String]?
    }

    func translateToChinese(_ text: String, apiURL: String, apiKey: String) async throws -> String {
        let url = try Self.normalizedTranslateURL(from: apiURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(
            TranslateRequest(text: text, sourceLang: "auto", targetLang: "ZH")
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw DeepLXTranslatorError.apiError(networkErrorMessage(for: error, url: url))
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepLXTranslatorError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = responseText?.isEmpty == false ? "\n响应内容：\(responseText!)" : ""
            throw DeepLXTranslatorError.apiError("DeepLX 请求失败：HTTP \(httpResponse.statusCode)\n请求地址：\(url.absoluteString)\(detail)")
        }

        let decoded = try JSONDecoder().decode(TranslateResponse.self, from: data)
        if let code = decoded.code, code != 200 {
            let message = decoded.message?.isEmpty == false ? decoded.message! : "DeepLX 返回错误码 \(code)"
            throw DeepLXTranslatorError.apiError("\(message)\n请求地址：\(url.absoluteString)")
        }

        if let content = decoded.data?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }

        if let alternative = decoded.alternatives?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !alternative.isEmpty {
            return alternative
        }

        throw DeepLXTranslatorError.missingContent
    }

    static func normalizedTranslateURL(from value: String) throws -> URL {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedValue),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty,
              let host = components.host
        else {
            throw DeepLXTranslatorError.invalidURL(trimmedValue)
        }

        guard scheme == "https" || (scheme == "http" && isLocalhost(host)) else {
            throw DeepLXTranslatorError.insecureURL(trimmedValue)
        }

        components.scheme = scheme
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("translate") {
            components.path = "/" + ([path, "translate"].filter { !$0.isEmpty }.joined(separator: "/"))
        }

        guard let url = components.url else {
            throw DeepLXTranslatorError.invalidURL(trimmedValue)
        }
        return url
    }

    static func normalizedTranslateURLString(from value: String) throws -> String {
        try normalizedTranslateURL(from: value).absoluteString
    }

    private static func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func networkErrorMessage(for error: URLError, url: URL) -> String {
        let reason: String
        switch error.code {
        case .timedOut:
            reason = "请求超时"
        case .notConnectedToInternet:
            reason = "网络未连接"
        case .cannotFindHost:
            reason = "找不到服务器"
        case .cannotConnectToHost:
            reason = "无法连接服务器"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            reason = "HTTPS 证书校验失败"
        case .cancelled:
            reason = "请求已取消"
        default:
            reason = error.localizedDescription
        }

        return "DeepLX 请求失败：\(reason)\n请求地址：\(url.absoluteString)"
    }
}
