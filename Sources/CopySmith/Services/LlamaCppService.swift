import Foundation
import LLM

final class LlamaCppService: LLMService, @unchecked Sendable {
    private let modelURL: URL
    private var bot: LLM?
    private let lock = NSLock()

    init(modelURL: URL = LlamaCppService.resolveModelURL()) {
        self.modelURL = modelURL
        log.info("LlamaCpp", "service created — model: \(modelURL.lastPathComponent)")
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        .taskBacked { continuation in
            log.debug("LlamaCpp", "stream start — prompt \(prompt.count) chars")
            let streamStart = Date()
            var tokenCount = 0
            let bot = try self.loadedBot()
            bot.history = []
            await bot.core.resetContext()
            await bot.respond(to: prompt) { stream in
                for await token in stream {
                    if Task.isCancelled { break }
                    tokenCount += 1
                    continuation.yield(token)
                }
                return ""
            }
            let elapsed = Date().timeIntervalSince(streamStart)
            log.debug("LlamaCpp", "stream end — \(tokenCount) tokens in \(String(format: "%.2f", elapsed))s")
        }
    }

    // MARK: Private

    private func loadedBot() throws -> LLM {
        lock.lock()
        defer { lock.unlock() }
        if let existing = bot {
            log.debug("LlamaCpp", "reusing loaded model: \(modelURL.lastPathComponent)")
            return existing
        }
        log.info("LlamaCpp", "loading model: \(modelURL.path)")
        let loadStart = Date()
        guard let newBot = LLM(
            from: modelURL.path,
            topK: 20,
            topP: 0.8,
            temp: 0.7,
            repeatPenalty: 1.5,
            historyLimit: 0,
            maxTokenCount: 1024
        ) else {
            log.error("LlamaCpp", "failed to load model: \(modelURL.path)")
            throw ChatError.unavailable(
                "Failed to load model at \(modelURL.path)\n" +
                "Set COPYSMITH_MODEL_PATH to a .gguf file path, or place a model in " +
                "~/.cache/huggingface/hub/"
            )
        }
        let elapsed = Date().timeIntervalSince(loadStart)
        log.info("LlamaCpp", "model loaded in \(String(format: "%.2f", elapsed))s: \(modelURL.lastPathComponent)")
        bot = newBot
        return newBot
    }

    // MARK: Model discovery

    static let selectedModelKey = "selectedModelPath"

    // knownModels lets callers pass an already-scanned list to avoid a second hub traversal.
    static func resolveModelURL(knownModels: [URL]? = nil) -> URL {
        if let envPath = ProcessInfo.processInfo.environment["COPYSMITH_MODEL_PATH"] {
            log.info("LlamaCpp", "model resolved from COPYSMITH_MODEL_PATH: \(envPath)")
            return URL(fileURLWithPath: envPath)
        }
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
