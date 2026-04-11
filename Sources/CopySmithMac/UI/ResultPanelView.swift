import AppKit

// MARK: - Delegate

@MainActor
protocol ResultPanelViewDelegate: AnyObject {
    func panelDidRequestRefresh(_ panel: ResultPanelView)
    func panelDidRequestCopy(_ panel: ResultPanelView)
    func panelDidRequestAdd(_ panel: ResultPanelView)
}

// MARK: - Click-forwarding text view

/// Forwards mouseDown events to the enclosing ResultPanelView so that
/// clicking anywhere on the panel (including the text area) toggles expansion.
private class PanelTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        // Walk superview chain to find the panel and forward the click
        var view: NSView? = self
        while let v = view {
            if let panel = v as? ResultPanelView {
                panel.mouseDown(with: event)
                return
            }
            view = v.superview
        }
        super.mouseDown(with: event)
    }
}

// MARK: - ResultPanelView

final class ResultPanelView: NSView {

    // MARK: Public state

    let mode: ChatMode
    weak var delegate: ResultPanelViewDelegate?
    private(set) var isExpanded = false

    // MARK: UI elements

    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel  = NSTextField(labelWithString: "🖱️ Click to expand • ESC to collapse")
    private let refreshBtn = NSButton(title: "Refresh",  target: nil, action: nil)
    private let copyBtn    = NSButton(title: "Copy",     target: nil, action: nil)
    private let addBtn     = NSButton(title: "Add >>",   target: nil, action: nil)
    private let textView   = PanelTextView()
    private let scrollView = NSScrollView()
    private let progress   = NSProgressIndicator()

    private var textHeightConstraint: NSLayoutConstraint!

    // MARK: Init

    init(mode: ChatMode) {
        self.mode = mode
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Styles.panelBackground.cgColor
        layer?.borderColor     = Styles.textAreaBorder.cgColor
        layer?.borderWidth     = 1
        layer?.cornerRadius    = Styles.panelCornerRadius

        // Title
        titleLabel.stringValue = mode.title
        titleLabel.font        = Styles.font(size: Styles.buttonFontSize)
        titleLabel.textColor   = Styles.primaryText
        titleLabel.isBordered  = false
        titleLabel.isEditable  = false

        // Hint
        hintLabel.font      = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = Styles.hintText

        // Buttons
        configureButton(refreshBtn, title: "Refresh",  width: Styles.refreshButtonWidth)
        configureButton(copyBtn,    title: "Copy",     width: Styles.copyButtonWidth)
        configureButton(addBtn,     title: "Add >>",   width: Styles.addButtonWidth)

        refreshBtn.target = self; refreshBtn.action = #selector(onRefresh)
        copyBtn.target    = self; copyBtn.action    = #selector(onCopy)
        addBtn.target     = self; addBtn.action     = #selector(onAdd)

        // Header stack
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [titleLabel, hintLabel, spacer, refreshBtn, copyBtn, addBtn])
        header.orientation  = .horizontal
        header.spacing      = CGFloat(Styles.panelInternalSpacing)
        header.alignment    = .centerY
        header.distribution = .fill

        // Text view
        textView.isEditable             = false
        textView.isSelectable           = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable   = true
        textView.font                    = Styles.font(size: Styles.mainFontSize)
        textView.textColor               = Styles.primaryText
        textView.backgroundColor         = Styles.panelBackground
        textView.textContainerInset      = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        // Scroll view
        scrollView.documentView        = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .lineBorder
        scrollView.wantsLayer          = true
        scrollView.layer?.borderColor  = Styles.textAreaBorder.cgColor
        scrollView.layer?.borderWidth  = 1
        scrollView.layer?.cornerRadius = 3

        // Progress indicator
        progress.style           = .bar
        progress.isIndeterminate = true
        progress.controlSize     = .small
        progress.isHidden        = true

        // Layout
        let stack = NSStackView(views: [header, scrollView, progress])
        stack.orientation = .vertical
        stack.spacing     = CGFloat(Styles.panelInternalSpacing)
        stack.alignment   = .leading
        stack.distribution = .fill
        stack.edgeInsets  = NSEdgeInsets(
            top: Styles.panelInnerMargin, left: Styles.panelInnerMargin,
            bottom: Styles.panelInnerMargin, right: Styles.panelInnerMargin
        )

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        textHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: Styles.panelCollapsedHeight)
        textHeightConstraint.isActive = true

        // header and progress fill width
        header.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                          constant: -(Styles.panelInnerMargin * 2)),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                              constant: -(Styles.panelInnerMargin * 2)),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                            constant: -(Styles.panelInnerMargin * 2)),
            progress.heightAnchor.constraint(equalToConstant: Styles.progressHeight),
        ])
    }

    private func configureButton(_ btn: NSButton, title: String, width: CGFloat) {
        btn.title       = title
        btn.bezelStyle  = .rounded
        btn.font        = Styles.font(size: Styles.buttonFontSize)
        btn.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    // MARK: State update

    func apply(_ state: ModeResultState) {
        let text = state.text
        textView.string = text

        let loading = state.isLoading
        let isError  = state.isError

        copyBtn.isEnabled = !loading
        addBtn.isEnabled  = state.isAddable && !loading

        if isError {
            titleLabel.textColor = Styles.errorText
        } else {
            titleLabel.textColor = Styles.primaryText
        }

        if loading {
            progress.isHidden = false
            progress.startAnimation(nil)
        } else {
            progress.stopAnimation(nil)
            progress.isHidden = true
        }
    }

    // MARK: Expand / Collapse

    override func mouseDown(with event: NSEvent) {
        toggleExpand()
    }

    func toggleExpand() {
        isExpanded.toggle()
        let h = isExpanded ? Styles.panelExpandedHeight : Styles.panelCollapsedHeight
        textHeightConstraint.constant = h
        needsLayout = true
        window?.layoutIfNeeded()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        textHeightConstraint.constant = Styles.panelCollapsedHeight
        needsLayout = true
        window?.layoutIfNeeded()
    }

    // MARK: Actions

    @objc private func onRefresh() { delegate?.panelDidRequestRefresh(self) }
    @objc private func onCopy()    { delegate?.panelDidRequestCopy(self)    }
    @objc private func onAdd()     { delegate?.panelDidRequestAdd(self)     }
}

// MARK: - NSWindow layout helper

private extension NSWindow {
    func layoutIfNeeded() {
        contentView?.layoutSubtreeIfNeeded()
    }
}
