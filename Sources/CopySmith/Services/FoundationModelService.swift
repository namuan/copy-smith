import Foundation
import FoundationModels

struct FoundationModelService: LLMService {
    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        .taskBacked { continuation in
            guard case .available = SystemLanguageModel.default.availability else {
                throw ChatError.unavailable(
                    "Apple Intelligence is not available. Please enable it in System Settings > Apple Intelligence & Siri."
                )
            }

            let session = LanguageModelSession()
            var previous = ""
            for try await snapshot in session.streamResponse(to: prompt) {
                // snapshot.content is cumulative — yield only the new suffix
                let full = snapshot.content
                let delta = String(full.dropFirst(previous.count))
                if !delta.isEmpty { continuation.yield(delta) }
                previous = full
            }
        }
    }
}
