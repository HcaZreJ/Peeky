import AppKit
import Foundation

private struct PreviewTab {
    let id: UUID
    let url: URL
    var document: LoadedText?
    var errorMessage: String?
    var mode: PreviewMode
    var collapseNestedJSON: Bool
    var targetLine: Int?
    var targetColumn: Int?

    init(url: URL, document: LoadedText?, errorMessage: String?) {
        self.id = UUID()
        self.url = url
        self.document = document
        self.errorMessage = errorMessage
        self.mode = .formatted
        self.collapseNestedJSON = false
        self.targetLine = nil
        self.targetColumn = nil
    }
}

private final class FileTabView: NSControl {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var isSelectedTab = false {
        didSet {
            updateAppearance()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let closeButton = NSButton()
    private let isError: Bool
    private var isHovering = false {
        didSet {
            updateAppearance()
        }
    }

    init(url: URL, subtitle: String, isError: Bool, isSelected: Bool) {
        self.isError = isError
        self.isSelectedTab = isSelected
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 18, height: 18)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = url.lastPathComponent
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.toolTip = url.path

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 10)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.toolTip = "Close Tab"
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let rowStack = NSStackView(views: [iconView, textStack, closeButton])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        if isSelectedTab {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        } else if isHovering {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: isSelectedTab ? .semibold : .regular)
        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.alphaValue = isSelectedTab || isHovering ? 1 : 0.55
    }

    @objc private func closeClicked(_ sender: Any?) {
        onClose?()
    }
}

private final class MarkdownOutlineItemView: NSControl {
    var onSelect: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let level: Int
    private var isHovering = false {
        didSet {
            updateAppearance()
        }
    }

    init(item: MarkdownOutlineItem) {
        level = min(max(item.level, 1), 6)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true

        titleLabel.stringValue = item.title.isEmpty ? "Untitled heading" : item.title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: level <= 2 ? .semibold : .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.toolTip = item.title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let leadingInset = 6 + CGFloat(level - 1) * 10
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovering
            ? NSColor.labelColor.withAlphaComponent(0.06).cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isHovering || level <= 2 ? .labelColor : .secondaryLabelColor
    }
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    var onOpenRequested: (() -> Void)?
    var onURLsDropped: (([URL]) -> Void)?
    var onClose: (() -> Void)?

    private let rootView = DropContainerView()
    private let sidebarView = DropSidebarView()
    private let sidebarScrollView = DropScrollView()
    private let tabListDocumentView = DropContainerView()
    private let sidebarStack = NSStackView()
    private let tabStack = NSStackView()
    private let outlineSectionStack = NSStackView()
    private let outlineSeparator = NSBox()
    private let outlineHeaderLabel = NSTextField(labelWithString: "Contents")
    private let outlineStack = NSStackView()
    private let contentView = DropContainerView()
    private let headerView = DropHeaderView()
    private let titleLabel = NSTextField(labelWithString: "Peeky")
    private let metaLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: ["Format", "Raw"], trackingMode: .selectOne, target: nil, action: nil)
    private let foldButton = NSButton()
    private let wrapButton = NSButton()
    private let copyButton = NSButton()
    private let revealButton = NSButton()
    private let openButton = NSButton()
    private let scrollView = DropScrollView()
    private let gutterView = PreviewGutterView()
    private let textView = DropTextView()
    private let emptyView = NSStackView()

    private var tabs: [PreviewTab] = []
    private var activeTabID: UUID?
    private var wrapsLines = true
    private var sidebarWidthConstraint: NSLayoutConstraint?

    var isEmpty: Bool {
        tabs.isEmpty
    }

    init() {
        let window = DropWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Peeky"
        window.minSize = NSSize(width: 680, height: 360)

        super.init(window: window)
        window.delegate = self
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func open(url: URL) {
        open(urls: [url])
    }

    func open(urls: [URL]) {
        open(requests: urls.compactMap(OpenRequest.fileURL))
    }

    func open(requests: [OpenRequest]) {
        var selectedTabID: UUID?

        for request in requests {
            let standardizedURL = request.url.standardizedFileURL
            if let existingIndex = tabs.firstIndex(where: { $0.url.standardizedFileURL == standardizedURL }) {
                selectedTabID = tabs[existingIndex].id
                if request.line != nil {
                    tabs[existingIndex].mode = .raw
                    tabs[existingIndex].targetLine = request.line
                    tabs[existingIndex].targetColumn = request.column
                }
                continue
            }

            var tab = loadTab(url: standardizedURL)
            if request.line != nil {
                tab.mode = .raw
                tab.targetLine = request.line
                tab.targetColumn = request.column
            }
            tabs.append(tab)
            selectedTabID = tab.id
        }

        if let selectedTabID {
            activeTabID = selectedTabID
        } else if activeTabID == nil {
            activeTabID = tabs.first?.id
        }

        rebuildTabList()
        renderActiveTab()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func setupUI() {
        guard let window else { return }

        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        rootView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        window.contentView = rootView

        setupSidebar()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        contentView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        rootView.addSubview(contentView)
        setupHeader()
        setupTextView()
        setupEmptyView()

        let sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: 210)
        self.sidebarWidthConstraint = sidebarWidthConstraint

        NSLayoutConstraint.activate([
            sidebarView.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarWidthConstraint,

            contentView.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        if let dropWindow = window as? DropWindow {
            dropWindow.onDropFiles = { [weak self] urls in
                self?.onURLsDropped?(urls)
            }
            dropWindow.onFileDragActiveChanged = { [weak self] active in
                self?.rootView.setDropHighlight(active)
            }
        }

        showEmptyState()
    }

    private func setupSidebar() {
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.material = .sidebar
        sidebarView.blendingMode = .withinWindow
        sidebarView.state = .active
        sidebarView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        sidebarView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        rootView.addSubview(sidebarView)

        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.autohidesScrollers = true
        sidebarScrollView.borderType = .noBorder
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        sidebarScrollView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        sidebarView.addSubview(sidebarScrollView)

        tabListDocumentView.translatesAutoresizingMaskIntoConstraints = false
        tabListDocumentView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        tabListDocumentView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 10
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        tabListDocumentView.addSubview(sidebarStack)

        tabStack.orientation = .vertical
        tabStack.alignment = .width
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarStack.addArrangedSubview(tabStack)

        outlineSeparator.boxType = .separator
        outlineSeparator.translatesAutoresizingMaskIntoConstraints = false

        outlineHeaderLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        outlineHeaderLabel.textColor = .secondaryLabelColor
        outlineHeaderLabel.lineBreakMode = .byTruncatingTail
        outlineHeaderLabel.maximumNumberOfLines = 1

        outlineStack.orientation = .vertical
        outlineStack.alignment = .width
        outlineStack.spacing = 2
        outlineStack.translatesAutoresizingMaskIntoConstraints = false

        outlineSectionStack.orientation = .vertical
        outlineSectionStack.alignment = .width
        outlineSectionStack.spacing = 6
        outlineSectionStack.translatesAutoresizingMaskIntoConstraints = false
        outlineSectionStack.isHidden = true
        outlineSectionStack.addArrangedSubview(outlineSeparator)
        outlineSectionStack.addArrangedSubview(outlineHeaderLabel)
        outlineSectionStack.addArrangedSubview(outlineStack)
        sidebarStack.addArrangedSubview(outlineSectionStack)
        sidebarScrollView.documentView = tabListDocumentView

        NSLayoutConstraint.activate([
            sidebarScrollView.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 8),
            sidebarScrollView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -8),

            tabListDocumentView.topAnchor.constraint(equalTo: sidebarScrollView.contentView.topAnchor),
            tabListDocumentView.leadingAnchor.constraint(equalTo: sidebarScrollView.contentView.leadingAnchor),
            tabListDocumentView.widthAnchor.constraint(equalTo: sidebarScrollView.contentView.widthAnchor),
            tabListDocumentView.heightAnchor.constraint(greaterThanOrEqualTo: sidebarScrollView.contentView.heightAnchor),

            sidebarStack.topAnchor.constraint(equalTo: tabListDocumentView.topAnchor, constant: 2),
            sidebarStack.leadingAnchor.constraint(equalTo: tabListDocumentView.leadingAnchor, constant: 8),
            sidebarStack.trailingAnchor.constraint(equalTo: tabListDocumentView.trailingAnchor, constant: -8),
            sidebarStack.bottomAnchor.constraint(lessThanOrEqualTo: tabListDocumentView.bottomAnchor, constant: -2),

            outlineSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.material = .headerView
        headerView.blendingMode = .withinWindow
        headerView.state = .active
        headerView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        headerView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        contentView.addSubview(headerView)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1

        metaLabel.font = NSFont.systemFont(ofSize: 11)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.maximumNumberOfLines = 1

        let titleStack = NSStackView(views: [titleLabel, metaLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.setHuggingPriority(.defaultLow, for: .horizontal)

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.selectedSegment = PreviewMode.formatted.rawValue
        modeControl.segmentStyle = .texturedRounded

        configureIconButton(
            foldButton,
            symbol: "arrow.down.right.and.arrow.up.left",
            tooltip: "Collapse nested JSON",
            action: #selector(toggleJSONFolding(_:))
        )
        foldButton.setButtonType(.toggle)
        configureIconButton(wrapButton, symbol: "text.alignleft", tooltip: "Toggle line wrap", action: #selector(toggleWrap(_:)))
        configureIconButton(copyButton, symbol: "doc.on.doc", tooltip: "Copy", action: #selector(copyPreview(_:)))
        configureIconButton(revealButton, symbol: "magnifyingglass", tooltip: "Reveal in Finder", action: #selector(revealInFinder(_:)))
        configureIconButton(openButton, symbol: "folder", tooltip: "Open", action: #selector(openClicked(_:)))

        let controls = NSStackView(views: [modeControl, foldButton, wrapButton, copyButton, revealButton, openButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [titleStack, controls])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerStack)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            headerStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            foldButton.widthAnchor.constraint(equalToConstant: 30),
            wrapButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.widthAnchor.constraint(equalToConstant: 30),
            revealButton.widthAnchor.constraint(equalToConstant: 30),
            openButton.widthAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupTextView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = false
        scrollView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        scrollView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }
        contentView.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.onDropFiles = { [weak self] urls in
            self?.onURLsDropped?(urls)
        }
        textView.onFileDragActiveChanged = { [weak self] active in
            self?.rootView.setDropHighlight(active)
        }

        scrollView.documentView = textView
        gutterView.clientView = textView
        scrollView.verticalRulerView = gutterView
    }

    private func setupEmptyView() {
        emptyView.orientation = .vertical
        emptyView.alignment = .centerX
        emptyView.spacing = 12
        emptyView.translatesAutoresizingMaskIntoConstraints = false

        let appName = NSTextField(labelWithString: "Peeky")
        appName.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        appName.textColor = .labelColor

        let button = NSButton(title: "Open File", target: self, action: #selector(openClicked(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .large

        emptyView.addArrangedSubview(appName)
        emptyView.addArrangedSubview(button)
        contentView.addSubview(emptyView)
    }

    private func loadTab(url: URL) -> PreviewTab {
        do {
            let loaded = try TextFileLoader.load(url: url)
            return PreviewTab(url: loaded.url, document: loaded, errorMessage: nil)
        } catch {
            return PreviewTab(url: url, document: nil, errorMessage: error.localizedDescription)
        }
    }

    private var activeTabIndex: Int? {
        guard let activeTabID else { return nil }
        return tabs.firstIndex { $0.id == activeTabID }
    }

    private var activeTab: PreviewTab? {
        guard let activeTabIndex else { return nil }
        return tabs[activeTabIndex]
    }

    private func rebuildTabList() {
        for view in tabStack.arrangedSubviews {
            tabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        updateSidebarVisibility()

        for tab in tabs {
            let tabView = FileTabView(
                url: tab.url,
                subtitle: tabSubtitle(for: tab),
                isError: tab.errorMessage != nil,
                isSelected: tab.id == activeTabID
            )
            let tabID = tab.id
            tabView.onSelect = { [weak self] in
                self?.selectTab(id: tabID)
            }
            tabView.onClose = { [weak self] in
                self?.closeTab(id: tabID)
            }
            tabStack.addArrangedSubview(tabView)
            tabView.widthAnchor.constraint(equalTo: tabStack.widthAnchor).isActive = true
        }
    }

    private func rebuildMarkdownOutline(_ outline: [MarkdownOutlineItem]) {
        clearMarkdownOutline()

        guard !outline.isEmpty else { return }

        for item in outline {
            let itemView = MarkdownOutlineItemView(item: item)
            itemView.onSelect = { [weak self] in
                self?.scrollToOutlineItem(item)
            }
            outlineStack.addArrangedSubview(itemView)
            itemView.widthAnchor.constraint(equalTo: outlineStack.widthAnchor).isActive = true
        }

        outlineSectionStack.isHidden = false
    }

    private func clearMarkdownOutline() {
        for view in outlineStack.arrangedSubviews {
            outlineStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        outlineSectionStack.isHidden = true
    }

    private func updateSidebarVisibility() {
        let hasTabs = !tabs.isEmpty
        sidebarView.isHidden = !hasTabs
        sidebarScrollView.isHidden = !hasTabs
        sidebarWidthConstraint?.constant = hasTabs ? 240 : 0
        rootView.needsLayout = true
    }

    private func tabSubtitle(for tab: PreviewTab) -> String {
        if let document = tab.document {
            return [
                document.kind.displayName,
                ByteCountFormatter.string(fromByteCount: document.totalBytes, countStyle: .file)
            ].joined(separator: " | ")
        }

        return "Open failed"
    }

    private func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        rebuildTabList()
        renderActiveTab()
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingActiveTab = tabs[index].id == activeTabID
        tabs.remove(at: index)

        if tabs.isEmpty {
            activeTabID = nil
        } else if closingActiveTab {
            activeTabID = tabs[min(index, tabs.count - 1)].id
        }

        rebuildTabList()
        renderActiveTab()
    }

    private func renderActiveTab() {
        guard let tab = activeTab else {
            showEmptyState()
            return
        }

        titleLabel.stringValue = tab.url.lastPathComponent
        window?.title = tab.url.lastPathComponent
        window?.representedURL = tab.url

        if let document = tab.document {
            render(
                document: document,
                mode: tab.mode,
                collapseNestedJSON: tab.collapseNestedJSON,
                targetLine: tab.targetLine,
                tabID: tab.id
            )
        } else {
            renderError(message: tab.errorMessage ?? "Open failed", url: tab.url)
        }

        clearTargetPosition(for: tab.id)
    }

    private func render(
        document: LoadedText,
        mode: PreviewMode,
        collapseNestedJSON: Bool,
        targetLine: Int?,
        tabID: UUID
    ) {
        modeControl.selectedSegment = mode.rawValue
        modeControl.isEnabled = document.kind.hasFormattedPreview
        modeControl.setLabel(document.kind == .markdown ? "Preview" : "Format", forSegment: 0)

        let canFoldJSON = (document.kind == .json || document.kind == .jsonl) && mode == .formatted
        foldButton.isEnabled = canFoldJSON
        foldButton.state = collapseNestedJSON && canFoldJSON ? .on : .off
        foldButton.toolTip = collapseNestedJSON && canFoldJSON
            ? "Expand nested JSON"
            : "Collapse nested JSON"

        let rendered = PreviewRenderer.render(
            document: document,
            mode: mode,
            collapseNestedJSON: collapseNestedJSON && canFoldJSON
        )
        textView.textStorage?.setAttributedString(rendered.attributedText)
        applyDisplayMetadata(rendered.display)
        if document.kind == .markdown {
            rebuildMarkdownOutline(rendered.outline)
        } else {
            clearMarkdownOutline()
        }

        let baseSummary = [
            document.kind.displayName,
            ByteCountFormatter.string(fromByteCount: document.totalBytes, countStyle: .file),
            document.encodingName
        ].joined(separator: "  |  ")

        var summary = baseSummary
        if document.isTruncated {
            summary += "  |  Previewing first \(ByteCountFormatter.string(fromByteCount: Int64(document.readBytes), countStyle: .file))"
        }
        if let note = rendered.note {
            summary += "  |  \(note)"
        }
        if let targetLine {
            summary += "  |  Line \(targetLine)"
        }

        metaLabel.stringValue = summary
        revealButton.isEnabled = true
        copyButton.isEnabled = true
        showPreviewState()
        applyLineWrapping()
        let targetLocation = targetLine.flatMap { rendered.display.targetLocationsByOriginalLine[$0] }
        scheduleInitialScroll(targetLine: targetLine, targetLocation: targetLocation, tabID: tabID)
    }

    private func renderError(message: String, url: URL) {
        titleLabel.stringValue = url.lastPathComponent
        metaLabel.stringValue = "Open failed"
        modeControl.isEnabled = false
        foldButton.isEnabled = false
        foldButton.state = .off
        revealButton.isEnabled = true
        copyButton.isEnabled = true

        textView.textStorage?.setAttributedString(SyntaxHighlighter.monospace(message))
        applyDisplayMetadata(.plain)
        clearMarkdownOutline()
        showPreviewState()
        applyLineWrapping()
    }

    private func applyDisplayMetadata(_ display: PreviewDisplayMetadata) {
        gutterView.configuration = display.gutter
        scrollView.rulersVisible = display.gutter.isVisible
        textView.overlayConfiguration = display.textOverlay
    }

    private func clearTargetPosition(for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].targetLine = nil
        tabs[index].targetColumn = nil
    }

    private func scheduleInitialScroll(targetLine: Int?, targetLocation: Int?, tabID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeTabID == tabID else { return }

            if let targetLocation {
                self.scrollToCharacterLocation(targetLocation)
            } else if let targetLine {
                self.scrollToLine(targetLine)
            } else {
                let topRange = NSRange(location: 0, length: 0)
                self.textView.setSelectedRange(topRange)
                self.textView.scrollRangeToVisible(topRange)
            }
        }
    }

    private func scrollToLine(_ line: Int) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let location = characterOffset(forLine: line, in: text)
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
    }

    private func scrollToOutlineItem(_ item: MarkdownOutlineItem) {
        if activeTab?.mode == .formatted, let renderedLocation = item.renderedLocation {
            scrollToCharacterLocation(renderedLocation)
        } else {
            scrollToLine(item.sourceLine)
        }
    }

    private func scrollToCharacterLocation(_ location: Int) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let safeLocation = min(max(location, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))
        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
    }

    private func characterOffset(forLine targetLine: Int, in text: NSString) -> Int {
        guard targetLine > 1 else { return 0 }

        var currentLine = 1
        var location = 0

        while currentLine < targetLine, location < text.length {
            let searchRange = NSRange(location: location, length: text.length - location)
            let newlineRange = text.range(of: "\n", options: [], range: searchRange)
            guard newlineRange.location != NSNotFound else {
                return text.length
            }

            location = newlineRange.location + newlineRange.length
            currentLine += 1
        }

        return min(location, text.length)
    }

    private func showEmptyState() {
        updateSidebarVisibility()
        window?.title = "Peeky"
        window?.representedURL = nil
        titleLabel.stringValue = "Peeky"
        emptyView.isHidden = false
        scrollView.isHidden = true
        modeControl.isEnabled = false
        foldButton.isEnabled = false
        foldButton.state = .off
        revealButton.isEnabled = false
        copyButton.isEnabled = false
        metaLabel.stringValue = ""
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        applyDisplayMetadata(.plain)
        clearMarkdownOutline()
    }

    private func showPreviewState() {
        updateSidebarVisibility()
        emptyView.isHidden = true
        scrollView.isHidden = false
    }

    private func applyLineWrapping() {
        if wrapsLines {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.toolTip = tooltip
        button.target = self
        button.action = action
    }

    @objc private func openClicked(_ sender: Any?) {
        onOpenRequested?()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let index = activeTabIndex else { return }
        tabs[index].mode = PreviewMode(rawValue: sender.selectedSegment) ?? .formatted
        renderActiveTab()
    }

    @objc private func toggleJSONFolding(_ sender: Any?) {
        guard
            let index = activeTabIndex,
            let document = tabs[index].document,
            document.kind == .json || document.kind == .jsonl
        else {
            return
        }

        tabs[index].collapseNestedJSON.toggle()
        renderActiveTab()
    }

    @objc private func toggleWrap(_ sender: Any?) {
        wrapsLines.toggle()
        applyLineWrapping()
    }

    @objc private func copyPreview(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let url = activeTab?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
