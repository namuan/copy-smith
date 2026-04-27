import Foundation
import LocalLLMClient
import LocalLLMClientLlama

final class LlamaCppService: LLMService, @unchecked Sendable {
    private let runner: InferenceRunner

    init(modelURL: URL = LlamaCppService.resolveModelURL()) {
        runner = InferenceRunner(modelURL: modelURL)
        log.info("LlamaCpp", "service created — model: \(modelURL.lastPathComponent)")
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        .taskBacked { continuation in
            try await self.runner.infer(prompt: prompt) { continuation.yield($0) }
        }
    }

    // MARK: Model discovery

    static let selectedModelKey = "selectedModelPath"

    // knownModels lets callers pass an already-scanned list to avoid a second hub traversal.
    static func resolveModelURL(knownModels: [URL]? = nil) -> URL {
        if let saved = UserDefaults.standard.string(forKey: selectedModelKey) {
            let url = URL(fileURLWithPath: saved)
            var st = stat()
            if stat(url.path, &st) == 0, st.st_size > 0 {
                log.info("LlamaCpp", "model resolved from UserDefaults: \(url.lastPathComponent)")
                return url
            }
            log.warn("LlamaCpp", "saved model path no longer valid, falling back — path: \(saved)")
        }
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let preferred = "google_gemma-3-1b-it-qat-Q4_K_M.gguf"
        let allFound  = knownModels ?? allModels(in: hubDir)
        if let match = allFound.first(where: { $0.lastPathComponent == preferred }) {
            log.info("LlamaCpp", "model resolved to preferred default: \(preferred)")
            return match
        }
        if let found = findSmallestModel(from: allFound) {
            log.info("LlamaCpp", "preferred model not found, falling back to smallest: \(found.lastPathComponent)")
            return found
        }
        log.warn("LlamaCpp", "no model found in hub, using placeholder path")
        return hubDir.appendingPathComponent("model.gguf")
    }

    static func availableModels() -> [URL] {
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let models = allModels(in: hubDir).sorted { $0.lastPathComponent < $1.lastPathComponent }
        log.info("LlamaCpp", "discovered \(models.count) model(s) in hub: \(models.map(\.lastPathComponent).joined(separator: ", "))")
        return models
    }

    // stat() follows symlinks; lstat() (used by Foundation APIs) does not.
    // Broken symlinks return rc=-1 and are skipped automatically.
    private static func findSmallestModel(from models: [URL]) -> URL? {
        var best: (url: URL, size: Int)?
        for url in models {
            var st = stat()
            guard stat(url.path, &st) == 0, st.st_size > 0 else { continue }
            let size = Int(st.st_size)
            if best == nil || size < best!.size {
                best = (url, size)
            }
        }
        return best?.url
    }

    private static func allModels(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "gguf",
                  !url.lastPathComponent.hasPrefix("mmproj") else { continue }
            var st = stat()
            guard stat(url.path, &st) == 0, st.st_size > 0 else { continue }
            results.append(url)
        }
        return results
    }
}

// Serializes concurrent inference requests so LlamaClient (not thread-safe) is
// never driven by more than one task at a time. Uses task-chaining: each new
// request waits for the previous task to finish before starting its own inference.
private actor InferenceRunner {
    private var client: LlamaClient?
    private let modelURL: URL
    private var tailTask: Task<Void, Error>?

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func infer(prompt: String, onToken: @Sendable @escaping (String) -> Void) async throws {
        let previous = tailTask
        let task: Task<Void, Error> = Task { [weak self] in
            if case .failure(let error) = await previous?.result {
                log.debug("LlamaCpp", "previous inference task failed (skipping): \(error)")
            }
            guard !Task.isCancelled, let self else { return }
            try await self.runInference(prompt: prompt, onToken: onToken)
        }
        tailTask = task
        try await task.value
    }

    private func runInference(prompt: String, onToken: @Sendable @escaping (String) -> Void) async throws {
        log.debug("LlamaCpp", "stream start — prompt \(prompt.count) chars")
        let streamStart = Date()
        var tokenCount = 0

        let client = try loadedClient()
        let input = LLMInput.chat([.user(prompt)])
        // Use textStream (sync) rather than responseStream so cancellation is
        // fully cooperative — responseStream spawns an unstructured background
        // Task that keeps writing to Context.batch even after the consumer breaks,
        // racing with the next inference's reset.
        let generator = try client.textStream(from: input)
        for try await token in generator {
            if Task.isCancelled { break }
            tokenCount += 1
            onToken(token)
        }

        let elapsed = Date().timeIntervalSince(streamStart)
        log.debug("LlamaCpp", "stream end — \(tokenCount) tokens in \(String(format: "%.2f", elapsed))s")
    }

    private func loadedClient() throws -> LlamaClient {
        if let existing = client {
            log.debug("LlamaCpp", "reusing loaded model: \(modelURL.lastPathComponent)")
            return existing
        }
        log.info("LlamaCpp", "loading model: \(modelURL.path)")
        let loadStart = Date()
        do {
            let newClient = try LlamaClient(
                url: modelURL,
                mmprojURL: nil,
                parameter: .init(
                    context: 4096,
                    temperature: 0.7,
                    topK: 20,
                    topP: 0.8,
                    penaltyRepeat: 1.5
                ),
                messageProcessor: nil
            )
            client = newClient
            let elapsed = Date().timeIntervalSince(loadStart)
            log.info("LlamaCpp", "model loaded in \(String(format: "%.2f", elapsed))s: \(modelURL.lastPathComponent)")
            return newClient
        } catch {
            log.error("LlamaCpp", "failed to load model: \(modelURL.path) — \(error)")
            throw ChatError.unavailable(
                "Failed to load model at \(modelURL.path)\n" +
                "Place a model in ~/.cache/huggingface/hub/\n" +
                "Error: \(error.localizedDescription)"
            )
        }
    }
}
