import Foundation

/// Limits concurrent mode generation requests to `maxConcurrent`.
/// Uses polling so that Task cancellation naturally propagates.
actor GenerationScheduler {
    let maxConcurrent: Int

    private var running = 0

    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }

    /// Suspends until a slot is available, then acquires it.
    /// Throws `CancellationError` if the calling task is cancelled while waiting.
    func waitForSlot() async throws {
        while running >= maxConcurrent {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000) // 50 ms polling
        }
        running += 1
    }

    func release() {
        running = max(0, running - 1)
    }
}
