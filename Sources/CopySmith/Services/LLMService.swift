import Foundation


protocol LLMService: Sendable {
    func stream(prompt: String) -> AsyncThrowingStream<String, Error>
}


enum ChatError: Error, Sendable {
    case unavailable(String)
    case apiError(String)
    case networkError(String)
    case cancelled
}


extension AsyncThrowingStream where Failure == Error {
    /// Runs `body` inside a Task, finishing the stream on completion and forwarding
    /// errors to the stream's consumer. Cancellation is wired automatically.
    static func taskBacked(
        _ body: @Sendable @escaping (Continuation) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        Self { continuation in
            let task = Task {
                do {
                    try await body(continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
