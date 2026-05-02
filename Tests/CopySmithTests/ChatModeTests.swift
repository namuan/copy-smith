import XCTest
@testable import CopySmith

final class ChatModeTests: XCTestCase {


    func testExactlyEightModes() {
        XCTAssertEqual(ChatMode.all.count, 8)
    }

    func testModeOrder() {
        let titles = ChatMode.all.map(\.title)
        XCTAssertEqual(titles, [
            "Proofread", "Concise", "Professional", "Friendly",
            "Rewrite", "Summarise", "Explain", "Fallacy Finder"
        ])
    }

    func testModeIdsAreUnique() {
        let ids = ChatMode.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }


    func testBuildPrompt_containsPrefix() {
        let mode = ChatMode.all[0] // Proofread
        let text = "Hello world."
        let prompt = mode.buildPrompt(for: text)
        XCTAssertTrue(prompt.hasPrefix(mode.promptPrefix))
    }

    func testBuildPrompt_separatedByBlankLine() {
        let mode = ChatMode.all[0]
        let text = "Test input."
        let prompt = mode.buildPrompt(for: text)
        // Should be: prefix + "\n\n" + text
        let expected = "\(mode.promptPrefix)\n\n\(text)"
        XCTAssertEqual(prompt, expected)
    }


    func testRefinePrompt_containsModeTitles() {
        let proofread  = ChatMode.all.first(where: { $0.id == "proofread"  })!
        let concise    = ChatMode.all.first(where: { $0.id == "concise"    })!
        let blocks: [(mode: ChatMode, text: String)] = [
            (proofread, "Fixed text."),
            (concise, "Short text.")
        ]
        let prompt = ChatMode.buildRefinePrompt(blocks: blocks)
        XCTAssertTrue(prompt.contains("## Proofread"))
        XCTAssertTrue(prompt.contains("Fixed text."))
        XCTAssertTrue(prompt.contains("## Concise"))
        XCTAssertTrue(prompt.contains("Short text."))
    }

    func testRefinePrompt_blocksSeperatedByBlankLine() {
        let modes = Array(ChatMode.all.prefix(2))
        let blocks: [(mode: ChatMode, text: String)] = modes.map { ($0, "text") }
        let prompt = ChatMode.buildRefinePrompt(blocks: blocks)
        // Each block should be separated by \n\n
        XCTAssertTrue(prompt.contains("text\n\n## "))
    }
}
