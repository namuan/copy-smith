import XCTest
@testable import CopySmith

final class SSEParserTests: XCTestCase {

    // MARK: payload(from:)

    func testPayload_stripsDataPrefix() {
        let line = #"data: {"choices":[{"delta":{"content":"hi"}}]}"#
        let payload = SSEParser.payload(from: line)
        XCTAssertNotNil(payload)
        XCTAssertTrue(payload!.hasPrefix("{"))
    }

    func testPayload_returnsNilForDone() {
        XCTAssertNil(SSEParser.payload(from: "data: [DONE]"))
        XCTAssertNil(SSEParser.payload(from: "[DONE]"))
    }

    func testPayload_returnsNilForEmptyLine() {
        XCTAssertNil(SSEParser.payload(from: ""))
        XCTAssertNil(SSEParser.payload(from: "  "))
    }

    func testPayload_noPrefix() {
        let raw = #"{"choices":[{"delta":{"content":"hello"}}]}"#
        let payload = SSEParser.payload(from: raw)
        XCTAssertEqual(payload, raw)
    }

    // MARK: isDone(_:)

    func testIsDone_withPrefix() {
        XCTAssertTrue(SSEParser.isDone("data: [DONE]"))
    }

    func testIsDone_withoutPrefix() {
        XCTAssertTrue(SSEParser.isDone("[DONE]"))
    }

    func testIsDone_falseForData() {
        XCTAssertFalse(SSEParser.isDone(#"data: {"choices":[]}"#))
    }

    // MARK: extractContent(from:)

    func testExtractContent_happyPath() {
        let payload = #"{"choices":[{"delta":{"content":"world"}}]}"#
        XCTAssertEqual(SSEParser.extractContent(from: payload), "world")
    }

    func testExtractContent_emptyDelta() {
        let payload = #"{"choices":[{"delta":{}}]}"#
        XCTAssertNil(SSEParser.extractContent(from: payload))
    }

    func testExtractContent_missingChoices() {
        let payload = #"{"id":"x"}"#
        XCTAssertNil(SSEParser.extractContent(from: payload))
    }

    func testExtractContent_multipleChoicesUsesFirst() {
        let payload = #"{"choices":[{"delta":{"content":"first"}},{"delta":{"content":"second"}}]}"#
        XCTAssertEqual(SSEParser.extractContent(from: payload), "first")
    }

    func testExtractContent_invalidJSON() {
        XCTAssertNil(SSEParser.extractContent(from: "not-json"))
    }
}
