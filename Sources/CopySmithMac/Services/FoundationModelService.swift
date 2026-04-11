import Foundation
import FoundationModels

struct FoundationModelService: LLMService {
    func stream(model: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let languageModel = SystemLanguageModel.default
                    guard case .available = languageModel.availability else {
                        continuation.finish(
                            throwing: ChatError.apiError(
                                "Apple Intelligence is not available. Please enable it in System Settings > Apple Intelligence & Siri."
                            )
                        )
                        return
                    }

                    let session = LanguageModelSession()
                    for try await snapshot in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as ChatError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: ChatError.networkError(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
