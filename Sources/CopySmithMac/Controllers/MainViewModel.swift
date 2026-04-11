import Foundation
import AppKit

// MARK: - Delegate

@MainActor
protocol MainViewModelDelegate: AnyObject {
    func modeDidUpdate(modeId: String, state: ModeResultState)
    func selectionDidChange(selectedModeIds: [String])
    func refineDidUpdate(text: String, isLoading: Bool)
}

// MARK: - ViewModel

@MainActor
final class MainViewModel {

    // MARK: Published state

    private(set) var clipboardText: String = ""
    private(set) var modeStates: [String: ModeResultState] = [:]
    private(set) var selectedModeIds: [String] = []   // ordered
    private(set) var refinedResult: String = ""

    // MARK: Dependencies

    private let clipboard: ClipboardServiceProtocol
    private let chatService: any LLMService
    private let scheduler = GenerationScheduler()

    // MARK: Task tracking

    private var modeTasks: [String: Task<Void, Never>] = [:]
    private var refineTask: Task<Void, Never>?

    /// Monotonically increasing; used for batch invalidation.
    private var currentBatchGeneration = 0
    /// Per-mode generation counter; incremented on individual refresh.
    private var modeGenerations: [String: Int] = [:]

    // MARK: Delegate

    weak var delegate: MainViewModelDelegate?

    // MARK: Init

    init(
        clipboard: ClipboardServiceProtocol = ClipboardService(),
        chatService: any LLMService = FoundationModelService()
    ) {
        self.clipboard = clipboard
        self.chatService = chatService

        for mode in ChatMode.all {
            modeStates[mode.id] = .initial
            modeGenerations[mode.id] = 0
        }
    }

    // MARK: Launch

    func onLaunch() {
        clipboardText = clipboard.readString() ?? ""

        if clipboardText.isEmpty {
            for mode in ChatMode.all {
                let state = ModeResultState(
                    text: "Clipboard is empty. Copy some text and restart the application.",
                    status: .done,
                    generation: 0
                )
                modeStates[mode.id] = state
                delegate?.modeDidUpdate(modeId: mode.id, state: state)
            }
        } else {
            startAllModes(generation: currentBatchGeneration)
        }
    }

    // MARK: Refresh all

    func refreshAll() {
        for task in modeTasks.values { task.cancel() }
        modeTasks = [:]
        refineTask?.cancel()

        currentBatchGeneration += 1
        let gen = currentBatchGeneration

        for mode in ChatMode.all {
            modeGenerations[mode.id] = gen
            let state = ModeResultState(text: "Queued...", status: .queued, generation: gen)
            modeStates[mode.id] = state
            delegate?.modeDidUpdate(modeId: mode.id, state: state)
        }

        if clipboardText.isEmpty {
            for mode in ChatMode.all {
                let state = ModeResultState(
                    text: "Main text from clipboard is empty.",
                    status: .done,
                    generation: gen
                )
                modeStates[mode.id] = state
                delegate?.modeDidUpdate(modeId: mode.id, state: state)
            }
            return
        }

        startAllModes(generation: gen)
    }

    // MARK: Refresh one

    func refreshMode(_ modeId: String) {
        guard let mode = ChatMode.all.first(where: { $0.id == modeId }) else { return }

        modeTasks[modeId]?.cancel()
        modeTasks[modeId] = nil

        currentBatchGeneration += 1
        let gen = currentBatchGeneration
        modeGenerations[modeId] = gen

        let queued = ModeResultState(text: "Queued...", status: .queued, generation: gen)
        modeStates[modeId] = queued
        delegate?.modeDidUpdate(modeId: modeId, state: queued)

        if clipboardText.isEmpty {
            let state = ModeResultState(
                text: "Main text from clipboard is empty.",
                status: .done,
                generation: gen
            )
            modeStates[modeId] = state
            delegate?.modeDidUpdate(modeId: modeId, state: state)
            return
        }

        startMode(mode, generation: gen)
    }

    // MARK: Combine / Refine

    func addModeToSelection(_ modeId: String) {
        guard !selectedModeIds.contains(modeId) else { return }
        selectedModeIds.append(modeId)
        delegate?.selectionDidChange(selectedModeIds: selectedModeIds)
    }

    func removeModeFromSelection(_ modeId: String) {
        selectedModeIds.removeAll { $0 == modeId }
        delegate?.selectionDidChange(selectedModeIds: selectedModeIds)
    }

    func clearSelection() {
        selectedModeIds = []
        refinedResult = ""
        delegate?.selectionDidChange(selectedModeIds: selectedModeIds)
        delegate?.refineDidUpdate(text: "", isLoading: false)
    }

    func refine() {
        guard !selectedModeIds.isEmpty else { return }

        let blocks: [(mode: ChatMode, text: String)] = selectedModeIds.compactMap { modeId in
            guard let mode = ChatMode.all.first(where: { $0.id == modeId }),
                  let state = modeStates[modeId] else { return nil }
            return (mode, state.text)
        }

        let prompt = ChatMode.buildRefinePrompt(blocks: blocks)

        refineTask?.cancel()
        refinedResult = "Loading..."
        delegate?.refineDidUpdate(text: "Loading...", isLoading: true)

        refineTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""

            do {
                for try await chunk in self.chatService.stream(prompt: prompt) {
                    try Task.checkCancellation()
                    accumulated += chunk
                    let snapshot = accumulated
                    self.refinedResult = snapshot
                    self.delegate?.refineDidUpdate(text: snapshot, isLoading: true)
                }
                self.refinedResult = accumulated
                self.delegate?.refineDidUpdate(text: accumulated, isLoading: false)
            } catch is CancellationError {
                // ignore
            } catch {
                let msg = errorMessage(from: error)
                self.refinedResult = msg
                self.delegate?.refineDidUpdate(text: msg, isLoading: false)
            }
        }
    }

    // MARK: Copy

    @discardableResult
    func copyToClipboard(_ text: String) -> Bool {
        clipboard.write(text)
    }

    // MARK: Lifecycle

    func cancelAll() {
        for task in modeTasks.values { task.cancel() }
        modeTasks = [:]
        refineTask?.cancel()
    }

    // MARK: Private helpers

    private func startAllModes(generation: Int) {
        for mode in ChatMode.all {
            startMode(mode, generation: generation)
        }
    }

    private func startMode(_ mode: ChatMode, generation: Int) {
        let task = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.scheduler.waitForSlot()
            } catch {
                return
            }

            defer {
                Task { await self.scheduler.release() }
            }

            guard !Task.isCancelled else { return }
            guard self.modeGenerations[mode.id] == generation else { return }

            let loading = ModeResultState(text: "Loading...", status: .running, generation: generation)
            self.modeStates[mode.id] = loading
            self.delegate?.modeDidUpdate(modeId: mode.id, state: loading)

            let prompt = mode.buildPrompt(for: self.clipboardText)
            var accumulated = ""

            do {
                for try await chunk in self.chatService.stream(prompt: prompt) {
                    try Task.checkCancellation()
                    guard self.modeGenerations[mode.id] == generation else { return }

                    accumulated += chunk
                    let snapshot = accumulated
                    let running = ModeResultState(text: snapshot, status: .running, generation: generation)
                    self.modeStates[mode.id] = running
                    self.delegate?.modeDidUpdate(modeId: mode.id, state: running)
                }

                guard self.modeGenerations[mode.id] == generation else { return }
                let done = ModeResultState(text: accumulated, status: .done, generation: generation)
                self.modeStates[mode.id] = done
                self.delegate?.modeDidUpdate(modeId: mode.id, state: done)

            } catch is CancellationError {
                // ignore
            } catch {
                guard self.modeGenerations[mode.id] == generation else { return }
                let msg = errorMessage(from: error)
                let errState = ModeResultState(text: msg, status: .error(msg), generation: generation)
                self.modeStates[mode.id] = errState
                self.delegate?.modeDidUpdate(modeId: mode.id, state: errState)
            }

            self.modeTasks[mode.id] = nil
        }

        modeTasks[mode.id] = task
    }
}

// MARK: - Helpers

private func errorMessage(from error: Error) -> String {
    switch error {
    case let e as ChatError:
        switch e {
        case .unavailable(let s): return s
        case .apiError(let s):    return "API error: \(s)"
        case .networkError(let s): return s
        case .cancelled:           return ""
        }
    default:
        return "Error: \(error.localizedDescription)"
    }
}
