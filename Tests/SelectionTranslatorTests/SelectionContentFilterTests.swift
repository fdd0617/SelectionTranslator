import XCTest
@testable import SelectionTranslator

final class SelectionContentFilterTests: XCTestCase {
    func testSkipsLongAlphaNumericTokens() {
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("a1b2c3d4e5f6g7h8"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("release_20260612_build_ABC123"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("9f86d081884c7d659a2feaa0c55ad015"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("ABC123DEF456GHI789"))
    }

    func testShortAlphaNumericTextStillTranslates() {
        XCTAssertTrue(SelectionContentFilter.shouldTranslate("error 404 means not found"))
        XCTAssertTrue(SelectionContentFilter.shouldTranslate("HTTP2 failed"))
    }

    func testSkipsPathLikeText() {
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("/Users/fan/Projects/Codex/SelectionTranslator"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("~/Downloads/archive"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("./Sources/SelectionTranslator/AppDelegate.swift"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("../logs/app.log"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("Sources/SelectionTranslator/AppDelegate.swift"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("C:\\Users\\fan\\Downloads"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("src/components/TranslationPanel/View.swift"))
    }

    func testExistingSkipRulesRemainActive() {
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("纯中文内容"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("123,456.78"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("https://example.com/v1"))
        XCTAssertFalse(SelectionContentFilter.shouldTranslate("   "))
    }

    func testMixedChineseAndEnglishStillTranslates() {
        XCTAssertTrue(SelectionContentFilter.shouldTranslate("这个 error means the request failed"))
    }
}
