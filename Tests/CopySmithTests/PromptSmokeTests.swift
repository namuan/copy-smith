import XCTest
import Darwin
@testable import CopySmith

/// Integration smoke test: loads the default GGUF model and verifies every
/// ChatMode produces non-empty output for a fixed sample text.
///
/// Run with:
///   swift test --filter PromptSmokeTests
///
/// Requirements:
///   - A GGUF model in ~/.cache/huggingface/hub/ OR COPYSMITH_MODEL_PATH set.
///   - Skips automatically if no model is found.
final class PromptSmokeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Each mode can take ~30s on slow hardware; 8 modes + model load = 5 min budget.
        executionTimeAllowance = 300
    }

    private let sampleText = """
        The quarterly report shows strong performance across all departments. \
        Revenue increased by 15% year-over-year, driven primarily by expansion \
        into new markets. However, operational costs also rose due to hiring and \
        infrastructure investments. The leadership team is optimistic about \
        continued growth in the next fiscal year.
        """

    func testAllModesProduceOutput() async throws {
        let modelURL = LlamaCppService.resolveModelURL()

        var st = stat()
        guard stat(modelURL.path, &st) == 0, st.st_size > 0 else {
            throw XCTSkip(
                "No GGUF model found — place a model in ~/.cache/huggingface/hub/ " +
                "or set COPYSMITH_MODEL_PATH"
            )
        }

        print("\n[Smoke] Using model: \(modelURL.lastPathComponent)")
        let service = LlamaCppService(modelURL: modelURL)
        var failures: [String] = []

        for mode in ChatMode.all {
            let prompt = mode.buildPrompt(for: sampleText)
            var output = ""
            let start = Date()

            do {
                for try await chunk in service.stream(prompt: prompt) {
                    output += chunk
                }
            } catch {
                failures.append("\(mode.id): threw \(error)")
                continue
            }

            let elapsed = Date().timeIntervalSince(start)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                failures.append("\(mode.id): empty output")
                print("[Smoke] FAIL \(mode.id): empty output (\(String(format: "%.1f", elapsed))s)")
            } else {
                print("[Smoke] PASS \(mode.id): \(trimmed.count) chars in \(String(format: "%.1f", elapsed))s")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "The following modes produced no output:\n" + failures.joined(separator: "\n")
        )
    }
}
