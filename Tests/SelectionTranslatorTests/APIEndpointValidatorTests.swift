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
}
