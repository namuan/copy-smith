import AppKit

@MainActor
final class MainViewController: NSViewController {

    // MARK: ViewModel

    let viewModel: MainViewModel

    // MARK: UI

    // Top bar
    private let modelLabel   = NSTextField(labelWithString: "Model:")
    private let modelPopup   = NSPopUpButton()
    private let modelRefresh = NSButton(title: "↻",         target: nil, action: nil)
    private let refreshAllBtn = NSButton(title: "Refresh All", target: nil, action: nil)
    private let closeBtn     = NSButton(title: "Close",     target: nil, action: nil)

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
        // Model label
        modelLabel.font      = Styles.font(size: Styles.buttonFontSize)
        modelLabel.textColor = Styles.primaryText
        modelLabel.isBordered = false
        modelLabel.isEditable = false

        // Model popup — starts with "Loading..."
        modelPopup.addItem(withTitle: "Loading...")
        modelPopup.isEnabled = false
        modelPopup.font      = Styles.font(size: Styles.buttonFontSize)
        modelPopup.target    = self
        modelPopup.action    = #selector(modelSelected)
        modelPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        // Model refresh button
        configureToolbarButton(modelRefresh, title: "↻", width: 28)
        modelRefresh.toolTip = "Refresh model list"
        modelRefresh.target  = self
        modelRefresh.action  = #selector(refreshModels)

        // Refresh All
        configureToolbarButton(refreshAllBtn, title: "Refresh All")
        refreshAllBtn.target = self
        refreshAllBtn.action = #selector(refreshAll)

        // Close
        configureToolbarButton(closeBtn, title: "Close")
        closeBtn.target = self
        closeBtn.action = #selector(closeApp)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [
            spacer, modelLabel, modelPopup, modelRefresh, refreshAllBtn, closeBtn
        ])
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

        // Tag the bar so setupContent can anchor below it
        bar.identifier = NSUserInterfaceItemIdentifier("topBar")
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
        // Build panel stack inside scroll view
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

        // Make panels fill the scroll view width
        for panel in resultPanels.values {
            panel.translatesAutoresizingMaskIntoConstraints = false
        }

        panelScrollView.documentView        = panelStack
        panelScrollView.hasVerticalScroller = true
        panelScrollView.hasHorizontalScroller = false
        panelScrollView.autohidesScrollers  = true
        panelScrollView.drawsBackground     = false

        // Combine panel fixed width
        combinePanel.delegate = self
        combinePanel.translatesAutoresizingMaskIntoConstraints = false

        // Horizontal split
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

        // Panel stack width = scroll view content width
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        let clip = panelScrollView.contentView
        panelStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor).isActive = true
        panelStack.topAnchor.constraint(equalTo: clip.topAnchor).isActive = true
        panelStack.widthAnchor.constraint(equalTo: clip.widthAnchor).isActive = true

        // Each panel fills the stack width
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
        super.keyDown(with: event)
    }

    // MARK: Actions

    @objc private func modelSelected() {
        let title = modelPopup.selectedItem?.title ?? ""
        viewModel.selectModel(title)
    }

    @objc private func refreshModels() {
        viewModel.loadModels()
    }

    @objc private func refreshAll() {
        viewModel.refreshAll()
    }

    @objc private func closeApp() {
        viewModel.cancelAll()
        NSApp.terminate(nil)
    }
}

// MARK: - MainViewModelDelegate

extension MainViewController: MainViewModelDelegate {

    func modelsLoadingStarted() {
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: "Loading...")
        modelPopup.isEnabled = false
    }

    func modelsDidLoad(_ models: [String], selectedModel: String) {
        modelPopup.removeAllItems()
        for m in models { modelPopup.addItem(withTitle: m) }
        modelPopup.isEnabled = true
        if let idx = models.firstIndex(of: selectedModel) {
            modelPopup.selectItem(at: idx)
        }
    }

    func modelsDidFailToLoad() {
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: "Failed to load")
        modelPopup.isEnabled = false
    }

    func modeDidUpdate(modeId: String, state: ModeResultState) {
        resultPanels[modeId]?.apply(state)
    }

    func selectionDidChange(selectedModeIds: [String]) {
        combinePanel.updateSelectedModes(selectedModeIds)
    }

    func refineDidUpdate(text: String, isLoading: Bool) {
        combinePanel.updateRefinedResult(text: text, isLoading: isLoading)
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
