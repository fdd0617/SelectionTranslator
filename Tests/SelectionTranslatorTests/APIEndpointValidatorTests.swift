import XCTest
@testable import SelectionTranslator

final class APIEndpointValidatorTests: XCTestCase {
    func testNormalizesBaseURLToChatCompletionsEndpoint() throws {
        let url = try APIEndpointValidator.normalizedChatCompletionsURLString(from: "https://api.example.com/v1")

        XCTAssertEqual(url, "https://api.example.com/v1/chat/completions")
    }

    func testKeepsExistingChatCompletionsEndpoint() throws {
        let url = try APIEndpointValidator.normalizedChatCompletionsURLString(from: "https://api.example.com/v1/chat/completions")

        XCTAssertEqual(url, "https://api.example.com/v1/chat/completions")
    }

    func testRequiresHTTPS() {
        XCTAssertThrowsError(try APIEndpointValidator.normalizedChatCompletionsURLString(from: "http://api.example.com/v1")) { error in
            guard case OpenAITranslatorError.insecureURL = error else {
                return XCTFail("Expected insecureURL, got \(error)")
            }
        }
    }

    func testRejectsInvalidURL() {
        XCTAssertThrowsError(try APIEndpointValidator.normalizedChatCompletionsURLString(from: "not a url")) { error in
            guard case OpenAITranslatorError.invalidURL = error else {
                return XCTFail("Expected invalidURL, got \(error)")
            }
        }
    }

    func testNormalizesOpenAIModelsEndpointFromBaseURL() throws {
        let url = try APIEndpointValidator.normalizedOpenAIModelsURL(from: "https://api.example.com/v1")

        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/models")
    }

    func testNormalizesOpenAIModelsEndpointFromChatCompletionsURL() throws {
        let url = try APIEndpointValidator.normalizedOpenAIModelsURL(from: "https://api.example.com/v1/chat/completions")

        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/models")
    }

    func testNormalizesAnthropicModelsEndpointFromBaseURL() throws {
        let url = try AnthropicTranslator.normalizedModelsURL(from: "https://api.anthropic.com/v1")

        XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/v1/models")
    }

    func testNormalizesAnthropicModelsEndpointFromMessagesURL() throws {
        let url = try AnthropicTranslator.normalizedModelsURL(from: "https://api.anthropic.com/v1/messages")

        XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/v1/models")
    }
}
