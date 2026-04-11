import Foundation

enum ModeStatus: Sendable {
    case queued
    case running
    case done
    case error(String)
}

struct ModeResultState: Sendable {
    var text: String
    var status: ModeStatus
    var generation: Int

    static let initial = ModeResultState(text: "", status: .queued, generation: 0)

    var isLoading: Bool {
        if case .running = status { return true }
        return false
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    /// True when text is actionable (not a placeholder or loading).
    var isAddable: Bool {
        !text.isEmpty && text != "Queued..." && text != "Loading..."
    }
}
