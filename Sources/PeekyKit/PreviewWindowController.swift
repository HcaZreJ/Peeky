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
    /// 后台构建好的 JSON/JSONL 树索引缓存；tab 重新激活时直接复用，不重新构建。
    var jsonTreeIndex: JSONTreeIndex?
    /// JSON/JSONL tab 的树/原文视图选择；per-tab 记录，切 tab 保持各自状态。
    var jsonTreeVisible: Bool

    init(url: URL, document: LoadedText?, errorMessage: String?) {
        self.id = UUID()
        self.url = url
        self.document = document
        self.errorMessage = errorMessage
        self.mode = .formatted
        self.collapseNestedJSON = false
        self.targetLine = nil
        self.targetColumn = nil
        self.jsonTreeVisible = true
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

        // 左对齐；x 起点 = 12 + (level-1)*12（相对侧栏左缘）。sidebarStack 自身已带 8pt
        // 左内边距，itemView 本地再补 4pt 即落在侧栏坐标系的 x=12/24/36...；额外 +2 用于
        // 抵消 NSTextField 默认 alignmentRect 相对 frame 左右各内缩 2pt 的系统性偏移
        // （frame.origin.x 才是视觉/dump 关心的真实渲染位置）。
        let leadingInset = 6 + CGFloat(level - 1) * 12
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20)
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

/// 作为 NSScrollView documentView 使用的纵向栈：翻转坐标系让内容顶部对齐、
/// 初始视口停在最上（未翻转的 documentView 超出视口时停靠底部）。
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    var onOpenRequested: (() -> Void)?
    var onURLsDropped: (([URL]) -> Void)?
    var onClose: (() -> Void)?

    private let rootView = DropContainerView()
    private let sidebarView = DropSidebarView()
    private let sidebarScrollView = DropScrollView()
    private let tabListDocumentView = DropContainerView()
    private let sidebarStack = NSStackView()
    private let tabSectionStack = NSStackView()
    private let tabHeaderStack = NSStackView()
    private let tabHeaderLabel = NSTextField(labelWithString: "OPEN")
    private let tabSectionSeparator = NSBox()
    private let fileTreeSectionStack = NSStackView()
    private let fileTreeHeaderStack = NSStackView()
    private let fileTreeHeaderLabel = NSTextField(labelWithString: "FILES")
    private let fileTreeDisclosureButton = NSButton()
    private let fileTreeView = FileTreeView()
    private let tabStack = NSStackView()
    private let outlineSectionStack = NSStackView()
    private let outlineSeparator = NSBox()
    private let outlineHeaderStack = NSStackView()
    private let outlineHeaderLabel = NSTextField(labelWithString: "CONTENTS")
    private let outlineScrollView = NSScrollView()
    private let outlineStack = FlippedStackView()
    private let contentView = DropContainerView()
    private let headerView = DropHeaderView()
    private let titleLabel = NSTextField(labelWithString: "Peeky")
    private let metaLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: ["Format", "Raw"], trackingMode: .selectOne, target: nil, action: nil)
    private let jsonViewToggle = NSSegmentedControl(labels: ["Tree", "Text"], trackingMode: .selectOne, target: nil, action: nil)
    private let foldButton = NSButton()
    private let wrapButton = NSButton()
    private let copyButton = NSButton()
    private let revealButton = NSButton()
    private let openButton = NSButton()
    private let copyMenu = NSMenu()
    private var copyRelativePathMenuItem: NSMenuItem?
    private let scrollView = DropScrollView()
    private let gutterView = PreviewGutterView()
    private let textView = DropTextView()
    private let jsonOutlineView = JSONOutlineView()
    private let emptyView = NSStackView()

    private var tabs: [PreviewTab] = []
    private var activeTabID: UUID?
    private var wrapsLines = true
    /// 递增即作废在途布局泵；每次内容或换行模式变化后 startLayoutPump() 重启。
    private var layoutPumpGeneration = 0
    /// 递增即作废在途高亮分块流；tab 切换/关闭/重新渲染时 invalidateHighlighting() 推进，
    /// 在途 Task 据此丢弃迟到的 chunk，杜绝旧文档颜色刷到新文档上。
    private var highlightGeneration = 0
    private var highlightTask: Task<Void, Never>?
    /// Markdown 围栏代码块逐块高亮 Task 集合（一个 markdown 文档可含多个代码块，
    /// 各自独立起 Task）；invalidateHighlighting() 与 highlightTask 一并取消清空。
    private var codeBlockHighlightTasks: [Task<Void, Never>] = []
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var isFileTreeCollapsed = false
    /// 当前文件树的根目录；nil 表示尚未打开过任何文件/目录，树区未建立。
    private var treeRootURL: URL?

    var isEmpty: Bool {
        tabs.isEmpty
    }

    var activeFileURL: URL? {
        activeTab?.url
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

            if standardizedURL.hasDirectoryPath {
                // 目录请求不产生内容 tab，仅设置/切换树根（TextFileLoader 拒目录的行为保留）。
                establishTreeRoot(for: standardizedURL)
                continue
            }

            if let existingIndex = tabs.firstIndex(where: { $0.url.standardizedFileURL == standardizedURL }) {
                selectedTabID = tabs[existingIndex].id
                if request.line != nil {
                    tabs[existingIndex].mode = .raw
                    tabs[existingIndex].targetLine = request.line
                    tabs[existingIndex].targetColumn = request.column
                }
                establishTreeRoot(for: standardizedURL)
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
            establishTreeRoot(for: standardizedURL)
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

    /// 窗口 resize（含拖拽 live resize 逐帧）实时重算限宽阅读列内边距（R4f）；
    /// 非 markdown formatted 状态下该调用是零成本的 no-op（复位到默认全宽内边距）。
    func windowDidResize(_ notification: Notification) {
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
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
        setupJSONOutlineView()
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

            jsonOutlineView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            jsonOutlineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            jsonOutlineView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            jsonOutlineView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
        sidebarStack.spacing = 8
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        tabListDocumentView.addSubview(sidebarStack)

        // 区块顺序：OPEN（tab）→ FILES（树）→ CONTENTS（大纲）。
        setupTabSection()
        sidebarStack.addArrangedSubview(tabSectionStack)

        setupFileTreeSection()
        sidebarStack.addArrangedSubview(fileTreeSectionStack)

        setupOutlineSection()
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

            // 分隔线需要显式 width 绑定到所在分区，否则 NSBox .separator 会退化成其
            // 极窄的 intrinsic 宽度（视觉上等于没有分隔线）。分区宽度已 == sidebarStack
            // 宽度，而 sidebarStack 相对 tabListDocumentView 自身左右各留 8pt，分隔线
            // 因此天然满足"左右各留 8pt 内边距"，无需再额外内缩。
            tabSectionSeparator.heightAnchor.constraint(equalToConstant: 1),
            tabSectionSeparator.widthAnchor.constraint(equalTo: tabSectionStack.widthAnchor),
            outlineSeparator.heightAnchor.constraint(equalToConstant: 1),
            outlineSeparator.widthAnchor.constraint(equalTo: outlineSectionStack.widthAnchor),

            // 三区标题行左对齐 x=12pt（相对侧栏）：sidebarStack 自身已带 8pt 左内边距，
            // 标题行在此再补 6pt（4pt 版式内边距 + 2pt 用于抵消标题 NSTextField 的
            // alignmentRect 系统性左内缩，使 frame.origin.x 落在 12）；右侧留 8pt，
            // 与分隔线的左右内边距一致。
            tabHeaderStack.leadingAnchor.constraint(equalTo: tabSectionStack.leadingAnchor, constant: 6),
            tabHeaderStack.trailingAnchor.constraint(equalTo: tabSectionStack.trailingAnchor, constant: -8),
            tabStack.widthAnchor.constraint(equalTo: tabSectionStack.widthAnchor),
            fileTreeHeaderStack.leadingAnchor.constraint(equalTo: fileTreeSectionStack.leadingAnchor, constant: 6),
            fileTreeHeaderStack.trailingAnchor.constraint(equalTo: fileTreeSectionStack.trailingAnchor, constant: -8),
            fileTreeView.widthAnchor.constraint(equalTo: fileTreeSectionStack.widthAnchor),
            outlineHeaderStack.leadingAnchor.constraint(equalTo: outlineSectionStack.leadingAnchor, constant: 6),
            outlineHeaderStack.trailingAnchor.constraint(equalTo: outlineSectionStack.trailingAnchor, constant: -8),
            outlineScrollView.widthAnchor.constraint(equalTo: outlineSectionStack.widthAnchor),

            tabSectionStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),
            fileTreeSectionStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),
            outlineSectionStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),

            // CONTENTS 高度=内容，上限为侧栏高的 35%，超出时 outlineScrollView 内部滚动。
            outlineScrollView.heightAnchor.constraint(lessThanOrEqualTo: sidebarView.heightAnchor, multiplier: 0.35)
        ])

        // 优先级须低于 NSWindow 隐式"保持当前尺寸"(~500)：内容超过 35% 上限时
        // 此等式断开、区高停在上限，而不是以更高优先级把窗口撑大。
        let outlineHuggingHeight = outlineScrollView.heightAnchor.constraint(equalTo: outlineStack.heightAnchor)
        outlineHuggingHeight.priority = .defaultLow
        outlineHuggingHeight.isActive = true
    }

    /// 「OPEN」tab 分区：小节标题 + 既有 tabStack（卡片样式不变，只挪到侧栏顶部）；
    /// tabs 为空时整区（含尾部分隔线）隐藏，见 rebuildTabList。
    private func setupTabSection() {
        tabHeaderLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        tabHeaderLabel.textColor = .secondaryLabelColor
        tabHeaderLabel.lineBreakMode = .byTruncatingTail
        tabHeaderLabel.maximumNumberOfLines = 1

        tabHeaderStack.orientation = .horizontal
        tabHeaderStack.alignment = .centerY
        tabHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        tabHeaderStack.addArrangedSubview(tabHeaderLabel)

        tabStack.orientation = .vertical
        tabStack.alignment = .width
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        tabSectionSeparator.boxType = .separator
        tabSectionSeparator.translatesAutoresizingMaskIntoConstraints = false

        tabSectionStack.orientation = .vertical
        tabSectionStack.alignment = .width
        tabSectionStack.spacing = 4
        tabSectionStack.translatesAutoresizingMaskIntoConstraints = false
        tabSectionStack.isHidden = true
        tabSectionStack.addArrangedSubview(tabHeaderStack)
        tabSectionStack.addArrangedSubview(tabStack)
        tabSectionStack.addArrangedSubview(tabSectionSeparator)
        tabSectionStack.setCustomSpacing(8, after: tabStack)
    }

    /// 「FILES」文件树分区：小节标题 + 可折叠 disclosure + FileTreeView。样式沿用既有
    /// outline 分区（outlineSeparator/outlineHeaderLabel）的字体/颜色约定。
    private func setupFileTreeSection() {
        fileTreeHeaderLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        fileTreeHeaderLabel.textColor = .secondaryLabelColor
        fileTreeHeaderLabel.lineBreakMode = .byTruncatingTail
        fileTreeHeaderLabel.maximumNumberOfLines = 1
        fileTreeHeaderLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        fileTreeDisclosureButton.title = ""
        fileTreeDisclosureButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Toggle file tree")
        fileTreeDisclosureButton.imagePosition = .imageOnly
        fileTreeDisclosureButton.isBordered = false
        fileTreeDisclosureButton.setButtonType(.momentaryPushIn)
        fileTreeDisclosureButton.toolTip = "Toggle file tree"
        fileTreeDisclosureButton.target = self
        fileTreeDisclosureButton.action = #selector(toggleFileTreeCollapsed(_:))
        fileTreeDisclosureButton.setContentHuggingPriority(.required, for: .horizontal)

        fileTreeHeaderStack.orientation = .horizontal
        fileTreeHeaderStack.alignment = .centerY
        fileTreeHeaderStack.spacing = 4
        fileTreeHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        fileTreeHeaderStack.addArrangedSubview(fileTreeHeaderLabel)
        fileTreeHeaderStack.addArrangedSubview(fileTreeDisclosureButton)

        fileTreeView.translatesAutoresizingMaskIntoConstraints = false
        fileTreeView.onFileClick = { [weak self] url in
            self?.open(url: url)
        }

        fileTreeSectionStack.orientation = .vertical
        fileTreeSectionStack.alignment = .width
        fileTreeSectionStack.spacing = 4
        fileTreeSectionStack.translatesAutoresizingMaskIntoConstraints = false
        fileTreeSectionStack.isHidden = true
        fileTreeSectionStack.addArrangedSubview(fileTreeHeaderStack)
        fileTreeSectionStack.addArrangedSubview(fileTreeView)
    }

    /// 「CONTENTS」大纲分区：分隔线 + 小节标题 + 可滚动大纲列表。高度随内容，
    /// 上限为侧栏高度的 35%；超出内部滚动，避免把 FILES 区挤没。非 markdown 文档时
    /// 整区（含分隔线）隐藏，见 rebuildMarkdownOutline / clearMarkdownOutline。
    private func setupOutlineSection() {
        outlineSeparator.boxType = .separator
        outlineSeparator.translatesAutoresizingMaskIntoConstraints = false

        outlineHeaderLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        outlineHeaderLabel.textColor = .secondaryLabelColor
        outlineHeaderLabel.lineBreakMode = .byTruncatingTail
        outlineHeaderLabel.maximumNumberOfLines = 1

        outlineHeaderStack.orientation = .horizontal
        outlineHeaderStack.alignment = .centerY
        outlineHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        outlineHeaderStack.addArrangedSubview(outlineHeaderLabel)

        outlineStack.orientation = .vertical
        outlineStack.alignment = .width
        outlineStack.spacing = 0
        outlineStack.translatesAutoresizingMaskIntoConstraints = false

        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.hasHorizontalScroller = false
        outlineScrollView.autohidesScrollers = true
        outlineScrollView.borderType = .noBorder
        outlineScrollView.drawsBackground = false
        outlineScrollView.documentView = outlineStack

        // documentView 只钉 top/leading/trailing，高度由条目内容自撑：内容超过
        // 35% 上限时在 clip 内滚动。bottom 若与 clipView 钉成等式，大纲总高会经
        // 35% 上限反推成侧栏/窗口的硬性最小高度，标题多的文档会把窗口撑出屏幕。
        NSLayoutConstraint.activate([
            outlineStack.topAnchor.constraint(equalTo: outlineScrollView.contentView.topAnchor),
            outlineStack.leadingAnchor.constraint(equalTo: outlineScrollView.contentView.leadingAnchor),
            outlineStack.trailingAnchor.constraint(equalTo: outlineScrollView.contentView.trailingAnchor)
        ])

        outlineSectionStack.orientation = .vertical
        outlineSectionStack.alignment = .width
        outlineSectionStack.spacing = 4
        outlineSectionStack.translatesAutoresizingMaskIntoConstraints = false
        outlineSectionStack.isHidden = true
        outlineSectionStack.addArrangedSubview(outlineSeparator)
        outlineSectionStack.addArrangedSubview(outlineHeaderStack)
        outlineSectionStack.addArrangedSubview(outlineScrollView)
        outlineSectionStack.setCustomSpacing(8, after: outlineSeparator)
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

        jsonViewToggle.target = self
        jsonViewToggle.action = #selector(jsonViewModeChanged(_:))
        jsonViewToggle.selectedSegment = 0
        jsonViewToggle.segmentStyle = .texturedRounded
        jsonViewToggle.isHidden = true
        jsonViewToggle.toolTip = "Switch between tree and raw text view"

        configureIconButton(
            foldButton,
            symbol: "arrow.down.right.and.arrow.up.left",
            tooltip: "Collapse nested JSON",
            action: #selector(toggleJSONFolding(_:))
        )
        foldButton.setButtonType(.toggle)
        configureIconButton(wrapButton, symbol: "text.alignleft", tooltip: "Toggle line wrap", action: #selector(toggleWrap(_:)))
        configureIconButton(copyButton, symbol: "doc.on.doc", tooltip: "Copy", action: #selector(showCopyMenu(_:)))
        configureIconButton(revealButton, symbol: "magnifyingglass", tooltip: "Reveal in Finder", action: #selector(revealInFinder(_:)))
        configureIconButton(openButton, symbol: "folder", tooltip: "Open", action: #selector(openClicked(_:)))
        configureCopyMenu()

        let controls = NSStackView(views: [modeControl, jsonViewToggle, foldButton, wrapButton, copyButton, revealButton, openButton])
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
        // 大纲跳转 / peeky:// 行定位会用 setSelectedRange 选中整行做定位反馈；
        // 未聚焦时 AppKit 默认用非强调灰色高亮整行，深色模式下在标题行上格外
        // 显眼，故关闭选中背景色，只保留滚动定位本身。
        textView.selectedTextAttributes = [.backgroundColor: NSColor.clear]
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
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = gutterView
        gutterView.connect(textView: textView, scrollView: scrollView)
    }

    /// JSON/JSONL 默认视图：树。与 scrollView 同区域叠放，按 showJSONTree/showPlainText
    /// 二选一显示；结构由树的系统缩进 + disclosure 三角表达，故树可见时行号 gutter
    /// （scrollView 的 verticalRulerView）随 scrollView 一起隐藏。
    private func setupJSONOutlineView() {
        jsonOutlineView.translatesAutoresizingMaskIntoConstraints = false
        jsonOutlineView.isHidden = true
        contentView.addSubview(jsonOutlineView)
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

    /// 树根 = RepoRoot.discover(from: target) ?? (target 为目录 ? target : 其父目录)。
    /// 根已存在且 target 仍在根内 → 不重建，只 revealAndSelect；target 在根外 → 重算根并 reload。
    private func establishTreeRoot(for target: URL) {
        let standardizedTarget = target.standardizedFileURL
        let targetIsDirectory = standardizedTarget.hasDirectoryPath

        if let currentRoot = treeRootURL, isURL(standardizedTarget, containedIn: currentRoot) {
            if !targetIsDirectory {
                fileTreeView.revealAndSelect(fileURL: standardizedTarget)
            }
            return
        }

        let newRoot = RepoRoot.discover(from: standardizedTarget)
            ?? (targetIsDirectory ? standardizedTarget : standardizedTarget.deletingLastPathComponent())

        treeRootURL = newRoot
        fileTreeSectionStack.isHidden = false
        fileTreeView.reload(root: newRoot)

        if !targetIsDirectory {
            fileTreeView.revealAndSelect(fileURL: standardizedTarget)
        }
    }

    private func isURL(_ url: URL, containedIn root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count >= rootComponents.count else { return false }
        return Array(urlComponents.prefix(rootComponents.count)) == rootComponents
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

        tabSectionStack.isHidden = tabs.isEmpty
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
        let hasContent = !tabs.isEmpty || treeRootURL != nil
        sidebarView.isHidden = !hasContent
        sidebarScrollView.isHidden = !hasContent
        sidebarWidthConstraint?.constant = hasContent ? 240 : 0
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
        invalidateHighlighting()

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
                jsonTreeVisible: tab.jsonTreeVisible,
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
        jsonTreeVisible: Bool,
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
        applyEditorTheme(usesDarkModern: rendered.usesDarkModernTheme)
        if let language = rendered.highlightLanguage {
            startHighlighting(text: document.text, language: language, tabID: tabID)
        }
        if document.kind == .markdown {
            rebuildMarkdownOutline(rendered.outline)
            if mode == .formatted {
                highlightMarkdownCodeBlocks(tabID: tabID)
            }
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
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
        let targetLocation = targetLine.flatMap { rendered.display.targetLocationsByOriginalLine[$0] }
        scheduleInitialScroll(targetLine: targetLine, targetLocation: targetLocation, tabID: tabID)

        if document.kind == .json || document.kind == .jsonl {
            jsonViewToggle.isHidden = false
            jsonViewToggle.isEnabled = true
            jsonViewToggle.selectedSegment = jsonTreeVisible ? 0 : 1
            if jsonTreeVisible {
                presentJSONTree(document: document, tabID: tabID)
            } else {
                showPlainText()
            }
        } else {
            jsonViewToggle.isHidden = true
            showPlainText()
        }
    }

    private func renderError(message: String, url: URL) {
        titleLabel.stringValue = url.lastPathComponent
        metaLabel.stringValue = "Open failed"
        modeControl.isEnabled = false
        jsonViewToggle.isHidden = true
        foldButton.isEnabled = false
        foldButton.state = .off
        revealButton.isEnabled = true
        copyButton.isEnabled = true

        textView.textStorage?.setAttributedString(SyntaxHighlighter.monospace(message))
        applyDisplayMetadata(.plain)
        applyEditorTheme(usesDarkModern: false)
        clearMarkdownOutline()
        showPreviewState()
        showPlainText()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
    }

    // MARK: - JSON 树 / 原文切换

    /// JSON 树当前是否为可见视图（json/jsonl tab 且未切到原文）；供主菜单折叠命令族
    /// （全部展开/全部折叠/折叠到第 N 层）的可用性判定。
    var isJSONTreeActive: Bool {
        guard let tab = activeTab, let document = tab.document else { return false }
        return (document.kind == .json || document.kind == .jsonl) && tab.jsonTreeVisible
    }

    func expandJSONTreeAll() {
        jsonOutlineView.expandAll()
    }

    func collapseJSONTreeAll() {
        jsonOutlineView.collapseAll()
    }

    func collapseJSONTree(toLevel level: Int) {
        jsonOutlineView.collapseToLevel(level)
    }

    /// JSON/JSONL 默认视图 = 树：索引已缓存（tab 曾激活过）直接无闪切换；否则先保持
    /// 原文文本视图可见，后台构建索引，就绪且该 tab 仍激活时才切到树，避免闪切换/
    /// 切错 tab 的竞态。
    private func presentJSONTree(document: LoadedText, tabID: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        if let cachedIndex = tabs[tabIndex].jsonTreeIndex {
            showJSONTree(cachedIndex)
            return
        }

        showPlainText()

        let text = document.text
        let kind = document.kind
        DispatchQueue.global(qos: .userInitiated).async {
            let builtIndex = JSONTreeIndex.build(text: text, kind: kind)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let currentTabIndex = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                self.tabs[currentTabIndex].jsonTreeIndex = builtIndex
                guard self.activeTabID == tabID else { return }
                self.showJSONTree(builtIndex)
            }
        }
    }

    private func showJSONTree(_ index: JSONTreeIndex) {
        guard let document = activeTab?.document else { return }
        jsonOutlineView.setContent(index: index, text: document.text, kind: document.kind)
        scrollView.isHidden = true
        jsonOutlineView.isHidden = false
    }

    private func showPlainText() {
        jsonOutlineView.isHidden = true
        jsonOutlineView.reset()
        scrollView.isHidden = false
    }

    private func applyDisplayMetadata(_ display: PreviewDisplayMetadata) {
        gutterView.configuration = display.gutter
        textView.overlayConfiguration = display.textOverlay
    }

    // MARK: - 限宽阅读列（R4f）：markdown formatted 模式正文列定宽居中

    /// 当前是否应处于限宽阅读列状态：markdown + formatted + 开启折行。关闭折行时
    /// textView 走水平滚动（isHorizontallyResizable=true / widthTracksTextView=false），
    /// 折行意义上的"列宽"不成立，故此时与非 markdown 一样退回默认全宽。
    private var isMarkdownReadingColumnActive: Bool {
        guard wrapsLines, let tab = activeTab, let document = tab.document else { return false }
        return document.kind == .markdown && tab.mode == .formatted
    }

    /// 实现取舍：textView 保持既有 widthTracksTextView=true 全宽栈不变（折行/选中/
    /// 复制/gutter 行号换算全部沿用现有管线，零改动），只动态调
    /// textContainerInset.width 做左右对称内边距——AppKit 在 widthTracksTextView=true
    /// 时按 (textView.frame.width − 2×textContainerInset.width) 换算实际排版宽度，
    /// 折行天然按此列宽发生；字符定位（scrollToLine/scrollToOutlineItem 等）全程只用
    /// NSRange 字符偏移，不含任何 x 坐标假设，故不受水平内边距变化影响。
    /// 列宽 = min(42×16pt 正文字号≈672pt, 可用宽−2×24pt 最小边距)，居中；
    /// 非 markdown / raw / 关闭折行时复位到既有默认 18pt 内边距（现状全宽行为）。
    private func applyMarkdownReadingColumn(isActive: Bool) {
        guard isActive else {
            textView.textContainerInset = NSSize(width: 18, height: 16)
            return
        }

        let columnMaxWidth: CGFloat = 42 * 16
        let minMargin: CGFloat = 24
        let availableWidth = scrollView.contentSize.width

        let margin = availableWidth > columnMaxWidth
            ? (availableWidth - columnMaxWidth) / 2
            : min(minMargin, max(0, availableWidth / 2))

        textView.textContainerInset = NSSize(width: margin, height: 16)
    }

    // MARK: - 高亮接入（R4e）：Dark Modern 主题 + 分块原位上色

    /// 编辑器区（scrollView + textView + gutterView）整体切 Dark Modern 外观：显式覆盖
    /// appearance 让 indent guides/record 注解等既有动态系统色（DropTextView 内绘制）
    /// 也随之解析为深色变体；背景/gutter 精确色值另见 DarkModernTheme。
    private func applyEditorTheme(usesDarkModern: Bool) {
        let appearance = usesDarkModern ? NSAppearance(named: .darkAqua) : nil
        scrollView.appearance = appearance
        textView.appearance = appearance
        gutterView.appearance = appearance
        textView.backgroundColor = usesDarkModern ? DarkModernTheme.background : .textBackgroundColor
        gutterView.usesDarkModernTheme = usesDarkModern
    }

    /// 递增高亮代际并取消在途分块流；tab 切换/关闭/重新渲染前必调，防止旧文档的
    /// 迟到 chunk 刷到新内容上。
    private func invalidateHighlighting() {
        highlightTask?.cancel()
        highlightTask = nil
        for task in codeBlockHighlightTasks {
            task.cancel()
        }
        codeBlockHighlightTasks.removeAll()
        highlightGeneration += 1
    }

    /// 起后台分块高亮流：首块（200 行）优先泵送，逐块到达即在主线程原位 addAttribute
    /// 上色，绝不整文重设 attributedString。代际 + 当前活跃 tab 双重校验，过期结果丢弃。
    private func startHighlighting(text: String, language: String, tabID: UUID) {
        guard let stream = HighlightService.shared.highlightStream(text: text, language: language) else {
            return
        }

        let generation = highlightGeneration
        let lineStarts = PreviewDisplayMetadata.lineStartLocations(in: text)

        highlightTask = Task { @MainActor [weak self] in
            for await chunk in stream {
                guard let self, !Task.isCancelled else { return }
                guard self.highlightGeneration == generation, self.activeTabID == tabID else { return }
                self.applyHighlightChunk(chunk, lineStarts: lineStarts)
            }
        }
    }

    private func applyHighlightChunk(_ chunk: HighlightChunk, lineStarts: [Int]) {
        guard let textStorage = textView.textStorage else { return }
        let totalLength = textStorage.length

        textStorage.beginEditing()
        for (offset, line) in chunk.lines.enumerated() {
            let lineIndex = chunk.firstLine + offset
            guard lineIndex < lineStarts.count else { continue }

            var location = lineStarts[lineIndex]
            for token in line {
                let length = (token.text as NSString).length
                guard length > 0 else { continue }
                guard location + length <= totalLength else { break }
                textStorage.addAttribute(
                    .foregroundColor,
                    value: highlightColor(fromHex: token.colorHex),
                    range: NSRange(location: location, length: length)
                )
                location += length
            }
        }
        textStorage.endEditing()
    }

    /// Markdown 围栏代码块语言标记（``` py / ```TypeScript 等，来自
    /// `MarkdownRenderer.codeLanguageAttributeKey`）到 shiki language id 的别名
    /// 映射；未识别的语言/空标记返回 nil，调用方保持该代码块现状（只有底色块，
    /// 不上色）。HighlightService 本身只认精确的 shiki language id，不做别名
    /// 归一化，故映射放在消费端而非 HighlightService.swift。
    private static let fenceCodeLanguageAliases: [String: String] = [
        "python": "python", "py": "python",
        "typescript": "typescript", "ts": "typescript",
        "javascript": "javascript", "js": "javascript", "node": "javascript",
        "json": "json", "jsonc": "json",
        "yaml": "yaml", "yml": "yaml",
        "toml": "toml",
        "bash": "bash", "sh": "bash", "shell": "bash", "zsh": "bash",
        "swift": "swift",
        "ini": "ini", "conf": "ini", "config": "ini"
    ]

    private static func shikiLanguage(forFenceTag fenceTag: String) -> String? {
        fenceCodeLanguageAliases[fenceTag.lowercased()]
    }

    /// Markdown formatted 渲染落定（textStorage 已 setAttributedString）后，扫描
    /// 其中带 `MarkdownRenderer.codeLanguageAttributeKey` 的围栏代码块 run；每个
    /// 识别出 shiki language 的代码块各自起一个高亮 Task，落地后按行/列偏移原位
    /// `addAttribute(.foregroundColor)` 上色（同 applyHighlightChunk 语义，不
    /// 整体重设 attributedString）。run 的字符区间在上色期间不变——markdown 渲染
    /// 是一次性 setAttributedString，这里只 addAttribute。代际 + activeTabID
    /// 双重校验复用 startHighlighting 的既有防护语义，杜绝切 tab/重渲染后迟到的
    /// 上色任务刷到新内容上。
    private func highlightMarkdownCodeBlocks(tabID: UUID) {
        guard let textStorage = textView.textStorage else { return }

        let generation = highlightGeneration
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let fullText = textStorage.string as NSString

        textStorage.enumerateAttribute(
            MarkdownRenderer.codeLanguageAttributeKey,
            in: fullRange,
            options: []
        ) { value, range, _ in
            guard
                let fenceTag = value as? String,
                let language = Self.shikiLanguage(forFenceTag: fenceTag),
                range.length > 0
            else {
                return
            }

            let code = fullText.substring(with: range)
            let lineStarts = PreviewDisplayMetadata.lineStartLocations(in: code)

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                guard let lines = await HighlightService.shared.highlight(text: code, language: language) else { return }
                guard !Task.isCancelled else { return }
                guard self.highlightGeneration == generation, self.activeTabID == tabID else { return }
                self.applyCodeBlockTokens(lines, blockRange: range, lineStarts: lineStarts, textStorage: textStorage)
            }
            codeBlockHighlightTasks.append(task)
        }
    }

    private func applyCodeBlockTokens(
        _ lines: [HighlightedLine],
        blockRange: NSRange,
        lineStarts: [Int],
        textStorage: NSTextStorage
    ) {
        let totalLength = textStorage.length
        let blockEnd = blockRange.location + blockRange.length

        textStorage.beginEditing()
        for (lineIndex, line) in lines.enumerated() {
            guard lineIndex < lineStarts.count else { break }

            var location = blockRange.location + lineStarts[lineIndex]
            for token in line {
                let length = (token.text as NSString).length
                guard length > 0 else { continue }
                guard location + length <= totalLength, location + length <= blockEnd else { break }
                textStorage.addAttribute(
                    .foregroundColor,
                    value: highlightColor(fromHex: token.colorHex),
                    range: NSRange(location: location, length: length)
                )
                location += length
            }
        }
        textStorage.endEditing()
    }

    private func highlightColor(fromHex hex: String) -> NSColor {
        var sanitized = hex
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return DarkModernTheme.foreground
        }

        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
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
                self.gutterView.needsDisplay = true
            }
        }
    }

    private func scrollToLine(_ line: Int) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let location = characterOffset(forLine: line, in: text)
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
        gutterView.needsDisplay = true
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
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.setSelectedRange(lineRange)
        textView.scrollRangeToVisible(lineRange)
        gutterView.needsDisplay = true
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
        jsonOutlineView.isHidden = true
        jsonOutlineView.reset()
        modeControl.isEnabled = false
        jsonViewToggle.isHidden = true
        foldButton.isEnabled = false
        foldButton.state = .off
        revealButton.isEnabled = false
        copyButton.isEnabled = false
        metaLabel.stringValue = ""
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        applyDisplayMetadata(.plain)
        applyEditorTheme(usesDarkModern: false)
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        clearMarkdownOutline()
    }

    private func showPreviewState() {
        updateSidebarVisibility()
        emptyView.isHidden = true
    }

    private func applyLineWrapping() {
        if wrapsLines {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            // maxSize 必须无限大：NSTextView 布局驱动的增长走
            // setConstrainedFrameSize，被钳在 maxSize 内；默认 maxSize 是
            // 初始 frame（视口大小），长文档 frame 长不过视口高度，
            // scrollView 便没有可滚动区域（issue #3）。
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
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
        gutterView.needsDisplay = true
    }

    /// 主线程分片推进 TextKit1 布局。macOS 26 上惰性布局不自行推进，
    /// 无人推进时长文档的 textView frame 停在视口高度，scrollView 没有
    /// 可滚动区域（issue #3）。每拍布局一小段后经 main.async 让出 runloop，
    /// 文档 frame 随之渐进长高，滚动条渐进变准，交互始终响应。
    private func startLayoutPump() {
        layoutPumpGeneration += 1
        pumpLayout(generation: layoutPumpGeneration)
    }

    private func pumpLayout(generation: Int) {
        guard
            generation == layoutPumpGeneration,
            let layoutManager = textView.layoutManager,
            let textStorage = textView.textStorage
        else {
            return
        }

        let length = textStorage.length
        let firstUnlaid = layoutManager.firstUnlaidCharacterIndex()
        guard firstUnlaid < length else {
            gutterView.needsDisplay = true
            return
        }

        let chunkLength = min(64_000, length - firstUnlaid)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: firstUnlaid, length: chunkLength))
        DispatchQueue.main.async { [weak self] in
            self?.pumpLayout(generation: generation)
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

    @objc private func jsonViewModeChanged(_ sender: NSSegmentedControl) {
        guard let index = activeTabIndex else { return }
        tabs[index].jsonTreeVisible = sender.selectedSegment == 0
        renderActiveTab()
    }

    @objc private func toggleWrap(_ sender: Any?) {
        wrapsLines.toggle()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
    }

    @objc private func toggleFileTreeCollapsed(_ sender: Any?) {
        isFileTreeCollapsed.toggle()
        fileTreeView.isHidden = isFileTreeCollapsed
        fileTreeDisclosureButton.image = NSImage(
            systemSymbolName: isFileTreeCollapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: "Toggle file tree"
        )
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let url = activeTab?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Copy menu (工具栏下拉 + Edit 主菜单共用的六项操作)

    private func configureCopyMenu() {
        copyMenu.delegate = self

        let copyAllItem = NSMenuItem(title: "Copy All", action: #selector(copyAllMenuAction(_:)), keyEquivalent: "c")
        copyAllItem.keyEquivalentModifierMask = [.command, .option]
        copyAllItem.target = self
        copyMenu.addItem(copyAllItem)

        let copyAbsoluteItem = NSMenuItem(
            title: "Copy Absolute Path",
            action: #selector(copyAbsolutePathMenuAction(_:)),
            keyEquivalent: "c"
        )
        copyAbsoluteItem.keyEquivalentModifierMask = [.command, .shift]
        copyAbsoluteItem.target = self
        copyMenu.addItem(copyAbsoluteItem)

        let copyRelativeItem = NSMenuItem(
            title: "Copy Relative Path",
            action: #selector(copyRelativePathMenuAction(_:)),
            keyEquivalent: "c"
        )
        copyRelativeItem.keyEquivalentModifierMask = [.command, .shift, .option]
        copyRelativeItem.target = self
        copyMenu.addItem(copyRelativeItem)
        copyRelativePathMenuItem = copyRelativeItem

        copyMenu.addItem(.separator())

        let copyFileItem = NSMenuItem(title: "Copy File", action: #selector(copyFileMenuAction(_:)), keyEquivalent: "")
        copyFileItem.target = self
        copyMenu.addItem(copyFileItem)

        let copyPathLineItem = NSMenuItem(
            title: "Copy Path:Line",
            action: #selector(copyPathLineMenuAction(_:)),
            keyEquivalent: ""
        )
        copyPathLineItem.target = self
        copyMenu.addItem(copyPathLineItem)

        copyMenu.addItem(.separator())

        let openInEditorItem = NSMenuItem(
            title: "Open in Editor",
            action: #selector(openInEditorMenuAction(_:)),
            keyEquivalent: "e"
        )
        openInEditorItem.keyEquivalentModifierMask = [.command]
        openInEditorItem.target = self
        copyMenu.addItem(openInEditorItem)
    }

    /// 弹出前隐藏「复制相对路径」——无 repo root 时该项不出现。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === copyMenu else { return }
        copyRelativePathMenuItem?.isHidden = !hasRepoRootForActiveFile
    }

    private var hasRepoRootForActiveFile: Bool {
        guard let url = activeTab?.url else { return false }
        return RepoRoot.discover(from: url) != nil
    }

    @objc private func showCopyMenu(_ sender: Any?) {
        copyMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: copyButton.bounds.height + 4), in: copyButton)
    }

    @objc private func copyAllMenuAction(_ sender: Any?) {
        copyAllText()
    }

    @objc private func copyAbsolutePathMenuAction(_ sender: Any?) {
        copyAbsolutePath()
    }

    @objc private func copyRelativePathMenuAction(_ sender: Any?) {
        copyRelativePath()
    }

    @objc private func copyFileMenuAction(_ sender: Any?) {
        copyFileReference()
    }

    @objc private func copyPathLineMenuAction(_ sender: Any?) {
        copyPathLineReference()
    }

    @objc private func openInEditorMenuAction(_ sender: Any?) {
        openInEditor()
    }

    /// ① 复制全文：TextFileLoader 的原始文本，不是渲染后 attributed 文本。
    func copyAllText() {
        guard let document = activeTab?.document else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.text, forType: .string)
    }

    /// ② 复制绝对路径。
    func copyAbsolutePath() {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// ③ 复制相对 repo root 路径；无 repo 时静默不作为（菜单项本身已隐藏/禁用）。
    func copyRelativePath() {
        guard let url = activeTab?.url, let root = RepoRoot.discover(from: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(relativePath(of: url, root: root), forType: .string)
    }

    /// ④ 复制文件本体：Finder ⌘V 可粘贴出文件。
    func copyFileReference() {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    /// ⑤ 复制 path:line：行号取当前选中文本首行，无选中时取可视区首个逻辑行。
    func copyPathLineReference() {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(url.path):\(currentReferenceLine())", forType: .string)
    }

    /// ⑥ ⌘E 用编辑器打开：默认 app 是 VS Code/Cursor 时经其 URL scheme 带 path:line 定位。
    func openInEditor() {
        guard let url = activeTab?.url else { return }
        openFileInEditor(url: url, line: currentReferenceLine())
    }

    private func relativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents

        guard
            urlComponents.count > rootComponents.count,
            Array(urlComponents.prefix(rootComponents.count)) == rootComponents
        else {
            return url.standardizedFileURL.path
        }

        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func currentReferenceLine() -> Int {
        let selectedRange = textView.selectedRange()
        let anchorLocation = selectedRange.length > 0 ? selectedRange.location : visibleFirstCharacterLocation()
        return logicalLineNumber(atCharacterLocation: anchorLocation)
    }

    private func visibleFirstCharacterLocation() -> Int {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return textView.selectedRange().location
        }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: textView.visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else {
            return textView.selectedRange().location
        }

        let charRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        return charRange.location
    }

    /// 当前 textView 内容（无论 raw/formatted）中，某字符位置对应的 1-based 逻辑行号；
    /// 与 gutter 当前展示的编号规则一致（普通行号表 / JSONL 记录原始行 marker）。
    private func logicalLineNumber(atCharacterLocation location: Int) -> Int {
        switch gutterView.configuration.mode {
        case .hidden:
            return rawLineNumber(atCharacterLocation: location)
        case .lineNumbers(let starts):
            return lineStartIndex(for: location, in: starts) + 1
        case .markers(let markers):
            let sorted = markers.sorted { $0.characterLocation < $1.characterLocation }
            var matchedLabel: String?
            for marker in sorted where marker.characterLocation <= location {
                matchedLabel = marker.label
            }
            if let matchedLabel, let value = Int(matchedLabel) {
                return value
            }
            return rawLineNumber(atCharacterLocation: location)
        }
    }

    private func lineStartIndex(for location: Int, in starts: [Int]) -> Int {
        guard !starts.isEmpty else { return 0 }

        var low = 0
        var high = starts.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= location {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return match
    }

    private func rawLineNumber(atCharacterLocation location: Int) -> Int {
        let text = textView.string as NSString
        guard text.length > 0 else { return 1 }

        let safeLocation = min(max(location, 0), text.length)
        var line = 1
        var index = 0

        while index < safeLocation {
            let searchRange = NSRange(location: index, length: safeLocation - index)
            let newlineRange = text.range(of: "\n", options: [], range: searchRange)
            guard newlineRange.location != NSNotFound else { break }
            line += 1
            index = newlineRange.location + newlineRange.length
        }

        return line
    }

    private func openFileInEditor(url: URL, line: Int) {
        guard let editorURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            NSWorkspace.shared.open(url)
            return
        }

        let bundleID = Bundle(url: editorURL)?.bundleIdentifier
        let scheme: String?
        switch bundleID {
        case "com.microsoft.VSCode":
            scheme = "vscode"
        case "com.todesktop.230313mzl4w4u92":
            scheme = "cursor"
        default:
            scheme = nil
        }

        if
            let scheme,
            let encodedPath = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let deepLinkURL = URL(string: "\(scheme)://file/\(encodedPath):\(line)")
        {
            NSWorkspace.shared.open(deepLinkURL)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
