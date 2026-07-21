import AppKit
import Foundation
import WebKit

private struct PreviewTab {
    let id: UUID
    let url: URL
    var document: LoadedText?
    var errorMessage: String?
    var mode: PreviewMode
    var targetLine: Int?
    var targetColumn: Int?

    init(url: URL, document: LoadedText?, errorMessage: String?) {
        self.id = UUID()
        self.url = url
        self.document = document
        self.errorMessage = errorMessage
        self.mode = .formatted
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

final class PreviewWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate, WKNavigationDelegate {
    var onOpenRequested: (() -> Void)?
    var onURLsDropped: (([URL]) -> Void)?
    var onClose: (() -> Void)?

    private let rootView = DropContainerView()
    private let sidebarView = DropSidebarView()
    private let sidebarSectionControl = NSSegmentedControl(labels: ["Open", "Files", "Contents"], trackingMode: .selectOne, target: nil, action: nil)
    private let sidebarScrollView = DropScrollView()
    private let tabListDocumentView = DropContainerView()
    private let sidebarStack = NSStackView()
    private let fileTreeView = FileTreeView()
    private let tabStack = NSStackView()
    private let outlineScrollView = NSScrollView()
    private let outlineStack = FlippedStackView()
    private let contentView = DropContainerView()
    private let headerView = DropHeaderView()
    private let headerDivider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()
    private let titleLabel = NSTextField(labelWithString: "Peeky")
    private let metaLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: ["Format", "Raw"], trackingMode: .selectOne, target: nil, action: nil)
    private let wrapButton = NSButton()
    private let copyButton = NSButton()
    private let revealButton = NSButton()
    private let openButton = NSButton()
    private let copyMenu = NSMenu()
    private var copyRelativePathMenuItem: NSMenuItem?
    private let scrollView = DropScrollView()
    private let gutterView = PreviewGutterView()
    private let textView = DropTextView()
    private let emptyView = NSStackView()
    /// markdown 专用渲染面：WKWebView + 真 github-markdown-css（像素级对齐 github）。
    /// 与编辑器 scrollView 同区叠放，仅 markdown 显示。属性初始化即创建，
    /// 让 WebContent 进程尽早预热，首次打开 markdown 近乎即时。
    private let markdownWebView = WKWebView()
    /// github-markdown.css 内容，首次访问时从资源包加载一次并缓存。
    private lazy var githubMarkdownCSS = MarkdownHTMLRenderer.loadGithubMarkdownCSS()
    /// 当前是否处于 markdown WebView 呈现态（决定大纲点击走 JS 滚动还是原生滚动）。
    private var isMarkdownWebActive = false
    /// 当前 markdown 的标题大纲（供 WebView 载入完成后按行定位到最近标题）。
    private var currentMarkdownOutline: [MarkdownOutlineItem] = []
    /// WebView 载入完成后要滚到的源行（peeky:// / 初始定位），载入完成即消费清空。
    private var pendingMarkdownScrollLine: Int?

    private var tabs: [PreviewTab] = []
    private var activeTabID: UUID?
    private var wrapsLines = true
    /// 最近一次渲染的编辑器区是否跟随系统明暗（JSON/JSONL）；系统外观切换时据此
    /// 决定是否即时重刷编辑器背景与全文基础前景。
    private var activeRenderFollowsSystemAppearance = false
    /// 当前渲染为 JSON/JSONL（usesJSONHighlighting）时缓存的完整文本；可见区惰性分色
    /// 以此为行对齐子串分词与坏行相交的坐标基准。非 JSON 渲染为 nil，可见区上色据此跳过。
    private var activeJSONText: String?
    /// 当前 JSON/JSONL 渲染的坏行在输出文本中的 UTF-16 区间（JSONL 坏行才非空）；
    /// 与可见范围相交者覆盖红前景 + 红背景。
    private var activeInvalidRanges: [NSRange] = []
    /// scrollView.contentView 滚动（boundsDidChange）观察 token；触发可见区惰性上色。
    /// deinit 在 Swift 6 严格并发下总是 nonisolated，无法访问主 actor 隔离的存储属性；
    /// 此清理只是摘掉注册在 NotificationCenter 的 token，无跨线程数据竞争，
    /// nonisolated(unsafe) 据实况解除隔离检查。
    private nonisolated(unsafe) var jsonHighlightScrollObserver: NSObjectProtocol?
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
    /// 当前文件树的根目录；nil 表示尚未打开过任何文件/目录，树区未建立。
    private var treeRootURL: URL?

    /// 侧栏三 tab（Open / Files / Contents），rawValue 即 segment 下标。
    private enum SidebarSection: Int {
        case open = 0
        case files = 1
        case contents = 2

        static let defaultsKey = "PeekySidebarSection"

        static func loadPreferred() -> SidebarSection {
            SidebarSection(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .open
        }

        func savePreferred() {
            UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    /// 用户最后一次主动点选的侧栏 tab（全局持久化）。当前文件让 CONTENTS 不可用时
    /// 显示层临时回落 FILES，偏好本身保持不变，切回 markdown 自动恢复。
    private var preferredSidebarSection = SidebarSection.loadPreferred()
    /// 当前文档是否有可展示的 markdown 大纲（决定 CONTENTS tab 可用性）。
    private var isOutlineAvailable = false

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
                    let existingKind = tabs[existingIndex].document?.kind
                    if existingKind != .json && existingKind != .jsonl {
                        tabs[existingIndex].mode = .raw
                    }
                    tabs[existingIndex].targetLine = request.line
                    tabs[existingIndex].targetColumn = request.column
                }
                establishTreeRoot(for: standardizedURL)
                continue
            }

            var tab = loadTab(url: standardizedURL)
            if request.line != nil {
                if tab.document?.kind != .json && tab.document?.kind != .jsonl {
                    tab.mode = .raw
                }
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
        setupMarkdownWebView()
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

            headerDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerDivider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            markdownWebView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            markdownWebView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            markdownWebView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            markdownWebView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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

        // 顶部常驻分段控件：三区互斥切换（issue #11），一次只显示一个区块。
        sidebarSectionControl.translatesAutoresizingMaskIntoConstraints = false
        sidebarSectionControl.controlSize = .small
        sidebarSectionControl.segmentDistribution = .fillEqually
        sidebarSectionControl.target = self
        sidebarSectionControl.action = #selector(sidebarSectionChanged(_:))
        sidebarView.addSubview(sidebarSectionControl)

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

        // OPEN / FILES 装进外层滚动区（树自撑高度，靠 sidebarScrollView 滚动）；
        // CONTENTS 独立成占满全高的滚动区，与 sidebarScrollView 互斥显示。
        setupTabSection()
        sidebarStack.addArrangedSubview(tabStack)

        setupFileTreeSection()
        sidebarStack.addArrangedSubview(fileTreeView)

        setupOutlineSection()
        sidebarView.addSubview(outlineScrollView)

        sidebarScrollView.documentView = tabListDocumentView

        NSLayoutConstraint.activate([
            sidebarSectionControl.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 10),
            sidebarSectionControl.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 8),
            sidebarSectionControl.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -8),

            sidebarScrollView.topAnchor.constraint(equalTo: sidebarSectionControl.bottomAnchor, constant: 8),
            sidebarScrollView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -8),

            outlineScrollView.topAnchor.constraint(equalTo: sidebarSectionControl.bottomAnchor, constant: 8),
            outlineScrollView.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 8),
            outlineScrollView.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -8),
            outlineScrollView.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -8),

            tabListDocumentView.topAnchor.constraint(equalTo: sidebarScrollView.contentView.topAnchor),
            tabListDocumentView.leadingAnchor.constraint(equalTo: sidebarScrollView.contentView.leadingAnchor),
            tabListDocumentView.widthAnchor.constraint(equalTo: sidebarScrollView.contentView.widthAnchor),
            tabListDocumentView.heightAnchor.constraint(greaterThanOrEqualTo: sidebarScrollView.contentView.heightAnchor),

            sidebarStack.topAnchor.constraint(equalTo: tabListDocumentView.topAnchor, constant: 2),
            sidebarStack.leadingAnchor.constraint(equalTo: tabListDocumentView.leadingAnchor, constant: 8),
            sidebarStack.trailingAnchor.constraint(equalTo: tabListDocumentView.trailingAnchor, constant: -8),
            sidebarStack.bottomAnchor.constraint(lessThanOrEqualTo: tabListDocumentView.bottomAnchor, constant: -2),

            tabStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),
            fileTreeView.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor)
        ])

        updateSidebarSections()
    }

    /// 「Open」tab 列表：既有卡片样式不变，选中 Open tab 时显示。
    private func setupTabSection() {
        tabStack.orientation = .vertical
        tabStack.alignment = .width
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 「Files」文件树：FileTreeView 自撑高度，靠外层 sidebarScrollView 滚动。
    private func setupFileTreeSection() {
        fileTreeView.translatesAutoresizingMaskIntoConstraints = false
        fileTreeView.onFileClick = { [weak self] url in
            self?.open(url: url)
        }
    }

    /// 「Contents」大纲：独立滚动区占满分段控件以下的侧栏全高，内容超高时内部滚动。
    private func setupOutlineSection() {
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

        // documentView 只钉 top/leading/trailing，高度由条目内容自撑，超出在 clip 内滚动。
        NSLayoutConstraint.activate([
            outlineStack.topAnchor.constraint(equalTo: outlineScrollView.contentView.topAnchor),
            outlineStack.leadingAnchor.constraint(equalTo: outlineScrollView.contentView.leadingAnchor),
            outlineStack.trailingAnchor.constraint(equalTo: outlineScrollView.contentView.trailingAnchor)
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
        contentView.addSubview(headerDivider)

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

        configureIconButton(wrapButton, symbol: "text.alignleft", tooltip: "Toggle line wrap", action: #selector(toggleWrap(_:)))
        configureIconButton(copyButton, symbol: "doc.on.doc", tooltip: "Copy", action: #selector(showCopyMenu(_:)))
        configureIconButton(revealButton, symbol: "magnifyingglass", tooltip: "Reveal in Finder", action: #selector(revealInFinder(_:)))
        configureIconButton(openButton, symbol: "folder", tooltip: "Open", action: #selector(openClicked(_:)))
        configureCopyMenu()

        let controls = NSStackView(views: [modeControl, wrapButton, copyButton, revealButton, openButton])
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
        // 标准选中高亮（跟随系统强调色），保证用户鼠标选中可见、⌘C 可复制。
        textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        textView.textContainerInset = NSSize(width: 4, height: 8)
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
        textView.onEffectiveAppearanceChanged = { [weak self] in
            self?.reapplyFollowSystemColorsIfNeeded()
        }

        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = gutterView
        gutterView.connect(textView: textView, scrollView: scrollView)

        // 滚动即重算可见区语义分色：观察 clip view 的 bounds 变更。
        // setTemporaryAttributes 不改 bounds，故此回调不成循环。
        scrollView.contentView.postsBoundsChangedNotifications = true
        jsonHighlightScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            // addObserver(queue: .main) 的 block 形参是 @Sendable，编译器无法静态验证
            // OperationQueue.main 与 MainActor 隔离域一致；queue: .main 已保证运行时必在
            // 主线程，assumeIsolated 据实况断言而非新开 Task 调度。
            MainActor.assumeIsolated {
                self?.applyVisibleJSONHighlighting()
            }
        }
    }

    deinit {
        if let jsonHighlightScrollObserver {
            NotificationCenter.default.removeObserver(jsonHighlightScrollObserver)
        }
    }

    /// markdown 专用 WebView：与编辑器 scrollView 同区叠放，仅 markdown 显示。
    /// 不覆盖 appearance，让 github-markdown-css 的 prefers-color-scheme 随系统自动切浅深。
    private func setupMarkdownWebView() {
        markdownWebView.translatesAutoresizingMaskIntoConstraints = false
        markdownWebView.isHidden = true
        markdownWebView.navigationDelegate = self
        contentView.addSubview(markdownWebView)
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

        for (index, item) in outline.enumerated() {
            let itemView = MarkdownOutlineItemView(item: item)
            itemView.onSelect = { [weak self] in
                guard let self else { return }
                // WebView 呈现态走 JS 滚到对应 heading-N；原生（>8MB raw 兜底）走源行滚动。
                if self.isMarkdownWebActive {
                    self.markdownWebView.evaluateJavaScript("scrollToHeading(\(index))")
                } else {
                    self.scrollToOutlineItem(item)
                }
            }
            outlineStack.addArrangedSubview(itemView)
            itemView.widthAnchor.constraint(equalTo: outlineStack.widthAnchor).isActive = true
        }

        isOutlineAvailable = true
        updateSidebarSections()
    }

    private func clearMarkdownOutline() {
        for view in outlineStack.arrangedSubviews {
            outlineStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        isOutlineAvailable = false
        updateSidebarSections()
    }

    private func updateSidebarVisibility() {
        let hasContent = !tabs.isEmpty || treeRootURL != nil
        sidebarView.isHidden = !hasContent
        sidebarWidthConstraint?.constant = hasContent ? 240 : 0
        rootView.needsLayout = true
        updateSidebarSections()
    }

    /// 按「偏好 + 可用性」推导当前生效 tab 并落到视图：一次只显示一个区块。
    /// 偏好 CONTENTS 但当前文档无大纲时临时回落 FILES（偏好保持，供下个 markdown 恢复）。
    private func updateSidebarSections() {
        let effective: SidebarSection = (preferredSidebarSection == .contents && !isOutlineAvailable)
            ? .files
            : preferredSidebarSection

        sidebarSectionControl.selectedSegment = effective.rawValue
        sidebarSectionControl.setEnabled(isOutlineAvailable, forSegment: SidebarSection.contents.rawValue)

        tabStack.isHidden = effective != .open
        fileTreeView.isHidden = effective != .files
        sidebarScrollView.isHidden = effective == .contents
        outlineScrollView.isHidden = effective != .contents
    }

    @objc private func sidebarSectionChanged(_ sender: NSSegmentedControl) {
        guard let section = SidebarSection(rawValue: sender.selectedSegment) else { return }
        preferredSidebarSection = section
        section.savePreferred()
        updateSidebarSections()
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
        // 文件树跟随新激活 tab：仍在当前根内只定位选中，在根外重算树根。
        if let url = activeTab?.url {
            establishTreeRoot(for: url)
        }
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
        if let url = activeTab?.url {
            establishTreeRoot(for: url)
        }
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
        targetLine: Int?,
        tabID: UUID
    ) {
        // markdown（≤8MB）走 WebView + 真 github-markdown-css；>8MB 落下方原生 raw 兜底。
        if document.kind == .markdown && document.readBytes <= 8 * 1024 * 1024 {
            renderMarkdownWeb(document: document, targetLine: targetLine)
            return
        }

        // JSON/JSONL 是唯一渲染形态（pretty-print 分色），不提供 Format/Raw 切换。
        let isJSONFamily = document.kind == .json || document.kind == .jsonl
        modeControl.isHidden = isJSONFamily
        modeControl.selectedSegment = mode.rawValue
        modeControl.isEnabled = document.kind.hasFormattedPreview
        modeControl.setLabel("Format", forSegment: 0)

        let rendered = PreviewRenderer.render(
            document: document,
            mode: mode
        )
        textView.textStorage?.setAttributedString(rendered.attributedText)
        applyDisplayMetadata(rendered.display)
        if rendered.usesJSONHighlighting {
            activeJSONText = rendered.attributedText.string
            activeInvalidRanges = rendered.display.invalidRecordRanges
        } else {
            activeJSONText = nil
            activeInvalidRanges = []
        }
        applyEditorTheme(
            followsSystemAppearance: rendered.followsSystemAppearance,
            usesDarkModern: rendered.usesDarkModernTheme
        )
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

        showPlainText()
        applyVisibleJSONHighlighting()
    }

    private func renderError(message: String, url: URL) {
        titleLabel.stringValue = url.lastPathComponent
        metaLabel.stringValue = "Open failed"
        modeControl.isEnabled = false
        revealButton.isEnabled = true
        copyButton.isEnabled = true

        textView.textStorage?.setAttributedString(SyntaxHighlighter.monospace(message))
        applyDisplayMetadata(.plain)
        applyEditorTheme(followsSystemAppearance: false, usesDarkModern: false)
        clearMarkdownOutline()
        showPreviewState()
        showPlainText()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
    }

    /// 恒单 textView 视图：显示编辑器 scrollView（含 textView + 行号 gutter）。
    private func showPlainText() {
        markdownWebView.isHidden = true
        isMarkdownWebActive = false
        scrollView.isHidden = false
    }

    /// markdown WebView 呈现态：只显 WebView，隐编辑器 scrollView。
    private func showMarkdownWeb() {
        scrollView.isHidden = true
        markdownWebView.isHidden = false
    }

    /// markdown（≤8MB）→ WKWebView + 真 github-markdown-css 呈现。构建 HTML、载入、
    /// 重建大纲、填元信息；选中+复制由 WebView 原生自带。
    private func renderMarkdownWeb(document: LoadedText, targetLine: Int?) {
        isMarkdownWebActive = true
        modeControl.isHidden = true

        let rendered = MarkdownHTMLRenderer.renderWithOutline(document.text)
        currentMarkdownOutline = rendered.outline
        pendingMarkdownScrollLine = targetLine
        let html = MarkdownHTMLRenderer.documentHTML(bodyHTML: rendered.html, css: githubMarkdownCSS)
        markdownWebView.loadHTMLString(html, baseURL: nil)

        rebuildMarkdownOutline(rendered.outline)

        var summary = [
            document.kind.displayName,
            ByteCountFormatter.string(fromByteCount: document.totalBytes, countStyle: .file),
            document.encodingName
        ].joined(separator: "  |  ")
        if document.isTruncated {
            summary += "  |  Previewing first \(ByteCountFormatter.string(fromByteCount: Int64(document.readBytes), countStyle: .file))"
        }
        if let targetLine {
            summary += "  |  Line \(targetLine)"
        }
        metaLabel.stringValue = summary
        revealButton.isEnabled = true
        copyButton.isEnabled = true

        showPreviewState()
        showMarkdownWeb()
    }

    /// WebView 载入完成：若有待定源行，滚到 sourceLine 不超过它的最后一个标题（就近定位）。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === markdownWebView, let line = pendingMarkdownScrollLine else { return }
        pendingMarkdownScrollLine = nil

        var targetIndex: Int?
        for (index, item) in currentMarkdownOutline.enumerated() {
            if item.sourceLine <= line {
                targetIndex = index
            } else {
                break
            }
        }
        if let targetIndex {
            webView.evaluateJavaScript("scrollToHeading(\(targetIndex))")
        }
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

    /// 正文填满窗口：markdown-formatted 用略宽于默认的对称内边距（32pt），其余模式
    /// 用默认 18pt。textView 走 widthTracksTextView=true + autoresizingMask [.width]，
    /// 实际排版宽 = frame 宽 − 2×inset，正文随窗口变宽自动变宽；内边距为常量、不依赖
    /// 当前宽度，故初始打开与拖拽 resize 都无需按宽度重算。字符定位（scrollToLine/
    /// scrollToOutlineItem 等）全程只用 NSRange 偏移、不含 x 坐标假设，不受内边距影响。
    private func applyMarkdownReadingColumn(isActive: Bool) {
        let margin: CGFloat = isActive ? 32 : 18
        textView.textContainerInset = NSSize(width: margin, height: 16)
    }

    // MARK: - 高亮接入（R4e）：Dark Modern 主题 + 分块原位上色

    /// 编辑器区（scrollView + textView + gutterView）主题三分流：
    /// - followsSystemAppearance（JSON/JSONL）：appearance = nil 跟随系统，背景/全文
    ///   基础前景经 `PeekyTheme` 按当前 effectiveAppearance 解析成单色主题色。
    /// - usesDarkModern（源码高亮）：钉死 darkAqua + `DarkModernTheme.background`。
    /// - 皆否（markdown/xml/plist/yaml/text）：appearance = nil + `.textBackgroundColor`。
    private func applyEditorTheme(followsSystemAppearance: Bool, usesDarkModern: Bool) {
        activeRenderFollowsSystemAppearance = followsSystemAppearance

        if followsSystemAppearance {
            scrollView.appearance = nil
            textView.appearance = nil
            gutterView.appearance = nil
            applyFollowSystemEditorColors()
        } else if usesDarkModern {
            let appearance = NSAppearance(named: .darkAqua)
            scrollView.appearance = appearance
            textView.appearance = appearance
            gutterView.appearance = appearance
            textView.backgroundColor = DarkModernTheme.background
        } else {
            scrollView.appearance = nil
            textView.appearance = nil
            gutterView.appearance = nil
            textView.backgroundColor = .textBackgroundColor
        }
    }

    /// JSON/JSONL 跟随系统外观：按 textView 当前 effectiveAppearance 解析出 light/dark，
    /// 施加编辑器背景色并把全文基础前景铺成单色主题前景（逐 token 分色由后续单元做）。
    private func applyFollowSystemEditorColors() {
        let appearance = PeekyTheme.resolveAppearance(textView.effectiveAppearance)
        textView.backgroundColor = PeekyTheme.color(.editorBackground, appearance: appearance)
        if let textStorage = textView.textStorage, textStorage.length > 0 {
            textStorage.addAttribute(
                .foregroundColor,
                value: PeekyTheme.color(.editorForeground, appearance: appearance),
                range: NSRange(location: 0, length: textStorage.length)
            )
        }
    }

    /// 系统明暗切换即时跟随：仅当最近一次渲染跟随系统外观（JSON/JSONL）时，重刷编辑器
    /// 背景 + 全文基础前景，并触发 gutter 重绘。
    func reapplyFollowSystemColorsIfNeeded() {
        guard activeRenderFollowsSystemAppearance else { return }
        applyFollowSystemEditorColors()
        gutterView.needsDisplay = true
        applyVisibleJSONHighlighting()
    }

    /// JSON/JSONL 惰性语义分色：仅对屏幕可见区上色，绝不整文分词。求出可见字符范围后
    /// 逐可见行遍历（从可视区首行起，到可视区末尾加 8192 buffer 为止），单行长度超过
    /// maxLineLength(65536 UTF-16) 的巨大单行值跳过分词、保留单色基础前景，避免超长单行
    /// tokenize 退化成近全文级卡主线程。逐行对齐保证 key/value 冒号判定在行内完整、词法
    /// 正确，只对每行子串调 `JSONHighlighter.tokenize`，token range 加该行起点偏移平移回全文
    /// 坐标，用 setTemporaryAttributes 施加语义前景色。坏行与可视行范围相交部分覆盖红前景
    /// （setTemporaryAttributes，后施加故优先于 token 色）+ 红背景（textStorage.addAttribute，
    /// 坏行数量少可接受）。setTemporaryAttributes 不改 bounds，故 boundsDidChange / pumpLayout
    /// 触发不成循环。非 JSON 渲染（activeJSONText == nil）直接跳过。
    private func applyVisibleJSONHighlighting() {
        guard let fullText = activeJSONText else { return }
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let nsText = fullText as NSString
        guard nsText.length > 0 else { return }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: textView.visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let clampedLocation = min(max(visibleCharRange.location, 0), nsText.length)
        let clampedLength = min(visibleCharRange.length, nsText.length - clampedLocation)
        let clampedRange = NSRange(location: clampedLocation, length: clampedLength)

        let maxLineLength = 65536
        let visibleEndCap = min(NSMaxRange(clampedRange) + 8192, nsText.length)
        let firstVisibleLineStart = nsText.lineRange(
            for: NSRange(location: clampedRange.location, length: 0)
        ).location

        let appearance = PeekyTheme.resolveAppearance(textView.effectiveAppearance)

        var lineStart = firstVisibleLineStart
        while lineStart < visibleEndCap {
            let line = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            guard line.length > 0 else { break }

            if line.length <= maxLineLength {
                let offset = line.location
                for token in JSONHighlighter.tokenize(nsText.substring(with: line)) {
                    let themeColor: PeekyTheme.ThemeColor
                    switch token.kind {
                    case .key: themeColor = .jsonKey
                    case .string: themeColor = .jsonString
                    case .number: themeColor = .jsonNumber
                    case .boolLiteral: themeColor = .jsonBool
                    case .nullLiteral: themeColor = .jsonNull
                    case .punctuation: themeColor = .jsonPunctuation
                    }
                    let globalRange = NSRange(location: token.range.location + offset, length: token.range.length)
                    layoutManager.setTemporaryAttributes(
                        [.foregroundColor: PeekyTheme.color(themeColor, appearance: appearance)],
                        forCharacterRange: globalRange
                    )
                }
            }

            lineStart = NSMaxRange(line)
        }

        guard !activeInvalidRanges.isEmpty else { return }
        let visibleLineRange = NSRange(
            location: firstVisibleLineStart,
            length: visibleEndCap - firstVisibleLineStart
        )
        let invalidForeground = PeekyTheme.color(.invalidLineForeground, appearance: appearance)
        let invalidBackground = PeekyTheme.color(.invalidLineBackground, appearance: appearance)
        for invalidRange in activeInvalidRanges {
            let intersection = NSIntersectionRange(invalidRange, visibleLineRange)
            guard intersection.length > 0, intersection.location + intersection.length <= nsText.length else { continue }
            layoutManager.setTemporaryAttributes(
                [.foregroundColor: invalidForeground],
                forCharacterRange: intersection
            )
            textView.textStorage?.addAttribute(
                .backgroundColor,
                value: invalidBackground,
                range: intersection
            )
        }
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
                self.textView.scrollRangeToVisible(topRange)
                self.textView.showFindIndicator(for: topRange)
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
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: lineRange)
        gutterView.needsDisplay = true
    }

    private func scrollToOutlineItem(_ item: MarkdownOutlineItem) {
        if activeTab?.mode == .formatted, let renderedLocation = item.renderedLocation {
            scrollToTopAligned(characterLocation: renderedLocation)
        } else {
            let text = textView.string as NSString
            guard text.length > 0 else { return }
            let location = characterOffset(forLine: item.sourceLine, in: text)
            scrollToTopAligned(characterLocation: location)
        }
    }

    /// 大纲点击专用置顶滚动：把目标字符位置所在逻辑行的首行滚到可视区顶部
    /// （减去一个小固定偏移）。与 scrollToLine/scrollToCharacterLocation
    /// （scheduleInitialScroll 的 path:line CLI 初始滚动等路径使用）完全独立——
    /// 那些路径继续用 scrollRangeToVisible 的"最小可见"语义，不受此函数影响。
    private func scrollToTopAligned(characterLocation location: Int) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let safeLocation = min(max(location, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))

        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            textView.scrollRangeToVisible(lineRange)
            textView.showFindIndicator(for: lineRange)
            gutterView.needsDisplay = true
            return
        }

        layoutManager.ensureLayout(forCharacterRange: lineRange)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        let topInset: CGFloat = 6
        let targetY = lineRect.minY + textView.textContainerOrigin.y - topInset

        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.frame.height ?? textView.frame.height
        let maxScrollableY = max(0, documentHeight - clipView.bounds.height)
        let clampedY = min(max(targetY, 0), maxScrollableY)

        clipView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)

        textView.showFindIndicator(for: lineRange)
        gutterView.needsDisplay = true
    }

    private func scrollToCharacterLocation(_ location: Int) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let safeLocation = min(max(location, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: lineRange)
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
        markdownWebView.isHidden = true
        isMarkdownWebActive = false
        modeControl.isEnabled = false
        revealButton.isEnabled = false
        copyButton.isEnabled = false
        metaLabel.stringValue = ""
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        applyDisplayMetadata(.plain)
        applyEditorTheme(followsSystemAppearance: false, usesDarkModern: false)
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
            applyVisibleJSONHighlighting()
            return
        }

        let chunkLength = min(64_000, length - firstUnlaid)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: firstUnlaid, length: chunkLength))
        applyVisibleJSONHighlighting()
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

    @objc private func toggleWrap(_ sender: Any?) {
        wrapsLines.toggle()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
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

        // 无 keyEquivalent：纯 ⌘C 留给 NSTextView 原生 copy:（复制选区），
        // 此菜单项只作为可发现入口，行为与原生 ⌘C 一致（含空选区回落全文）。
        let copySelectionItem = NSMenuItem(
            title: "Copy Selection",
            action: #selector(copySelectionMenuAction(_:)),
            keyEquivalent: ""
        )
        copySelectionItem.target = self
        copyMenu.addItem(copySelectionItem)

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

    @objc private func copySelectionMenuAction(_ sender: Any?) {
        copySelection()
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

    /// 复制选中：选区非空复制选区文本，选区为空回落复制全文（copyAllText 同源语义）。
    func copySelection() {
        guard let document = activeTab?.document else { return }
        let selectedRange = textView.selectedRange()
        let selectedText = selectedRange.length > 0 ? (textView.string as NSString).substring(with: selectedRange) : ""
        let payload = Self.selectionCopyPayload(selected: selectedText, full: document.text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    /// 选区非空取选区，选区为空回落全文；纯函数、无 MainActor 状态，标 nonisolated
    /// 便于任意上下文（含测试）同步调用，不依赖 NSTextView/NSPasteboard。
    nonisolated static func selectionCopyPayload(selected: String, full: String) -> String {
        selected.isEmpty ? full : selected
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
