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
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // close X 直接约束到 self（不进 rowStack）：所有 tab card 的 close 位置严格
        // 一致（世界坐标 trailing/centerY 恒定），不随行内容/rowStack pack 布局浮动。
        let rowStack = NSStackView(views: [iconView, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rowStack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 46)
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

final class PreviewWindowController: NSWindowController, NSWindowDelegate, NSMenuDelegate, WKNavigationDelegate, WKScriptMessageHandler {
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
    private let closeAllRow = NSStackView()
    private let closeAllButton = NSButton()
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
    private let viewModeGroup = NSStackView()
    private let copyContentButton = NSButton()
    private let copyNameButton = NSButton()
    private let copyAbsPathButton = NSButton()
    private let copyRelPathButton = NSButton()
    private let revealButton = NSButton()
    private let overflowButton = NSButton()
    private let overflowMenu = NSMenu()
    private var wrapLinesMenuItem: NSMenuItem?
    private let scrollView = DropScrollView()
    private let gutterView = PreviewGutterView()
    private let textView = DropTextView()
    /// 选区触发的浮动 Copy Path:Line 按钮：住在 scrollView.contentView 顶层，不参与
    /// 文档滚动；位置由 updateSelectionActionButton() 主动同步（见滚动/选区观察）。
    private let selectionActionButton = NSButton()
    private var selectionUpdateTimer: Timer?
    private let emptyView = NSStackView()
    /// 底部状态栏（Ln/Col/选中数/size）：所有 textView 类模式启用，markdown WebView /
    /// 空态 / 错误态隐藏（见 setStatusBarVisible）。
    private let statusBarView = NSView()
    private let statusBarLeftLabel = NSTextField(labelWithString: "")
    private let statusBarRightLabel = NSTextField(labelWithString: "")
    /// scrollView 底部两套互斥约束：statusBar 可见时钉到其顶部，隐藏时回落 contentView
    /// 底部；同一时刻只有一条 isActive，防重复激活冲突。
    private var scrollViewBottomToStatusBarConstraint: NSLayoutConstraint?
    private var scrollViewBottomToContentConstraint: NSLayoutConstraint?
    /// markdown 专用渲染面：WKWebView + 真 github-markdown-css（像素级对齐 github）。
    /// 与编辑器 scrollView 同区叠放，仅 markdown 显示。属性初始化即创建，
    /// 让 WebContent 进程尽早预热，首次打开 markdown 近乎即时。
    private let markdownWebView = WKWebView()
    /// github-markdown.css 内容，首次访问时从资源包加载一次并缓存。
    private lazy var githubMarkdownCSS = MarkdownHTMLRenderer.loadGithubMarkdownCSS()
    /// 当前是否处于 markdown WebView 呈现态（决定大纲点击走 JS 滚动还是原生滚动）。
    private var isMarkdownWebActive = false
    /// markdown WebView 场景下选区首行的源行号 heuristic 结果（见 handleWebViewSelectionPayload）；
    /// 非 markdown 场景恒 nil，copyPathLineReference() 据 isMarkdownWebActive 二选一。
    private var webViewSelectionLine: Int?
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
    /// textView 选区变化观察 token（状态栏 Ln/Col/选中数刷新）；controller 未作为
    /// NSTextViewDelegate，走 NotificationCenter 监听，deinit 清理同上。
    private nonisolated(unsafe) var textViewSelectionObserver: NSObjectProtocol?
    /// 当前渲染为 JSON/JSONL formatted（usesJSONHighlighting）时的折叠上下文：
    /// foldSourceText 为完整 pretty 全文，foldMap 为其折叠结构索引，collapsedFoldIDs 为
    /// 已折叠的 FoldRegion.id 集合，foldComposition 为按当前 collapsed 合成的可见态。
    /// 非 JSON 模式（或折叠尚未就绪）全 nil/空，gutterView.foldDisplay /
    /// textView.foldOverlay 同步清 nil，行为与改动前完全一致。
    private var foldSourceText: String?
    private var foldMap: JSONFoldMap?
    private var collapsedFoldIDs: Set<Int> = []
    private var foldComposition: FoldComposition?
    /// 折叠合成前的原始（源坐标）display：JSONL `.markers` 模式的 gutter markers /
    /// 记录分隔线 / 坏行区间据此在每次 applyFoldState() 时经 visibleRange(forSource:)
    /// remap；`.lineNumbers` 模式不需要它（直接用可见文本重建）。
    private var foldOriginalDisplay: PreviewDisplayMetadata?
    /// 每次新渲染落地（beginFoldContext/clearFoldContext）递增；折叠相关的后台任务
    /// （foldMap.build / >2MB compose）完成时校验代际未过期才落地，防止 tab 切换/
    /// 重新渲染后迟到的结果覆盖新内容。
    private var foldRenderGeneration = 0
    /// 每次 applyFoldState() 调用递增；解决同一渲染代际内快速连续折叠/展开时，
    /// 先发出的旧后台合成结果晚到达而覆盖新结果的竞态。
    private var foldComposeSequence = 0
    /// 状态栏 Ln/Col 计算用的源坐标行起点表：JSON/JSONL 折叠上下文下取 foldSourceText
    /// 的行表（折叠只改可见范围、不改源文本行号，故与 collapsedFoldIDs 无关、渲染落地时
    /// 建一次即可）；非折叠模式取当前 textView 内容本身的行表。
    private var statusBarSourceLineStarts: [Int] = [0]
    /// 状态栏右侧 "size: X.XX KB/MB" 文案；渲染落地时按文档字节数算一次，selection
    /// 变化时直接复用（避免每次选区变化重算）。
    private var statusBarSizeText: String = ""
    /// 递增即作废在途布局泵；每次内容或换行模式变化后 startLayoutPump() 重启。
    private var layoutPumpGeneration = 0
    /// 递增即作废在途高亮分块流；tab 切换/关闭/重新渲染时 invalidateHighlighting() 推进，
    /// 在途 Task 据此丢弃迟到的 chunk，杜绝旧文档颜色刷到新文档上。
    private var highlightGeneration = 0
    private var highlightTask: Task<Void, Never>?
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
        setupStatusBar()
        setupMarkdownWebView()
        // 浮动选区按钮住 contentView 顶层，必须晚于 scrollView/markdownWebView 加入，
        // 保证其 z-order 覆盖两条渲染路径（addSubview 默认叠在已有 subview 之上）。
        setupSelectionActionButton()
        setupEmptyView()

        let sidebarWidthConstraint = sidebarView.widthAnchor.constraint(equalToConstant: 210)
        self.sidebarWidthConstraint = sidebarWidthConstraint

        let scrollViewBottomToStatusBar = scrollView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor)
        let scrollViewBottomToContent = scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        scrollViewBottomToStatusBarConstraint = scrollViewBottomToStatusBar
        scrollViewBottomToContentConstraint = scrollViewBottomToContent

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

            markdownWebView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            markdownWebView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            markdownWebView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            markdownWebView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 22),

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
        sidebarStack.addArrangedSubview(closeAllRow)
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

            closeAllRow.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor),
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

        closeAllButton.title = "Close All"
        closeAllButton.font = NSFont.systemFont(ofSize: 11)
        closeAllButton.isBordered = false
        closeAllButton.contentTintColor = .secondaryLabelColor
        closeAllButton.target = self
        closeAllButton.action = #selector(closeAllTabsClicked(_:))
        closeAllButton.setContentHuggingPriority(.required, for: .horizontal)
        closeAllButton.translatesAutoresizingMaskIntoConstraints = false

        let closeAllSpacer = NSView()
        closeAllSpacer.translatesAutoresizingMaskIntoConstraints = false
        closeAllSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        closeAllSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeAllRow.orientation = .horizontal
        closeAllRow.alignment = .centerY
        closeAllRow.spacing = 8
        closeAllRow.translatesAutoresizingMaskIntoConstraints = false
        closeAllRow.addArrangedSubview(closeAllSpacer)
        closeAllRow.addArrangedSubview(closeAllButton)
        // tabs < 2 时无需一键清空；后续 updateCloseAllVisibility() 据 tabs 数量与当前
        // 生效侧栏区块（仅 Open 区块可见）刷新。
        closeAllRow.isHidden = true
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

        // Group A：视图模式段控件独立一组（JSON 家族/空态/加载中隐藏时随 modeControl.isHidden
        // 折叠，见 render()/renderMarkdownWeb() 的同步点）。
        viewModeGroup.orientation = .horizontal
        viewModeGroup.spacing = 0
        viewModeGroup.translatesAutoresizingMaskIntoConstraints = false
        viewModeGroup.addArrangedSubview(modeControl)

        // 4 个独立文件级复制动作：各自图标编码"复制哪种信息"，点击即时生效，不再有
        // "点了才发现是菜单"的隐喻错位（见 plan D8）。
        configureIconButton(copyContentButton, symbol: "doc.on.clipboard", tooltip: "Copy File Content", action: #selector(copyContentClicked(_:)))
        configureIconButton(copyNameButton, symbol: "character.textbox", tooltip: "Copy File Name", action: #selector(copyNameClicked(_:)))
        configureIconButton(copyAbsPathButton, symbol: "link", tooltip: "Copy Absolute Path", action: #selector(copyAbsPathClicked(_:)))
        configureIconButton(copyRelPathButton, symbol: "arrow.turn.up.right", tooltip: "Copy Relative Path", action: #selector(copyRelPathClicked(_:)))
        configureIconButton(revealButton, symbol: "folder", tooltip: "Reveal in Finder", action: #selector(revealInFinder(_:)))
        configureIconButton(overflowButton, symbol: "ellipsis.circle", tooltip: "More", action: #selector(showOverflowMenu(_:)))
        configureOverflowMenu()

        // copyGroup（4 个文件级复制动作）与 locationGroup（Reveal / overflow：定位与
        // 视图设置入口）各自组内间距 8；两小组间距 12（> 组内间距，编码两个子类）。
        let copyGroup = NSStackView(views: [copyContentButton, copyNameButton, copyAbsPathButton, copyRelPathButton])
        copyGroup.orientation = .horizontal
        copyGroup.alignment = .centerY
        copyGroup.spacing = 8
        copyGroup.translatesAutoresizingMaskIntoConstraints = false

        let locationGroup = NSStackView(views: [revealButton, overflowButton])
        locationGroup.orientation = .horizontal
        locationGroup.alignment = .centerY
        locationGroup.spacing = 8
        locationGroup.translatesAutoresizingMaskIntoConstraints = false

        // Group B：当前文件的动作/视图设置入口。
        let actionGroup = NSStackView(views: [copyGroup, locationGroup])
        actionGroup.orientation = .horizontal
        actionGroup.alignment = .centerY
        actionGroup.spacing = 12
        actionGroup.translatesAutoresizingMaskIntoConstraints = false

        // Group A / Group B 组间距 20（≥1.5× 组内间距 8），编码"两组不同类"。
        let controls = NSStackView(views: [viewModeGroup, actionGroup])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 20
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

            copyContentButton.widthAnchor.constraint(equalToConstant: 30),
            copyNameButton.widthAnchor.constraint(equalToConstant: 30),
            copyAbsPathButton.widthAnchor.constraint(equalToConstant: 30),
            copyRelPathButton.widthAnchor.constraint(equalToConstant: 30),
            revealButton.widthAnchor.constraint(equalToConstant: 30),
            overflowButton.widthAnchor.constraint(equalToConstant: 30)
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
        // 与 applyMarkdownReadingColumn 的非 markdown 紧凑内边距一致，首帧即为最终值。
        textView.textContainerInset = NSSize(width: 4, height: 6)
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
        gutterView.onToggleFold = { [weak self] visibleLine in
            self?.toggleFold(atVisibleLine: visibleLine)
        }

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

        // 状态栏 Ln/Col/选中数随选区变化刷新；controller 未作为 NSTextViewDelegate，
        // 走 NotificationCenter（同上 boundsDidChange 的 assumeIsolated 论证）。
        textViewSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusBar()
            }
        }
    }

    /// 选区级浮动 Copy Path:Line 按钮：住在 contentView（controller 根 view）顶层——
    /// NSTextView 场景与 markdown WebView 场景的目标 view 不同（scrollView vs.
    /// markdownWebView），contentView 是两者共同的上层容器，坐标统一由各自的
    /// updateSelectionActionButton() / updateSelectionActionButtonForWebView() 转换。
    /// 仅在非空选区、窗口 key 时显示（见 selectionDidChange / updateSelectionActionButton）。
    private func setupSelectionActionButton() {
        selectionActionButton.title = "path:line"
        if let symbolImage = NSImage(systemSymbolName: "link.badge.arrow.up.right", accessibilityDescription: "Copy path:line") {
            selectionActionButton.image = symbolImage
        } else {
            selectionActionButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Copy path:line")
        }
        selectionActionButton.imagePosition = .imageLeading
        selectionActionButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        selectionActionButton.contentTintColor = .white
        // AttributedTitle 明确白字，避免 NSButton 在 borderless + 深色背景下沿用系统灰。
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)
        ]
        selectionActionButton.attributedTitle = NSAttributedString(string: "path:line", attributes: attrs)
        selectionActionButton.isBordered = false
        selectionActionButton.wantsLayer = true
        selectionActionButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        selectionActionButton.layer?.cornerRadius = 6
        // 阴影强化脱离底层，确保在浅色/深色两外观下都醒目。
        selectionActionButton.shadow = NSShadow()
        selectionActionButton.layer?.shadowColor = NSColor.black.cgColor
        selectionActionButton.layer?.shadowOpacity = 0.18
        selectionActionButton.layer?.shadowOffset = CGSize(width: 0, height: -1)
        selectionActionButton.layer?.shadowRadius = 4
        selectionActionButton.layer?.masksToBounds = false
        selectionActionButton.target = self
        selectionActionButton.action = #selector(selectionCopyPathLineClicked(_:))
        selectionActionButton.translatesAutoresizingMaskIntoConstraints = false
        selectionActionButton.isHidden = true

        // 加到 contentView 的顶层（positioned: .above），保证覆盖 scrollView 与
        // markdownWebView；位置纯 frame 驱动，不加 anchor 约束。
        contentView.addSubview(selectionActionButton, positioned: .above, relativeTo: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionActionButtonBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    /// 选区变化 debounce 150ms 再评估显隐/定位，避免拖选过程中浮动按钮闪现。
    @objc private func selectionDidChange(_ notification: Notification) {
        selectionUpdateTimer?.invalidate()
        selectionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateSelectionActionButton()
            }
        }
    }

    /// 窗口失活立即隐藏浮动按钮（不等 debounce）。
    @objc func windowDidResignKey(_ notification: Notification) {
        selectionActionButton.isHidden = true
    }

    /// 滚动时按钮跟随选区在屏上重新定位；仅在已显示时才需要重算，避免空跑。
    @objc private func selectionActionButtonBoundsDidChange(_ notification: Notification) {
        guard !selectionActionButton.isHidden else { return }
        updateSelectionActionButton()
    }

    /// 计算选区首行边缘的浮动按钮位置（NSTextView 场景）；越界（贴工具栏/右缘）时反向就近校正。
    private func updateSelectionActionButton() {
        guard window?.isKeyWindow == true, activeTab != nil else {
            selectionActionButton.isHidden = true
            return
        }

        let range = textView.selectedRange()
        guard range.length > 0 else {
            selectionActionButton.isHidden = true
            return
        }

        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            selectionActionButton.isHidden = true
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            selectionActionButton.isHidden = true
            return
        }

        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let selectionRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphRange.location, length: min(glyphRange.length, 200)),
            in: textContainer
        )

        // textView 坐标 → contentView 坐标；转换含高度的完整矩形（而非仅转换一个点后手动
        // 加高度），让 convert(_:to:) 正确处理 textView（flipped）与 contentView（非 flipped）
        // 两者相反的 flip 方向——单点转换后再手动加减高度在跨 flip 时方向会算错。
        let inTextView = NSRect(
            x: selectionRect.maxX,
            y: lineFragmentRect.minY,
            width: 0,
            height: lineFragmentRect.height
        ).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        let rectInContent = textView.convert(inTextView, to: contentView)

        positionSelectionActionButton(anchorRect: rectInContent)
    }

    /// markdown WebView 场景的浮动按钮定位：payload 坐标是 CSS 像素（相对 WKWebView
    /// viewport）；WKWebView 本身是 flipped view，与 CSS 的 top-left/y-down 语义一致，
    /// 可直接构造矩形转换，无需额外翻转。
    private func updateSelectionActionButtonForWebView(x: Double, y: Double, width: Double, height: Double) {
        guard window?.isKeyWindow == true, isMarkdownWebActive else {
            selectionActionButton.isHidden = true
            return
        }

        let webRect = NSRect(x: x, y: y, width: width, height: height)
        let rectInContent = markdownWebView.convert(webRect, to: contentView)
        positionSelectionActionButton(anchorRect: rectInContent)
    }

    /// NSTextView / markdown WebView 两条路径共用的浮动按钮几何：anchorRect 已转换到
    /// contentView（非 flipped，y 向上）坐标系——anchorRect.maxY 对应锚点视觉上边缘、
    /// .minY 对应视觉下边缘（与两条路径各自转换前的 flipped 源视图里 min/max 含义相反，
    /// 由 convert(_:to:) 处理）。默认贴锚点上边缘上方 4pt；若越过 header 下边界（工具栏），
    /// 反向落到锚点下边缘下方 4pt；最终两轴都收敛在 contentView.bounds 内。
    private func positionSelectionActionButton(anchorRect: NSRect) {
        selectionActionButton.sizeToFit()
        var frame = selectionActionButton.frame
        // sizeToFit 只算 title + image 自身宽度，borderless 无内边距——手动加 16pt
        // 左右填充让 chip 视觉不挤，同时兜底最小宽度 108（放得下 icon + "path:line"）。
        frame.size.width = max(frame.size.width + 16, 108)
        frame.size.height = 28
        frame.origin.x = anchorRect.maxX - frame.width
        frame.origin.y = anchorRect.maxY + 4

        let clipBounds = contentView.bounds
        let headerBoundary = headerView.frame.minY - 4
        if frame.origin.y + frame.height > headerBoundary {
            frame.origin.y = anchorRect.minY - frame.height - 4
        }

        frame.origin.x = max(clipBounds.minX + 4, min(frame.origin.x, clipBounds.maxX - frame.width - 4))
        frame.origin.y = max(clipBounds.minY + 4, min(frame.origin.y, clipBounds.maxY - frame.height - 4))

        selectionActionButton.frame = frame
        selectionActionButton.isHidden = false
    }

    @objc private func selectionCopyPathLineClicked(_ sender: Any?) {
        copyPathLineReference()
        selectionActionButton.isHidden = true
    }

    /// 底部状态栏：左侧 Ln/Col/选中数，右侧文件 size；纯背景色块（非 vibrancy），色走
    /// PeekyTheme，见 applyStatusBarColors。默认隐藏，显示态由各渲染路径显式切换
    /// （见 setStatusBarVisible）。
    private func setupStatusBar() {
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.wantsLayer = true
        contentView.addSubview(statusBarView)

        statusBarLeftLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusBarLeftLabel.lineBreakMode = .byTruncatingTail
        statusBarLeftLabel.maximumNumberOfLines = 1

        statusBarRightLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusBarRightLabel.lineBreakMode = .byTruncatingTail
        statusBarRightLabel.maximumNumberOfLines = 1
        statusBarRightLabel.alignment = .right
        statusBarRightLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusBarRightLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let statusBarStack = NSStackView(views: [statusBarLeftLabel, statusBarRightLabel])
        statusBarStack.orientation = .horizontal
        statusBarStack.distribution = .equalSpacing
        statusBarStack.alignment = .centerY
        statusBarStack.translatesAutoresizingMaskIntoConstraints = false
        statusBarView.addSubview(statusBarStack)

        NSLayoutConstraint.activate([
            statusBarStack.leadingAnchor.constraint(equalTo: statusBarView.leadingAnchor, constant: 10),
            statusBarStack.trailingAnchor.constraint(equalTo: statusBarView.trailingAnchor, constant: -10),
            statusBarStack.centerYAnchor.constraint(equalTo: statusBarView.centerYAnchor)
        ])

        applyStatusBarColors()
    }

    deinit {
        if let jsonHighlightScrollObserver {
            NotificationCenter.default.removeObserver(jsonHighlightScrollObserver)
        }
        if let textViewSelectionObserver {
            NotificationCenter.default.removeObserver(textViewSelectionObserver)
        }
        // selectionDidChange / windowDidResignKey / selectionActionButtonBoundsDidChange
        // 均以 self 为 selector-based observer 注册，一并摘除。
        // selectionUpdateTimer 的 block 用 [weak self]，self 释放后 fire 自然 no-op，
        // 无需在 deinit 触碰（Swift 6 nonisolated deinit 也不允许访问非 Sendable 的 Timer）。
        NotificationCenter.default.removeObserver(self)
    }

    /// markdown 专用 WebView：与编辑器 scrollView 同区叠放，仅 markdown 显示。
    /// 不覆盖 appearance，让 github-markdown-css 的 prefers-color-scheme 随系统自动切浅深。
    /// 选区变化经 peekySelection 消息桥接回 Swift（见 userContentController(_:didReceive:)），
    /// 承接浮动 Copy Path:Line 按钮在 markdown 场景的显隐/定位。
    private func setupMarkdownWebView() {
        markdownWebView.translatesAutoresizingMaskIntoConstraints = false
        markdownWebView.isHidden = true
        markdownWebView.navigationDelegate = self
        contentView.addSubview(markdownWebView)

        let script = WKUserScript(
            source: Self.webViewSelectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        markdownWebView.configuration.userContentController.add(self, name: "peekySelection")
        markdownWebView.configuration.userContentController.addUserScript(script)
    }

    /// 注入 markdown WebView 的选区变化监听：非空选区时回传首行 clientRect（CSS 像素）
    /// 与选中文本；无选区/折叠选区时回传 hasSelection: false。经 peekySelection handler
    /// 桥接到 handleWebViewSelectionPayload(_:)。
    private static let webViewSelectionScript = #"""
    (function() {
        document.addEventListener('selectionchange', function() {
            const sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
                window.webkit.messageHandlers.peekySelection.postMessage({ hasSelection: false });
                return;
            }
            const range = sel.getRangeAt(0);
            const rects = range.getClientRects();
            const first = rects.length > 0 ? rects[0] : range.getBoundingClientRect();
            window.webkit.messageHandlers.peekySelection.postMessage({
                hasSelection: true,
                text: sel.toString(),
                x: first.left,
                y: first.top,
                width: first.width,
                height: first.height
            });
        });
    })();
    """#

    /// WKScriptMessageHandler：WebKit 保证此回调运行在主线程（同 jsonHighlightScrollObserver /
    /// textViewSelectionObserver 处的 assumeIsolated 论证一致）；message.name/.body 本身是
    /// MainActor-isolated 属性（SDK 标注），连读取也需在 assumeIsolated 块内，直接断言隔离
    /// 同步处理，避免把非 Sendable 的 Any 跨 Task 边界捕获触发 Swift 6 严格并发检查。
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard message.name == "peekySelection" else { return }
            handleWebViewSelectionPayload(message.body)
        }
    }

    /// markdown 场景源行号 heuristic：selected 来自 WebView 渲染后的纯文本（无 `**` /
    /// backtick 等 markdown 语法字符），source 是原 markdown 文本（含语法字符）。直接
    /// range(of: selected) 常失败——`**S3 principle**` 渲染成 `S3 principle`，跨过 `**`
    /// 的窗口在源里就找不到。故采取多起点、多长度短窗口采样：任一窗口能在源里 range(of:)
    /// 命中即用其行号——窗口只要避开源里 markdown 语法字符插入位置就命中，多起点保证
    /// 至少一个能落在"纯文本连续段"上。全部失败降级为 1。纯函数、无 UI 依赖、可测。
    nonisolated static func heuristicSourceLine(selected: String, in source: String) -> Int {
        guard !selected.isEmpty, !source.isEmpty else { return 1 }

        func lineNumber(atOffset offset: String.Index) -> Int {
            source[..<offset].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        }

        if let range = source.range(of: selected) {
            return lineNumber(atOffset: range.lowerBound)
        }

        let windowLengths = [40, 24, 16, 10, 6]
        let startOffsets = [0, 4, 8, 16, 24, 40, 64, 96]
        for length in windowLengths {
            for offset in startOffsets {
                guard selected.count >= offset + length else { continue }
                let startIdx = selected.index(selected.startIndex, offsetBy: offset)
                let endIdx = selected.index(startIdx, offsetBy: length)
                let needle = String(selected[startIdx..<endIdx])
                if let range = source.range(of: needle) {
                    return lineNumber(atOffset: range.lowerBound)
                }
            }
        }
        return 1
    }

    /// markdown WebView 选区 payload 处理：无选区立即隐藏；有选区则用 heuristic 算源行号，
    /// debounce 150ms 后定位浮动按钮（复用既有 selectionUpdateTimer，避免与 NSTextView
    /// 路径的 debounce 互相打断）。
    private func handleWebViewSelectionPayload(_ body: Any) {
        guard let payload = body as? [String: Any], let hasSelection = payload["hasSelection"] as? Bool else {
            return
        }

        guard hasSelection else {
            selectionActionButton.isHidden = true
            webViewSelectionLine = nil
            return
        }

        guard
            let text = payload["text"] as? String,
            let x = payload["x"] as? Double,
            let y = payload["y"] as? Double,
            let width = payload["width"] as? Double,
            let height = payload["height"] as? Double
        else {
            return
        }

        let sourceText = activeTab?.document?.text ?? ""
        webViewSelectionLine = Self.heuristicSourceLine(selected: text, in: sourceText)

        selectionUpdateTimer?.invalidate()
        selectionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateSelectionActionButtonForWebView(x: x, y: y, width: width, height: height)
            }
        }
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
        updateCloseAllVisibility()
    }

    /// Close All 只在 Open 区块生效且 tabs ≥2 时可见；tabStack.isHidden 已反映当前是否
    /// 处于 Open 区块，两条件合一即为最终显隐（tabs 数变化 / 侧栏区块切换均经此刷新，
    /// 因二者最终都会调用 updateSidebarSections()）。
    private func updateCloseAllVisibility() {
        closeAllRow.isHidden = tabs.count < 2 || tabStack.isHidden
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

    /// 一键清空全部 tab：与单 tab 关闭同一收尾（rebuildTabList → 文件树跟随 → 重渲染），
    /// 清空后 activeTab 恒 nil，renderActiveTab() 自然落到 showEmptyState() 分支。
    @objc private func closeAllTabsClicked(_ sender: Any?) {
        selectionActionButton.isHidden = true
        tabs.removeAll()
        activeTabID = nil

        rebuildTabList()
        if let url = activeTab?.url {
            establishTreeRoot(for: url)
        }
        renderActiveTab()
    }

    private func renderActiveTab() {
        selectionActionButton.isHidden = true
        invalidateHighlighting()
        clearFoldContext()

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
        viewModeGroup.isHidden = isJSONFamily
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
            beginFoldContext(sourceText: rendered.attributedText.string, originalDisplay: rendered.display, tabID: tabID)
        }
        // 非 JSON 分支：activeJSONText/activeInvalidRanges/折叠上下文已由
        // renderActiveTab() 顶部的 clearFoldContext() 清空，此处无需重复置空。
        statusBarSourceLineStarts = foldSourceText.map { PreviewDisplayMetadata.lineStartLocations(in: $0) }
            ?? PreviewDisplayMetadata.lineStartLocations(in: rendered.attributedText.string)
        statusBarSizeText = "size: \(Self.formattedFileSize(totalBytes: document.totalBytes))"
        applyEditorTheme(
            followsSystemAppearance: rendered.followsSystemAppearance,
            usesDarkModern: rendered.usesDarkModernTheme
        )
        if let language = rendered.highlightLanguage {
            startHighlighting(text: document.text, language: language, tabID: tabID)
        }
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
        setActionButtonsEnabled(true)
        copyRelPathButton.isEnabled = hasRepoRootForActiveFile
        showPreviewState()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
        let targetLocation = targetLine.flatMap { rendered.display.targetLocationsByOriginalLine[$0] }
        scheduleInitialScroll(targetLine: targetLine, targetLocation: targetLocation, tabID: tabID)

        showPlainText()
        applyVisibleJSONHighlighting()
        setStatusBarVisible(true)
        updateStatusBar()
    }

    private func renderError(message: String, url: URL) {
        titleLabel.stringValue = url.lastPathComponent
        metaLabel.stringValue = "Open failed"
        modeControl.isEnabled = false
        setActionButtonsEnabled(true)
        copyRelPathButton.isEnabled = hasRepoRootForActiveFile

        textView.textStorage?.setAttributedString(SyntaxHighlighter.monospace(message))
        applyDisplayMetadata(.plain)
        applyEditorTheme(followsSystemAppearance: false, usesDarkModern: false)
        clearMarkdownOutline()
        showPreviewState()
        showPlainText()
        applyLineWrapping()
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        startLayoutPump()
        setStatusBarVisible(false)
    }

    /// 恒单 textView 视图：显示编辑器 scrollView（含 textView + 行号 gutter）。
    private func showPlainText() {
        markdownWebView.isHidden = true
        isMarkdownWebActive = false
        selectionActionButton.isHidden = true
        webViewSelectionLine = nil
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
        selectionActionButton.isHidden = true
        webViewSelectionLine = nil
        isMarkdownWebActive = true
        modeControl.isHidden = true
        viewModeGroup.isHidden = true

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
        setActionButtonsEnabled(true)
        copyRelPathButton.isEnabled = hasRepoRootForActiveFile

        showPreviewState()
        showMarkdownWeb()
        setStatusBarVisible(false)
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

    // MARK: - 折叠管线（F6）：collapsed 状态持有 + 重组显示 + 双击选区/复制注入

    /// 新渲染落地为 JSON/JSONL formatted 时建立折叠上下文：collapsed 清空，后台线程
    /// build 折叠索引，回主线程存 foldMap 并跑一次 applyFoldState() 建立初始（恒等）
    /// 合成态——gutter 从此带三角/跳号，正文带缩进导轨，像素上与之前完全一致
    /// （collapsed 为空时 compose 恒等）。tabID + foldRenderGeneration 双重代际校验，
    /// 防止 tab 切换/重新渲染后迟到的 build 结果覆盖新内容。
    private func beginFoldContext(sourceText: String, originalDisplay: PreviewDisplayMetadata, tabID: UUID) {
        foldSourceText = sourceText
        foldOriginalDisplay = originalDisplay
        collapsedFoldIDs = []
        foldMap = nil
        foldComposition = nil
        foldRenderGeneration += 1
        let generation = foldRenderGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let builtMap = JSONFoldMap.build(prettyText: sourceText)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.foldRenderGeneration == generation, self.activeTabID == tabID else { return }
                self.foldMap = builtMap
                self.applyFoldState()
            }
        }
    }

    /// 折叠上下文全清（含 activeJSONText/activeInvalidRanges，两者与 usesJSONHighlighting
    /// 门控一致）：非 JSON 模式下 gutter/正文均不带折叠注入面，可见区分色整体跳过，
    /// 行为与改动前完全一致。
    private func clearFoldContext() {
        foldSourceText = nil
        foldOriginalDisplay = nil
        foldMap = nil
        foldComposition = nil
        collapsedFoldIDs = []
        foldRenderGeneration += 1
        activeJSONText = nil
        activeInvalidRanges = []
        gutterView.foldDisplay = nil
        textView.foldOverlay = nil
    }

    /// gutter 折叠三角点击：可见行 → 源行（无 composition 时恒等）→ 命中 openLine 的
    /// region → toggle 其 id 进/出 collapsedFoldIDs → 重组显示。
    private func toggleFold(atVisibleLine visibleLine: Int) {
        guard let foldMap else { return }

        let sourceLine: Int
        if let composition = foldComposition, visibleLine >= 0, visibleLine < composition.visibleLineToSourceLine.count {
            sourceLine = composition.visibleLineToSourceLine[visibleLine]
        } else {
            sourceLine = visibleLine
        }

        guard let region = foldMap.regions.first(where: { $0.openLine == sourceLine }) else { return }

        if collapsedFoldIDs.contains(region.id) {
            collapsedFoldIDs.remove(region.id)
        } else {
            collapsedFoldIDs.insert(region.id)
        }

        applyFoldState()
    }

    /// 重组显示：记住重组前视口首行的源行号，按当前 collapsedFoldIDs 合成新可见态
    /// （≤2MB 主线程直算，>2MB 后台算完回主线程），落地后把视口映射回新可见行滚动
    /// 保持。foldComposeSequence + foldRenderGeneration + activeTabID 三重代际校验，
    /// 快速连续折叠/展开时旧结果不会覆盖新结果。
    private func applyFoldState() {
        guard let foldSourceText, let foldMap, foldOriginalDisplay != nil else { return }

        let priorVisibleLine = currentVisibleLineIndex()
        let priorSourceLine: Int
        if let composition = foldComposition, priorVisibleLine < composition.visibleLineToSourceLine.count {
            priorSourceLine = composition.visibleLineToSourceLine[priorVisibleLine]
        } else {
            priorSourceLine = priorVisibleLine
        }

        foldComposeSequence += 1
        let sequence = foldComposeSequence
        let renderGeneration = foldRenderGeneration
        let tabID = activeTabID
        let collapsed = collapsedFoldIDs

        let sourceLength = (foldSourceText as NSString).length
        if sourceLength <= 2_000_000 {
            let composition = JSONFoldComposer.compose(sourceText: foldSourceText, foldMap: foldMap, collapsed: collapsed)
            finishApplyFoldState(composition, priorSourceLine: priorSourceLine, sequence: sequence, renderGeneration: renderGeneration, tabID: tabID)
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let composition = JSONFoldComposer.compose(sourceText: foldSourceText, foldMap: foldMap, collapsed: collapsed)
                DispatchQueue.main.async {
                    self?.finishApplyFoldState(composition, priorSourceLine: priorSourceLine, sequence: sequence, renderGeneration: renderGeneration, tabID: tabID)
                }
            }
        }
    }

    private func finishApplyFoldState(
        _ composition: FoldComposition,
        priorSourceLine: Int,
        sequence: Int,
        renderGeneration: Int,
        tabID: UUID?
    ) {
        guard
            foldComposeSequence == sequence,
            foldRenderGeneration == renderGeneration,
            activeTabID == tabID
        else { return }

        foldComposition = composition
        applyFoldComposition(composition)

        let newVisibleLine = floorVisibleLineIndex(forSourceLine: priorSourceLine, in: composition.visibleLineToSourceLine)
        scrollToVisibleLine(newVisibleLine, in: composition)
    }

    /// textStorage 整体替换为可见文本（沿用现有字体/基础前景铺色路径，折叠前后字体
    /// 不变）；chip 占位逐个挂 attachment cell（不改字符，U+FFFC 已在 visibleText 中）；
    /// gutter/正文注入面重建；activeJSONText/activeInvalidRanges 同步到可见坐标；
    /// 布局泵 + 可见区语义分色照常跑。
    private func applyFoldComposition(_ composition: FoldComposition) {
        let storage = NSMutableAttributedString(attributedString: SyntaxHighlighter.monospace(composition.visibleText))
        for chipRange in composition.chipRanges {
            let attachment = NSTextAttachment()
            attachment.attachmentCell = FoldChipAttachmentCell()
            storage.addAttribute(.attachment, value: attachment, range: chipRange)
        }
        textView.textStorage?.setAttributedString(storage)
        applyFollowSystemEditorColors()

        updateFoldGutterAndOverlay(for: composition)

        activeJSONText = composition.visibleText
        activeInvalidRanges = remappedInvalidRanges(in: composition)

        startLayoutPump()
        applyVisibleJSONHighlighting()
    }

    /// gutter 配置（.lineNumbers 直接用可见文本重建；.markers 把原始 markers/记录分隔线/
    /// 坏行区间逐个经 visibleRange(forSource:) remap）+ foldDisplay（跳号 + 三角状态）+
    /// 正文 foldOverlay（缩进导轨 + 双击选区扩展表 + 复制映射）。
    private func updateFoldGutterAndOverlay(for composition: FoldComposition) {
        guard let foldMap else { return }

        let lineStarts = PreviewDisplayMetadata.lineStartLocations(in: composition.visibleText)

        var disclosures: [Int: GutterDisclosureState] = [:]
        let regionsByOpenLine = Dictionary(uniqueKeysWithValues: foldMap.regions.map { ($0.openLine, $0) })
        for (visibleLine, sourceLine) in composition.visibleLineToSourceLine.enumerated() {
            guard let region = regionsByOpenLine[sourceLine] else { continue }
            disclosures[visibleLine] = collapsedFoldIDs.contains(region.id) ? .collapsed : .expanded
        }

        switch foldOriginalDisplay?.gutter.mode {
        case .markers(let originalMarkers):
            let remappedMarkers = originalMarkers.compactMap { marker -> PreviewGutterMarker? in
                guard
                    let visible = JSONFoldComposer.visibleRange(
                        forSource: NSRange(location: marker.characterLocation, length: 0),
                        in: composition
                    )
                else { return nil }
                return PreviewGutterMarker(characterLocation: visible.location, label: marker.label, isWarning: marker.isWarning)
            }
            gutterView.configuration = .markers(remappedMarkers)
        default:
            gutterView.configuration = .lineNumbers(for: composition.visibleText)
        }

        gutterView.foldDisplay = GutterFoldDisplay(
            visibleLineToSourceLine: composition.visibleLineToSourceLine,
            disclosures: disclosures,
            lineStartLocations: lineStarts
        )

        let remappedSeparators = (foldOriginalDisplay?.textOverlay.recordSeparatorLocations ?? []).compactMap {
            JSONFoldComposer.visibleRange(forSource: NSRange(location: $0, length: 0), in: composition)?.location
        }
        textView.overlayConfiguration = PreviewTextOverlayConfiguration(recordSeparatorLocations: remappedSeparators)

        textView.foldOverlay = FoldOverlayConfiguration(
            lineDepths: composition.visibleLineDepths,
            lineStartLocations: lineStarts,
            indentStepWidth: indentStepWidth(),
            selectionExpansions: buildSelectionExpansions(composition: composition, foldMap: foldMap),
            copyTransform: { [weak self] visibleRange in
                self?.foldCopyTransform(visibleRange)
            }
        )
    }

    /// 原始（源坐标）坏行区间逐个经 visibleRange(forSource:) remap；落在折叠内容中的
    /// 返回 chip 位置，照用（chip 本身呈红即代表其中含坏行）。
    private func remappedInvalidRanges(in composition: FoldComposition) -> [NSRange] {
        guard let originalRanges = foldOriginalDisplay?.invalidRecordRanges, !originalRanges.isEmpty else { return [] }
        return originalRanges.compactMap { JSONFoldComposer.visibleRange(forSource: $0, in: composition) }
    }

    /// 双击选区扩展表（全部可见坐标）：
    /// - 已折叠且未被外层吞并（effectiveCollapsed）的 region：trigger = 其 chip；
    ///   selection = chip 所在可见行行首 到 close 括号（含）。
    /// - 展开且未被祖先折叠吞并的 region：trigger = open 括号；selection = open 括号
    ///   起到 close 括号（含）。
    /// region 数 > 2000 时只对 openLine 落在当前可视行 ±5000 内的 region 生成（性能护栏）。
    private func buildSelectionExpansions(
        composition: FoldComposition,
        foldMap: JSONFoldMap
    ) -> [(trigger: NSRange, selection: NSRange)] {
        let effectiveCollapsedRegions = effectivelyCollapsedRegions(foldMap: foldMap, collapsed: collapsedFoldIDs)

        var regions = foldMap.regions
        if regions.count > 2000 {
            let anchorSourceLine = composition.visibleLineToSourceLine.first ?? 0
            regions = regions.filter { abs($0.openLine - anchorSourceLine) <= 5000 }
        }

        let lineStarts = PreviewDisplayMetadata.lineStartLocations(in: composition.visibleText)
        var expansions: [(trigger: NSRange, selection: NSRange)] = []

        for region in regions {
            let innerRange = region.innerCharRange
            let closeBracketSource = NSRange(location: innerRange.location + innerRange.length, length: 1)
            guard let closeVisible = JSONFoldComposer.visibleRange(forSource: closeBracketSource, in: composition) else {
                continue
            }
            let selectionEnd = closeVisible.location + closeVisible.length

            if effectiveCollapsedRegions.contains(where: { $0.id == region.id }) {
                guard
                    let chipVisible = JSONFoldComposer.visibleRange(forSource: innerRange, in: composition),
                    chipVisible.length == 1
                else { continue }
                let lineIndex = lineStartIndex(for: chipVisible.location, in: lineStarts)
                let lineStart = lineIndex < lineStarts.count ? lineStarts[lineIndex] : chipVisible.location
                let selection = NSRange(location: lineStart, length: max(0, selectionEnd - lineStart))
                expansions.append((trigger: chipVisible, selection: selection))
            } else {
                let isSwallowed = effectiveCollapsedRegions.contains { ancestor in
                    ancestor.id != region.id
                        && ancestor.openLine <= region.openLine
                        && region.closeLine <= ancestor.closeLine
                }
                guard !isSwallowed else { continue }

                let openBracketSource = NSRange(location: innerRange.location - 1, length: 1)
                guard let openVisible = JSONFoldComposer.visibleRange(forSource: openBracketSource, in: composition) else {
                    continue
                }
                let selection = NSRange(location: openVisible.location, length: max(0, selectionEnd - openVisible.location))
                expansions.append((trigger: openVisible, selection: selection))
            }
        }

        return expansions
    }

    /// 折叠生效集：collapsed 中存在于 foldMap 的区域，按行区间互不包含关系收敛到最外层
    /// （镜像 JSONFoldComposer 的私有 effectiveRegions 逻辑，该函数未导出）。
    private func effectivelyCollapsedRegions(foldMap: JSONFoldMap, collapsed: Set<Int>) -> [FoldRegion] {
        let candidates = foldMap.regions.filter { collapsed.contains($0.id) }
        guard !candidates.isEmpty else { return [] }
        return candidates.filter { candidate in
            !candidates.contains { other in
                other.id != candidate.id
                    && other.openLine <= candidate.openLine
                    && candidate.closeLine <= other.closeLine
            }
        }
    }

    /// 复制映射：选区与任一 chip 相交才展开为完整底层源文本，否则 nil 走默认复制。
    private func foldCopyTransform(_ visibleRange: NSRange) -> String? {
        guard let composition = foldComposition, let foldSourceText else { return nil }
        guard composition.chipRanges.contains(where: { NSIntersectionRange($0, visibleRange).length > 0 }) else {
            return nil
        }

        let sourceRange = JSONFoldComposer.sourceRange(forVisible: visibleRange, in: composition)
        let ns = foldSourceText as NSString
        let clampedLocation = min(max(sourceRange.location, 0), ns.length)
        let clampedLength = min(max(sourceRange.length, 0), ns.length - clampedLocation)
        return ns.substring(with: NSRange(location: clampedLocation, length: clampedLength))
    }

    /// 一个缩进级（2 空格）在正文字体下的宽度。
    private func indentStepWidth() -> CGFloat {
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return (" " as NSString).size(withAttributes: [.font: font]).width * 2
    }

    /// 当前视口首个可见行在"当前显示文本"坐标系中的行号(0-based)；复用既有
    /// lineStartIndex(for:in:) 的二分查找（floor 语义）。
    private func currentVisibleLineIndex() -> Int {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return 0 }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: textView.visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return 0 }
        let charRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let lineStarts = gutterView.foldDisplay?.lineStartLocations
            ?? PreviewDisplayMetadata.lineStartLocations(in: textView.string)
        return lineStartIndex(for: charRange.location, in: lineStarts)
    }

    /// mapping 中最后一个 <= sourceLine 的下标（floor 二分），mapping 恒为
    /// visibleLineToSourceLine（单调不降）。
    private func floorVisibleLineIndex(forSourceLine sourceLine: Int, in mapping: [Int]) -> Int {
        guard !mapping.isEmpty else { return 0 }

        var low = 0
        var high = mapping.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if mapping[mid] <= sourceLine {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return match
    }

    /// 重组后把视口保持在 visibleLine：确保该行已布局后 scrollRangeToVisible（不含
    /// showFindIndicator 高亮闪烁，这是内部视口保持，不是用户发起的导航）。
    private func scrollToVisibleLine(_ visibleLine: Int, in composition: FoldComposition) {
        let text = composition.visibleText as NSString
        guard text.length > 0 else { return }

        let lineStarts = gutterView.foldDisplay?.lineStartLocations
            ?? PreviewDisplayMetadata.lineStartLocations(in: composition.visibleText)
        let start = visibleLine >= 0 && visibleLine < lineStarts.count ? lineStarts[visibleLine] : 0
        let lineRange = text.lineRange(for: NSRange(location: min(start, text.length), length: 0))
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.scrollRangeToVisible(lineRange)
        gutterView.needsDisplay = true
    }

    // MARK: - 底部状态栏（F6）：Ln/Col/选中数/size

    /// statusBar 可见性切换：isHidden + 两套 scrollView 底部约束 isActive 互斥切换，
    /// 防重复激活冲突（AutoLayout 同一 attribute 两条 required 约束同时 active 会报错）。
    private func setStatusBarVisible(_ visible: Bool) {
        statusBarView.isHidden = !visible
        scrollViewBottomToStatusBarConstraint?.isActive = visible
        scrollViewBottomToContentConstraint?.isActive = !visible
    }

    /// 背景 statusBarBackground + 文字 statusBarText（11pt mono），按 textView 当前
    /// effectiveAppearance 解析——Dark Modern/plain 等非跟随系统模式也统一按此取色，
    /// 与编辑器区（尤其是钉死 darkAqua 的 Dark Modern）视觉一致。
    private func applyStatusBarColors() {
        let appearance = PeekyTheme.resolveAppearance(textView.effectiveAppearance)
        statusBarView.layer?.backgroundColor = PeekyTheme.color(.statusBarBackground, appearance: appearance).cgColor
        let textColor = PeekyTheme.color(.statusBarText, appearance: appearance)
        statusBarLeftLabel.textColor = textColor
        statusBarRightLabel.textColor = textColor
    }

    /// 左侧 "Ln X, Col Y"（+ 选中时追加 "N characters selected"）+ 右侧 "size: X.XX KB/MB"；
    /// 行列/选中数按源坐标：selectedRange（可见）经 sourceRange(forVisible:) 映射
    /// （无折叠上下文时恒等）。
    private func updateStatusBar() {
        guard !statusBarView.isHidden else { return }

        let visibleSelection = textView.selectedRange()
        let sourceSelection = foldComposition.map {
            JSONFoldComposer.sourceRange(forVisible: visibleSelection, in: $0)
        } ?? visibleSelection

        let starts = statusBarSourceLineStarts
        let lineIndex = lineStartIndex(for: sourceSelection.location, in: starts)
        let line = lineIndex + 1
        let lineStart = lineIndex < starts.count ? starts[lineIndex] : 0
        let column = sourceSelection.location - lineStart + 1

        var left = "Ln \(line), Col \(column)"
        if sourceSelection.length > 0 {
            left += "   \(sourceSelection.length) characters selected"
        }

        statusBarLeftLabel.stringValue = left
        statusBarRightLabel.stringValue = statusBarSizeText
    }

    /// "X.XX KB"（<1MB）或 "X.XX MB"（≥1MB），字节数除 1024 两位小数。
    private static func formattedFileSize(totalBytes: Int64) -> String {
        let kilobytes = Double(totalBytes) / 1024
        if kilobytes >= 1024 {
            return String(format: "%.2f MB", kilobytes / 1024)
        }
        return String(format: "%.2f KB", kilobytes)
    }

    // MARK: - 限宽阅读列（R4f）：markdown formatted 模式正文列定宽居中

    /// 当前是否应处于限宽阅读列状态：markdown + formatted + 开启折行。关闭折行时
    /// textView 走水平滚动（isHorizontallyResizable=true / widthTracksTextView=false），
    /// 折行意义上的"列宽"不成立，故此时与非 markdown 一样退回默认全宽。
    private var isMarkdownReadingColumnActive: Bool {
        guard wrapsLines, let tab = activeTab, let document = tab.document else { return false }
        return document.kind == .markdown && tab.mode == .formatted
    }

    /// 正文填满窗口：markdown-formatted 用略宽的对称内边距（32pt 横 / 16pt 纵）；
    /// 其余模式（JSON/源码/文本等编辑器形态）用紧凑内边距（4pt 横 / 6pt 纵）——
    /// 横向实际留白 = inset 4pt + NSTextContainer lineFragmentPadding 5pt = 9pt，
    /// 与 gutter 分隔线保持贴近而不粘连。textView 走 widthTracksTextView=true +
    /// autoresizingMask [.width]，实际排版宽 = frame 宽 − 2×inset，正文随窗口变宽
    /// 自动变宽；内边距为常量、不依赖当前宽度，故初始打开与拖拽 resize 都无需按
    /// 宽度重算。字符定位（scrollToLine/scrollToOutlineItem 等）全程只用 NSRange
    /// 偏移、不含 x 坐标假设，不受内边距影响。
    private func applyMarkdownReadingColumn(isActive: Bool) {
        textView.textContainerInset = isActive
            ? NSSize(width: 32, height: 16)
            : NSSize(width: 4, height: 6)
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

        applyStatusBarColors()
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
        applyStatusBarColors()
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

    /// `line` 为源行语义（1-based）：无折叠上下文时直接对应 textView 当前内容的行；
    /// 折叠态下经 `visibleLineToSourceLine` 反查落到可见行——目标行若在某折叠区内
    /// （已被隐藏），floor 二分天然落到该区 openLine 对应的可见行。
    private func scrollToLine(_ line: Int) {
        if let composition = foldComposition {
            scrollToLine(line, in: composition)
            return
        }

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        let location = characterOffset(forLine: line, in: text)
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: lineRange)
        gutterView.needsDisplay = true
    }

    private func scrollToLine(_ line: Int, in composition: FoldComposition) {
        let text = composition.visibleText as NSString
        guard text.length > 0 else { return }

        let sourceLineIndex = max(line - 1, 0)
        let visibleLine = floorVisibleLineIndex(forSourceLine: sourceLineIndex, in: composition.visibleLineToSourceLine)
        let lineStarts = gutterView.foldDisplay?.lineStartLocations ?? PreviewDisplayMetadata.lineStartLocations(in: composition.visibleText)
        let start = visibleLine >= 0 && visibleLine < lineStarts.count ? lineStarts[visibleLine] : 0
        let lineRange = text.lineRange(for: NSRange(location: min(start, text.length), length: 0))
        textView.layoutManager?.ensureLayout(forCharacterRange: lineRange)
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: lineRange)
        gutterView.needsDisplay = true
    }

    private func scrollToOutlineItem(_ item: MarkdownOutlineItem) {
        let text = textView.string as NSString
        guard text.length > 0 else { return }
        let location = characterOffset(forLine: item.sourceLine, in: text)
        scrollToTopAligned(characterLocation: location)
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
        setActionButtonsEnabled(false)
        selectionActionButton.isHidden = true
        webViewSelectionLine = nil
        metaLabel.stringValue = ""
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        applyDisplayMetadata(.plain)
        applyEditorTheme(followsSystemAppearance: false, usesDarkModern: false)
        applyMarkdownReadingColumn(isActive: isMarkdownReadingColumnActive)
        clearMarkdownOutline()
        setStatusBarVisible(false)
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

    /// 6 个动作 button（4 copy + reveal + overflow）随文件加载状态统一启用/禁用；
    /// overflow 一并禁用，避免空态浮出 wrap 菜单。
    private func setActionButtonsEnabled(_ enabled: Bool) {
        [copyContentButton, copyNameButton, copyAbsPathButton, copyRelPathButton, revealButton, overflowButton].forEach {
            $0.isEnabled = enabled
        }
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

    // MARK: - Overflow menu (顶栏 ⋯：当前只 Wrap Lines，未来视图设置扩展点)

    private func configureOverflowMenu() {
        overflowMenu.delegate = self

        let wrapItem = NSMenuItem(title: "Wrap Lines", action: #selector(toggleWrap(_:)), keyEquivalent: "")
        wrapItem.target = self
        wrapItem.state = wrapsLines ? .on : .off
        overflowMenu.addItem(wrapItem)
        wrapLinesMenuItem = wrapItem
    }

    /// overflowMenu 弹出前刷新「Wrap Lines」勾选态（反映当前 wrapsLines）。
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === overflowMenu {
            wrapLinesMenuItem?.state = wrapsLines ? .on : .off
        }
    }

    private var hasRepoRootForActiveFile: Bool {
        guard let url = activeTab?.url else { return false }
        return RepoRoot.discover(from: url) != nil
    }

    @objc private func showOverflowMenu(_ sender: Any?) {
        overflowMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.height + 4), in: overflowButton)
    }

    @objc private func copyContentClicked(_ sender: Any?) {
        copyAllText()
    }

    @objc private func copyNameClicked(_ sender: Any?) {
        copyFileName()
    }

    @objc private func copyAbsPathClicked(_ sender: Any?) {
        copyAbsolutePath()
    }

    @objc private func copyRelPathClicked(_ sender: Any?) {
        copyRelativePath()
    }

    /// ① 复制全文：TextFileLoader 的原始文本，不是渲染后 attributed 文本。
    func copyAllText() {
        guard let document = activeTab?.document else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.text, forType: .string)
    }

    /// 复制文件名（不含路径）。
    func copyFileName() {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.lastPathComponent, forType: .string)
    }

    /// ② 复制绝对路径。
    func copyAbsolutePath() {
        guard let url = activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// ③ 复制相对 repo root 路径；无 repo 时静默不作为（button 本身已禁用）。
    func copyRelativePath() {
        guard let url = activeTab?.url, let root = RepoRoot.discover(from: url) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(relativePath(of: url, root: root), forType: .string)
    }

    /// 复制 path:line：markdown WebView 场景取 webViewSelectionLine（heuristic 匹配失败
    /// 降级为 1）；NSTextView 场景行号取当前选中文本首行，无选中时取可视区首个逻辑行。
    /// 由选区浮动按钮（T2/T3）调用。
    func copyPathLineReference() {
        guard let url = activeTab?.url else { return }
        let line = isMarkdownWebActive ? (webViewSelectionLine ?? 1) : currentReferenceLine()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(url.path):\(line)", forType: .string)
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
}
