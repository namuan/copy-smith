import AppKit

// MARK: - Delegate

@MainActor
protocol CombinePanelViewDelegate: AnyObject {
    func combineDidRequestRemove(modeId: String)
    func combineDidRequestClearAll()
    func combineDidRequestRefine()
    func combineDidRequestCopy()
}

// MARK: - CombinePanelView

final class CombinePanelView: NSView {

    // MARK: Delegate

    weak var delegate: CombinePanelViewDelegate?

    // MARK: Private UI

    private let titleLabel       = NSTextField(labelWithString: "Combine & Refine")
    private let instructionLabel = NSTextField(
        labelWithString: "Click 'Add' buttons on panels to include responses for refinement."
    )
    private let selectedLabel    = NSTextField(labelWithString: "Selected Responses:")
    private let selectedStack    = NSStackView()
    private let selectedScroll   = NSScrollView()
    private let clearAllBtn      = NSButton(title: "Clear All", target: nil, action: nil)
    private let refineBtn        = NSButton(title: "Refine",    target: nil, action: nil)
    private let refinedLabel     = NSTextField(labelWithString: "Refined Result:")
    private let resultTextView   = NSTextView()
    private let resultScroll     = NSScrollView()
    private let copyBtn          = NSButton(title: "Copy",      target: nil, action: nil)

    // MARK: Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Styles.appBackground.cgColor
        layer?.borderColor     = Styles.textAreaBorder.cgColor
        layer?.borderWidth     = 1
        layer?.cornerRadius    = 4

        // Title
        titleLabel.font       = Styles.font(size: Styles.buttonFontSize + 2)
        titleLabel.textColor  = Styles.accentBlue
        titleLabel.isBordered = false
        titleLabel.isEditable = false

        // Instruction
        instructionLabel.font        = NSFont.systemFont(ofSize: 12)
        instructionLabel.textColor   = Styles.supportingText
        instructionLabel.isBordered  = false
        instructionLabel.isEditable  = false
        instructionLabel.lineBreakMode = .byWordWrapping
        instructionLabel.cell?.wraps = true

        // Selected Responses label
        selectedLabel.font      = Styles.font(size: Styles.buttonFontSize)
        selectedLabel.textColor = Styles.primaryText
        selectedLabel.isBordered = false
        selectedLabel.isEditable = false

        // Selected stack (vertical, inside a scroll view)
        selectedStack.orientation  = .vertical
        selectedStack.alignment    = .leading
        selectedStack.spacing      = 4
        selectedStack.distribution = .fill

        selectedScroll.documentView      = selectedStack
        selectedScroll.hasVerticalScroller = true
        selectedScroll.hasHorizontalScroller = false
        selectedScroll.autohidesScrollers  = true
        selectedScroll.borderType          = .lineBorder

        // Buttons row
        configureSmallButton(clearAllBtn, title: "Clear All")
        configureSmallButton(refineBtn,   title: "Refine")
        clearAllBtn.target = self; clearAllBtn.action = #selector(onClearAll)
        refineBtn.target   = self; refineBtn.action   = #selector(onRefine)

        let btnRow = NSStackView(views: [clearAllBtn, refineBtn])
        btnRow.orientation  = .horizontal
        btnRow.spacing      = Styles.combineSpacing
        btnRow.distribution = .fill

        // Refined result label
        refinedLabel.font      = Styles.font(size: Styles.buttonFontSize)
        refinedLabel.textColor = Styles.primaryText
        refinedLabel.isBordered = false
        refinedLabel.isEditable = false

        // Result text view
        resultTextView.isEditable              = false
        resultTextView.isSelectable            = true
        resultTextView.isHorizontallyResizable = false
        resultTextView.isVerticallyResizable   = true
        resultTextView.font                    = Styles.font(size: 14)
        resultTextView.textColor               = Styles.primaryText
        resultTextView.backgroundColor         = Styles.panelBackground
        resultTextView.textContainerInset      = NSSize(width: 4, height: 4)
        resultTextView.textContainer?.widthTracksTextView = true
        resultTextView.autoresizingMask = [.width]

        resultScroll.documentView          = resultTextView
        resultScroll.hasVerticalScroller   = true
        resultScroll.hasHorizontalScroller = false
        resultScroll.autohidesScrollers    = true
        resultScroll.borderType            = .lineBorder

        // Copy button
        configureSmallButton(copyBtn, title: "Copy")
        copyBtn.target = self; copyBtn.action = #selector(onCopy)

        // Root stack
        let root = NSStackView(views: [
            titleLabel,
            instructionLabel,
            selectedLabel,
            selectedScroll,
            btnRow,
            refinedLabel,
            resultScroll,
            copyBtn
        ])
        root.orientation  = .vertical
        root.alignment    = .leading
        root.spacing      = Styles.combineSpacing
        root.distribution = .fill
        root.edgeInsets   = NSEdgeInsets(
            top: Styles.combineInnerMargin, left: Styles.combineInnerMargin,
            bottom: Styles.combineInnerMargin, right: Styles.combineInnerMargin
        )

        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Width fills
            instructionLabel.widthAnchor.constraint(
                equalTo: root.widthAnchor, constant: -(Styles.combineInnerMargin * 2)),
            selectedScroll.widthAnchor.constraint(
                equalTo: root.widthAnchor, constant: -(Styles.combineInnerMargin * 2)),
            selectedScroll.heightAnchor.constraint(lessThanOrEqualToConstant: Styles.selectedScrollMaxH),
            btnRow.widthAnchor.constraint(
                equalTo: root.widthAnchor, constant: -(Styles.combineInnerMargin * 2)),
            resultScroll.widthAnchor.constraint(
                equalTo: root.widthAnchor, constant: -(Styles.combineInnerMargin * 2)),
        ])
    }

    private func configureSmallButton(_ btn: NSButton, title: String) {
        btn.title      = title
        btn.bezelStyle = .rounded
        btn.font       = Styles.font(size: Styles.buttonFontSize)
    }

    // MARK: State updates

    func updateSelectedModes(_ modeIds: [String]) {
        // Remove existing rows
        for sub in selectedStack.arrangedSubviews {
            selectedStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        for modeId in modeIds {
            guard let mode = ChatMode.all.first(where: { $0.id == modeId }) else { continue }
            let row = makeSelectedRow(mode: mode)
            selectedStack.addArrangedSubview(row)
        }

        refineBtn.isEnabled = !modeIds.isEmpty
        needsLayout = true
    }

    func updateRefinedResult(text: String, isLoading: Bool) {
        resultTextView.string = text
    }

    // MARK: Row builder

    private func makeSelectedRow(mode: ChatMode) -> NSView {
        let label = NSTextField(labelWithString: mode.title)
        label.font      = Styles.font(size: Styles.buttonFontSize)
        label.textColor = Styles.primaryText
        label.isBordered = false
        label.isEditable = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let removeBtn = NSButton(title: "X", target: nil, action: nil)
        removeBtn.bezelStyle = .rounded
        removeBtn.font = NSFont.systemFont(ofSize: 11)
        removeBtn.identifier = NSUserInterfaceItemIdentifier(rawValue: mode.id)
        removeBtn.target = self
        removeBtn.action = #selector(onRemove(_:))

        let row = NSStackView(views: [label, removeBtn])
        row.orientation  = .horizontal
        row.spacing      = 4
        row.alignment    = .centerY
        row.distribution = .fill
        return row
    }

    // MARK: Actions

    @objc private func onRemove(_ sender: NSButton) {
        delegate?.combineDidRequestRemove(modeId: sender.identifier!.rawValue)
    }

    @objc private func onClearAll() { delegate?.combineDidRequestClearAll() }
    @objc private func onRefine()   { delegate?.combineDidRequestRefine()   }
    @objc private func onCopy()     { delegate?.combineDidRequestCopy()     }
}
