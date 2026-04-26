import Foundation

/// Limits concurrent generation requests to `maxConcurrent`, releasing slots in
/// strict FIFO order so modes run in the order they were enqueued.
actor GenerationScheduler {
    let maxConcurrent: Int

    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(maxConcurrent: Int = 1) {
        self.maxConcurrent = maxConcurrent
    }

    /// Acquires a slot immediately if one is free, otherwise suspends in FIFO order.
    /// Throws `CancellationError` if the calling task is cancelled while waiting.
    func waitForSlot() async throws {
        try Task.checkCancellation()
        if running < maxConcurrent {
            running += 1
            log.debug("Scheduler", "slot acquired immediately (running: \(running)/\(maxConcurrent))")
            return
        }
        let id = UUID()
        log.debug("Scheduler", "queued (running: \(running)/\(maxConcurrent), waiting: \(waiters.count + 1))")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        if let first = waiters.first {
            waiters.removeFirst()
            // Hand the slot directly to the next waiter; running count stays the same.
            log.debug("Scheduler", "slot passed to next waiter (running: \(running)/\(maxConcurrent), remaining: \(waiters.count))")
            first.continuation.resume()
        } else {
            running = max(0, running - 1)
            log.debug("Scheduler", "slot released (running: \(running)/\(maxConcurrent))")
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
