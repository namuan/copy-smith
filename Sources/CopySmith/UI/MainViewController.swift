import AppKit

@MainActor
final class MainViewController: NSViewController {

    // MARK: ViewModel

    let viewModel: MainViewModel

    // MARK: UI

    // Top bar
    private let modelPicker   = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshAllBtn = NSButton(title: "Refresh All", target: nil, action: nil)
    private let closeBtn      = NSButton(title: "Close",       target: nil, action: nil)

    // Content
    private let panelScrollView = NSScrollView()
    private let panelStack      = NSStackView()
    private let combinePanel    = CombinePanelView()

    // Per-mode panels keyed by mode id
    private var resultPanels: [String: ResultPanelView] = [:]

    // MARK: Init

    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        viewModel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func loadView() {
        let root = RootContentView()
        root.frame = NSRect(x: 0, y: 0, width: Styles.windowWidth, height: Styles.windowHeight)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTopBar()
        setupContent()
        viewModel.onLaunch()
    }

    // MARK: Top bar

    private func setupTopBar() {
        setupModelPicker()

        configureToolbarButton(refreshAllBtn, title: "Refresh All")
        refreshAllBtn.target = self
        refreshAllBtn.action = #selector(refreshAll)

        configureToolbarButton(closeBtn, title: "Close")
        closeBtn.target = self
        closeBtn.action = #selector(closeApp)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [spacer, modelPicker, refreshAllBtn, closeBtn])
        bar.orientation  = .horizontal
        bar.spacing      = Styles.mainSpacing
        bar.alignment    = .centerY
        bar.distribution = .fill

        view.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: Styles.rootMargin),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Styles.rootMargin),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Styles.rootMargin),
        ])

        bar.identifier = NSUserInterfaceItemIdentifier("topBar")
    }

    private func setupModelPicker() {
        let models = viewModel.availableModels
        modelPicker.removeAllItems()

        if models.isEmpty {
            modelPicker.addItem(withTitle: "No models found")
            modelPicker.isEnabled = false
        } else {
            for url in models {
                modelPicker.addItem(withTitle: url.lastPathComponent)
                modelPicker.lastItem?.representedObject = url
            }
            modelPicker.selectItem(at: indexOfModel(viewModel.selectedModelURL) ?? 0)
            modelPicker.isEnabled = true
        }

        modelPicker.font = Styles.font(size: Styles.buttonFontSize)
        modelPicker.target = self
        modelPicker.action = #selector(modelPickerDidChange)
        modelPicker.translatesAutoresizingMaskIntoConstraints = false
    }

    private func indexOfModel(_ url: URL) -> Int? {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent
        return viewModel.availableModels.firstIndex(where: { $0.standardizedFileURL.path == path })
            ?? viewModel.availableModels.firstIndex(where: { $0.lastPathComponent == name })
    }

    private func configureToolbarButton(_ btn: NSButton, title: String, width: CGFloat? = nil) {
        btn.title      = title
        btn.bezelStyle = .rounded
        btn.font       = Styles.font(size: Styles.buttonFontSize)
        if let w = width {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
    }

    // MARK: Content area

    private func setupContent() {
        panelStack.orientation  = .vertical
        panelStack.alignment    = .leading
        panelStack.spacing      = Styles.mainSpacing
        panelStack.distribution = .fill

        for mode in ChatMode.all {
            let panel = ResultPanelView(mode: mode)
            panel.delegate = self
            resultPanels[mode.id] = panel
            panelStack.addArrangedSubview(panel)
        }

        for panel in resultPanels.values {
            panel.translatesAutoresizingMaskIntoConstraints = false
        }

        panelScrollView.documentView          = panelStack
        panelScrollView.hasVerticalScroller   = true
        panelScrollView.hasHorizontalScroller = false
        panelScrollView.autohidesScrollers    = true
        panelScrollView.drawsBackground       = false

        combinePanel.delegate = self
        combinePanel.translatesAutoresizingMaskIntoConstraints = false

        let topBar = view.subviews.first(where: {
            $0.identifier?.rawValue == "topBar"
        })!

        view.addSubview(panelScrollView)
        view.addSubview(combinePanel)

        panelScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            panelScrollView.topAnchor.constraint(
                equalTo: topBar.bottomAnchor, constant: Styles.mainSpacing),
            panelScrollView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Styles.rootMargin),
            panelScrollView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor, constant: -Styles.rootMargin),

            combinePanel.topAnchor.constraint(
                equalTo: topBar.bottomAnchor, constant: Styles.mainSpacing),
            combinePanel.leadingAnchor.constraint(
                equalTo: panelScrollView.trailingAnchor, constant: Styles.mainSpacing),
            combinePanel.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Styles.rootMargin),
            combinePanel.bottomAnchor.constraint(
                equalTo: view.bottomAnchor, constant: -Styles.rootMargin),
            combinePanel.widthAnchor.constraint(equalToConstant: Styles.combineWidth),
        ])

        panelStack.translatesAutoresizingMaskIntoConstraints = false
        let clip = panelScrollView.contentView
        panelStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor).isActive = true
        panelStack.topAnchor.constraint(equalTo: clip.topAnchor).isActive = true
        panelStack.widthAnchor.constraint(equalTo: clip.widthAnchor).isActive = true

        for panel in resultPanels.values {
            panel.widthAnchor.constraint(equalTo: panelStack.widthAnchor).isActive = true
        }

        combinePanel.updateSelectedModes([])
    }

    // MARK: Key events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            for panel in resultPanels.values {
                panel.collapse()
            }
            return
        }
        // Cmd+Q — quit (no menu bar, so handle it here)
        if event.keyCode == 12,
           event.modifierFlags.contains(.command) {
            viewModel.cancelAll()
            NSApp.terminate(nil)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Actions

    @objc private func modelPickerDidChange() {
        guard let url = modelPicker.selectedItem?.representedObject as? URL else { return }
        log.info("UI", "model picker changed → \(url.lastPathComponent)")
        viewModel.selectModel(url: url)
    }

    @objc private func refreshAll() {
        log.info("UI", "refresh all tapped")
        viewModel.refreshAll()
    }

    @objc private func closeApp() {
        log.info("UI", "close tapped")
        viewModel.cancelAll()
        NSApp.terminate(nil)
    }
}

// MARK: - MainViewModelDelegate

extension MainViewController: MainViewModelDelegate {

    func modeDidUpdate(modeId: String, state: ModeResultState) {
        resultPanels[modeId]?.apply(state)
    }

    func selectionDidChange(selectedModeIds: [String]) {
        combinePanel.updateSelectedModes(selectedModeIds)
    }

    func refineDidUpdate(text: String, isLoading: Bool) {
        combinePanel.updateRefinedResult(text: text, isLoading: isLoading)
    }

    func modelSelectionDidFail() {
        log.warn("UI", "model selection failed, reverting picker to \(viewModel.selectedModelURL.lastPathComponent)")
        if let idx = indexOfModel(viewModel.selectedModelURL) {
            modelPicker.selectItem(at: idx)
        }
    }
}

// MARK: - ResultPanelViewDelegate

extension MainViewController: ResultPanelViewDelegate {

    func panelDidRequestRefresh(_ panel: ResultPanelView) {
        viewModel.refreshMode(panel.mode.id)
    }

    func panelDidRequestCopy(_ panel: ResultPanelView) {
        let text = viewModel.modeStates[panel.mode.id]?.text ?? ""
        viewModel.copyToClipboard(text)
        NSApp.terminate(nil)
    }

    func panelDidRequestAdd(_ panel: ResultPanelView) {
        viewModel.addModeToSelection(panel.mode.id)
    }
}

// MARK: - CombinePanelViewDelegate

extension MainViewController: CombinePanelViewDelegate {

    func combineDidRequestRemove(modeId: String) {
        viewModel.removeModeFromSelection(modeId)
    }

    func combineDidRequestClearAll() {
        viewModel.clearSelection()
    }

    func combineDidRequestRefine() {
        viewModel.refine()
    }

    func combineDidRequestCopy() {
        let text = viewModel.refinedResult
        guard !text.isEmpty, text != "Loading..." else { return }
        viewModel.copyToClipboard(text)
        NSApp.terminate(nil)
    }
}

// MARK: - Root content view (draws border + background)

private final class RootContentView: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds,
                              xRadius: Styles.outerCornerRadius,
                              yRadius: Styles.outerCornerRadius)
        Styles.appBackground.setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                  xRadius: Styles.outerCornerRadius,
                                  yRadius: Styles.outerCornerRadius)
        border.lineWidth = Styles.outerBorderWidth
        Styles.outerBorder.setStroke()
        border.stroke()
    }
}
