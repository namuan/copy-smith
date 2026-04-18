import Foundation
import LLM

final class LlamaCppService: LLMService, @unchecked Sendable {
    private let modelURL: URL
    private var bot: LLM?
    private let lock = NSLock()

    init(modelURL: URL = LlamaCppService.resolveModelURL()) {
        self.modelURL = modelURL
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        .taskBacked { continuation in
            let bot = try self.loadedBot()
            bot.history = []
            await bot.respond(to: prompt) { stream in
                for await token in stream {
                    if Task.isCancelled { break }
                    continuation.yield(token)
                }
                return ""
            }
        }
    }

    // MARK: Private

    private func loadedBot() throws -> LLM {
        lock.lock()
        defer { lock.unlock() }
        if let existing = bot { return existing }
        let resolvedPath = modelURL.resolvingSymlinksInPath().path
        guard let newBot = LLM(from: resolvedPath, historyLimit: 0, maxTokenCount: 4096) else {
            throw ChatError.unavailable(
                "No model found at \(modelURL.path)\n" +
                "Set COPYSMITH_MODEL_PATH to a .gguf file path, or place a model in " +
                "~/.cache/huggingface/hub/"
            )
        }
        bot = newBot
        return newBot
    }

    // MARK: Model discovery

    private static func resolveModelURL() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["COPYSMITH_MODEL_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        let hubDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        if let found = findSmallestModel(in: hubDir) { return found }
        return hubDir.appendingPathComponent("model.gguf")
    }

    private static func findSmallestModel(in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(url: URL, size: Int)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "gguf",
                  !url.lastPathComponent.hasPrefix("mmproj") else { continue }
            let resolved = url.resolvingSymlinksInPath()
            guard let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size > 0 else { continue }
            candidates.append((url, size))
        }
        return candidates.min(by: { $0.size < $1.size })?.url
    }
}
