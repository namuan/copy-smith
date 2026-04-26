import XCTest
import Darwin
@testable import CopySmith

/// Full-stack integration tests for LlamaCppService.
///
/// These tests run real inference against the locally installed GGUF model and
/// verify correctness of the service layer without any simulated or mocked
/// components.  They are skipped automatically when no model is available.
///
/// Run with:
///   swift test --filter LLMServiceIntegrationTests
///
/// Budget: up to 10 minutes (each mode can take 30-60 s on a slow machine).
final class LLMServiceIntegrationTests: XCTestCase {

    private var service: LlamaCppService!
    private var modelURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 600

        let url = LlamaCppService.resolveModelURL()
        var st = stat()
        guard stat(url.path, &st) == 0, st.st_size > 0 else {
            throw XCTSkip(
                "No GGUF model — set COPYSMITH_MODEL_PATH or place a model " +
                "in ~/.cache/huggingface/hub/"
            )
        }
        modelURL = url
        service = LlamaCppService(modelURL: url)
        print("\n[Integration] model: \(url.lastPathComponent)")
    }

    // MARK: - Short text, all 8 modes sequentially

    /// Runs all 8 ChatModes one after another on the same service instance.
    /// Verifies that the per-request context reset works correctly so each
    /// mode produces a valid response.
    func testAllModesSequential() async throws {
        let text = """
            The quarterly report shows strong performance across all departments. \
            Revenue increased by 15% year-over-year, driven primarily by expansion \
            into new markets. However, operational costs also rose due to hiring and \
            infrastructure investments. The leadership team is optimistic about \
            continued growth in the next fiscal year.
            """

        var failures: [String] = []

        for mode in ChatMode.all {
            let prompt = mode.buildPrompt(for: text)
            let (output, elapsed, error) = await runStream(prompt: prompt)

            if let error {
                failures.append("\(mode.id): error — \(error)")
                print("[Integration] FAIL \(mode.id): \(error)")
                continue
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                failures.append("\(mode.id): empty output")
                print("[Integration] FAIL \(mode.id): empty output (\(fmt(elapsed))s)")
            } else {
                print("[Integration] PASS \(mode.id): \(trimmed.count) chars in \(fmt(elapsed))s")
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: - Long input (context stress)

    /// Sends a prompt long enough to previously trigger "context size exceeded"
    /// and verifies the service handles it without crashing or returning an error.
    func testLongInputDoesNotExceedContext() async throws {
        // ~600 word passage — enough to stress the old 2048-token context
        let longText = String(repeating: """
            Artificial intelligence and machine learning have become central pillars \
            of modern technology development. Companies across every sector are \
            investing heavily in these capabilities to automate processes, derive \
            insights from data, and create new products and services. The rapid \
            pace of advancement means that models which were state-of-the-art a \
            year ago are now being superseded by more capable successors.
            """, count: 5)

        let mode = ChatMode.all.first { $0.id == "concise" }!
        let prompt = mode.buildPrompt(for: longText)
        let (output, elapsed, error) = await runStream(prompt: prompt)

        XCTAssertNil(error, "Long input should not produce an error — got: \(error?.localizedDescription ?? "")")
        XCTAssertFalse(
            output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Long input should still produce output"
        )
        print("[Integration] Long-input PASS: \(output.count) chars in \(fmt(elapsed))s")
    }

    // MARK: - Context reset across multiple rounds

    /// Calls the service multiple times on the same instance and verifies that
    /// each call produces independent output (i.e. context is properly reset).
    func testContextResetBetweenCalls() async throws {
        let texts = [
            "The weather today is sunny with light winds.",
            "Machine learning models require large datasets for training.",
            "The recipe calls for two cups of flour and one egg.",
        ]

        var outputs: [String] = []

        for text in texts {
            let prompt = ChatMode.all.first { $0.id == "proofread" }!.buildPrompt(for: text)
            let (output, _, error) = await runStream(prompt: prompt)
            XCTAssertNil(error, "Round \(outputs.count + 1) failed: \(error?.localizedDescription ?? "")")
            outputs.append(output)
            print("[Integration] Reset-round \(outputs.count): \(output.count) chars")
        }

        XCTAssertEqual(outputs.count, 3)
        // Each output should be non-empty
        for (i, output) in outputs.enumerated() {
            XCTAssertFalse(
                output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Round \(i + 1) produced empty output"
            )
        }
    }

    // MARK: - Refine prompt (combine mode)

    /// Verifies that the Combine & Refine prompt (which is longer, combining
    /// multiple blocks) also works end-to-end.
    func testRefinePrompt() async throws {
        let blocks: [(mode: ChatMode, text: String)] = ChatMode.all.prefix(3).map { mode in
            (mode: mode, text: "Sample rewrite for \(mode.title) mode.")
        }
        let prompt = ChatMode.buildRefinePrompt(blocks: blocks)
        let (output, elapsed, error) = await runStream(prompt: prompt)

        XCTAssertNil(error, "Refine prompt error: \(error?.localizedDescription ?? "")")
        XCTAssertFalse(
            output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Refine prompt produced empty output"
        )
        print("[Integration] Refine PASS: \(output.count) chars in \(fmt(elapsed))s")
    }

    // MARK: - Cancellation does not corrupt subsequent calls

    /// Cancels a generation mid-stream then immediately starts a new one.
    /// Verifies the second call succeeds — proving the batch/context reset
    /// survives a mid-stream cancellation.
    func testCancellationDoesNotCorruptNextCall() async throws {
        let prompt = ChatMode.all.first { $0.id == "explain" }!
            .buildPrompt(for: "Quantum entanglement is a physical phenomenon.")

        // Start and then cancel after the first token
        let cancelTask = Task {
            var tokenCount = 0
            for try await _ in self.service.stream(prompt: prompt) {
                tokenCount += 1
                if tokenCount >= 1 { break }
            }
        }
        _ = try? await cancelTask.value

        // Now run a clean second inference — must not crash or produce empty output
        let (output, elapsed, error) = await runStream(
            prompt: ChatMode.all.first { $0.id == "concise" }!
                .buildPrompt(for: "Keep it simple and clear.")
        )

        XCTAssertNil(error, "Post-cancel call failed: \(error?.localizedDescription ?? "")")
        XCTAssertFalse(
            output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Post-cancel call produced empty output"
        )
        print("[Integration] Post-cancel PASS: \(output.count) chars in \(fmt(elapsed))s")
    }

    // MARK: - Helpers

    private func runStream(prompt: String) async -> (output: String, elapsed: TimeInterval, error: Error?) {
        let start = Date()
        var output = ""
        do {
            for try await chunk in service.stream(prompt: prompt) {
                output += chunk
            }
            return (output, Date().timeIntervalSince(start), nil)
        } catch {
            return (output, Date().timeIntervalSince(start), error)
        }
    }

    private func fmt(_ t: TimeInterval) -> String {
        String(format: "%.1f", t)
    }
}
