import Foundation
import PeekyCore

package struct TerminalSize: Equatable, Sendable {
    package var columns: Int
    package var rows: Int

    package init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// 标题行内容：显示路径 + 详情（最后更改时间 · 类型 · 大小 · note）。
package struct DocumentHeader: Equatable, Sendable {
    package let displayPath: String
    package let details: String

    package init(displayPath: String, details: String) {
        self.displayPath = displayPath
        self.details = details
    }
}

/// 文件戳：大小 + 最后更改时间，两次读到的不同才重读文件（与 app 的判断一致）。
package struct FileStamp: Equatable, Sendable {
    package let size: Int64
    package let modifiedAt: Date?

    package init(size: Int64, modifiedAt: Date?) {
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// 重读前记下的位置（源行号），新内容到达后视口按它对回。
package struct ReloadAnchor: Equatable, Sendable {
    package let topSourceLine: Int
    package let cursorSourceLine: Int
    package let wrapsLines: Bool
    package let horizontalOffset: Int
}

/// 打开的文档：文本按行存、上色方式、已到达的高亮结果。
package struct OpenedDocument: Equatable, Sendable {
    package let header: DocumentHeader
    package let store: LineStore
    package let presentation: Presentation
    /// 大文件默认不换行（逐行折行计算的代价随行长增长）。
    package let prefersWrapping: Bool
    /// shiki 高亮结果，按逻辑行号存；未到达的行用默认前景色。
    package var highlights: [Int: [HighlightedToken]] = [:]
    /// Markdown 排好的屏幕行（按某个终端宽度）；终端宽度变化后在后台重排。
    package var markdown: MarkdownRendering?
    /// Markdown 代码块的高亮结果，按代码块序号存。
    package var markdownCodeTokens: [Int: [[HighlightedToken]]] = [:]
    /// 文档所在目录：相对链接据此解析。
    package let baseDirectory: URL?
    /// JSON / JSONL 的折叠与路径状态。
    package var json: JSONView?
    /// 大文件先显示的原文：格式化后的文档到达时整篇替换。
    package let formattingPending: Bool
    /// 读入时的文件戳；目录监听报告变化时与磁盘上的比较。
    package let stamp: FileStamp?

    package init(
        header: DocumentHeader,
        store: LineStore,
        presentation: Presentation,
        prefersWrapping: Bool = true,
        markdown: MarkdownRendering? = nil,
        baseDirectory: URL? = nil,
        json: JSONView? = nil,
        formattingPending: Bool = false,
        stamp: FileStamp? = nil
    ) {
        self.header = header
        self.store = store
        self.presentation = presentation
        self.prefersWrapping = prefersWrapping
        self.markdown = markdown
        self.baseDirectory = baseDirectory
        self.json = json
        self.formattingPending = formattingPending
        self.stamp = stamp
    }

    /// 后台还在做的事，显示在状态栏左侧；都做完时为 nil。
    package var progressNote: String? {
        if formattingPending { return "正在格式化…" }
        if presentation.isJSON, json == nil { return "正在建立折叠索引…" }
        return nil
    }

    /// 光标所在可视行对应源文件的第几行（0 起算）：Markdown 取排版行的来源行，其余即逻辑行。
    package func sourceLine(forLine line: Int) -> Int {
        if let json { return json.sourceLine(forDisplayLine: line) }
        guard let rows = markdown?.rows, !rows.isEmpty else { return line }
        return rows[min(max(line, 0), rows.count - 1)].sourceLine
    }

    /// 源文件第 `sourceLine` 行（0 起算）对应的可视行：Markdown 取第一个来源行不小于它的排版行。
    package func line(forSourceLine sourceLine: Int) -> Int {
        if let json { return json.displayLine(forSourceLine: sourceLine) }
        guard let rows = markdown?.rows, !rows.isEmpty else { return sourceLine }
        return rows.firstIndex { $0.sourceLine >= sourceLine } ?? rows.count - 1
    }
}

/// 一次搜索：搜索词、陆续到达的匹配（按文档顺序）、当前匹配。
package struct SearchState: Equatable, Sendable {
    package let query: String
    /// 每次发起搜索递增；迟到的结果与它不符时丢弃
    package let id: Int
    package var matches: [SearchMatch] = []
    package var isComplete = false
    /// 匹配太多，只记了前 `SearchEngine.maximumMatches` 段
    package var isTruncated = false
    /// 当前匹配在 `matches` 里的下标（指向一处匹配的第一段）
    package var current: Int?
    /// 回车后还没跳过去：结果到达时跳到第一个不早于这一行（搜索坐标）的匹配
    package var pendingJumpFrom: Int?

    package init(query: String, id: Int, pendingJumpFrom: Int? = nil) {
        self.query = query
        self.id = id
        self.pendingJumpFrom = pendingJumpFrom
    }

    /// 一处匹配算一个（不算续段）。
    package var matchCount: Int { matches.count(where: { !$0.isContinuation }) }

    /// 第一个落在 `line` 行或之后的匹配段的下标。
    package func firstIndex(onOrAfter line: Int) -> Int {
        var low = 0
        var high = matches.count
        while low < high {
            let middle = (low + high) / 2
            if matches[middle].line < line { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// 当前匹配的全部段（第一段加上紧跟的续段）。
    package var currentSegments: Range<Int>? {
        guard let current else { return nil }
        var end = current + 1
        while end < matches.count, matches[end].isContinuation { end += 1 }
        return current..<end
    }
}

package enum DocumentState: Equatable, Sendable {
    case loading(path: String)
    case loaded(OpenedDocument)
    case failed(message: String)
    /// 打开的是目录：正文提示从侧栏选文件
    case noFile(directory: String)
}

/// 正文里的一个可视行位置：第 `line` 个逻辑行折出来的第 `row` 行（都 0 起算）。
package struct ScrollPosition: Equatable, Comparable, Sendable {
    package var line: Int
    package var row: Int

    package init(line: Int, row: Int) {
        self.line = line
        self.row = row
    }

    package static func < (lhs: ScrollPosition, rhs: ScrollPosition) -> Bool {
        (lhs.line, lhs.row) < (rhs.line, rhs.row)
    }
}

/// 正文区的滚动状态：视口顶端的可视行、光标所在的逻辑行、不换行时的水平偏移。
///
/// 所有操作都接收 `rows`：某个逻辑行占几个可视行（换行关闭时恒为 1）。
/// 只在视口附近按需计算，不预先算全文的可视行总数，大文件也不卡。
package struct Viewport: Equatable, Sendable {
    package var top = ScrollPosition(line: 0, row: 0)
    package var cursor = 0
    package var horizontalOffset = 0

    package init(top: ScrollPosition = ScrollPosition(line: 0, row: 0), cursor: Int = 0, horizontalOffset: Int = 0) {
        self.top = top
        self.cursor = cursor
        self.horizontalOffset = horizontalOffset
    }

    /// 移动光标，视口滚到刚好完整露出光标行（光标行比视口还高时露出它的开头）。
    package mutating func moveCursor(to line: Int, lineCount: Int, height: Int, rows: (Int) -> Int) {
        cursor = Self.clamp(line, lineCount: lineCount)
        if cursor < top.line || (cursor == top.line && top.row > 0) {
            top = ScrollPosition(line: cursor, row: 0)
        } else {
            let before = Self.rowsBetween(top, andStartOf: cursor, rows: rows)
            if before + min(rows(cursor), height) > height {
                top = Self.topShowingEnd(of: cursor, height: height, rows: rows)
            }
        }
        top = Self.clampTop(top, lineCount: lineCount, height: height, rows: rows)
    }

    /// 视口按可视行滚动 `delta` 行，光标被夹回视口内。
    package mutating func scroll(by delta: Int, lineCount: Int, height: Int, rows: (Int) -> Int) {
        top = Self.advance(top, by: delta, lineCount: lineCount, rows: rows)
        top = Self.clampTop(top, lineCount: lineCount, height: height, rows: rows)
        let lastVisible = Self.advance(top, by: height - 1, lineCount: lineCount, rows: rows).line
        cursor = min(max(cursor, top.line), lastVisible)
    }

    /// 打开时跳到指定行：光标放在该行，该行落在视口上部三分之一处。
    package mutating func jump(to line: Int, lineCount: Int, height: Int, rows: (Int) -> Int) {
        cursor = Self.clamp(line, lineCount: lineCount)
        top = Self.advance(ScrollPosition(line: cursor, row: 0), by: -(height / 3), lineCount: lineCount, rows: rows)
        top = Self.clampTop(top, lineCount: lineCount, height: height, rows: rows)
    }

    /// 视口里从上到下每个屏幕行对应的可视行位置；文档结束后为 nil。
    package func visibleRows(lineCount: Int, height: Int, rows: (Int) -> Int) -> [ScrollPosition?] {
        var result: [ScrollPosition?] = []
        var position = top
        for index in 0..<height {
            guard position.line < lineCount else {
                result.append(nil)
                continue
            }
            result.append(position)
            if index == height - 1 { break }
            if position.row + 1 < rows(position.line) {
                position.row += 1
            } else {
                position = ScrollPosition(line: position.line + 1, row: 0)
            }
        }
        return result
    }

    // MARK: - 可视行运算

    static func clamp(_ line: Int, lineCount: Int) -> Int {
        min(max(line, 0), max(lineCount - 1, 0))
    }

    /// 从 `position` 起前进（或后退）`delta` 个可视行，停在文档首尾。
    static func advance(_ position: ScrollPosition, by delta: Int, lineCount: Int, rows: (Int) -> Int) -> ScrollPosition {
        var current = position
        var remaining = abs(delta)
        if delta > 0 {
            while remaining > 0 {
                let rowCount = rows(current.line)
                if current.row + 1 < rowCount {
                    let step = min(rowCount - 1 - current.row, remaining)
                    current.row += step
                    remaining -= step
                } else {
                    guard current.line + 1 < lineCount else { break }
                    current = ScrollPosition(line: current.line + 1, row: 0)
                    remaining -= 1
                }
            }
        } else {
            while remaining > 0 {
                if current.row > 0 {
                    let step = min(current.row, remaining)
                    current.row -= step
                    remaining -= step
                } else {
                    guard current.line > 0 else { break }
                    current = ScrollPosition(line: current.line - 1, row: rows(current.line - 1) - 1)
                    remaining -= 1
                }
            }
        }
        return current
    }

    /// `top` 到第 `line` 行开头之间有几个可视行。
    static func rowsBetween(_ top: ScrollPosition, andStartOf line: Int, rows: (Int) -> Int) -> Int {
        guard line > top.line else { return 0 }
        var count = rows(top.line) - top.row
        for index in (top.line + 1)..<line {
            count += rows(index)
        }
        return count
    }

    /// 让第 `line` 行的最后一个可视行正好落在视口底部时的视口顶端。
    static func topShowingEnd(of line: Int, height: Int, rows: (Int) -> Int) -> ScrollPosition {
        var remaining = height
        var current = line
        while current >= 0 {
            let rowCount = rows(current)
            if rowCount >= remaining {
                return ScrollPosition(line: current, row: rowCount - remaining)
            }
            remaining -= rowCount
            current -= 1
        }
        return ScrollPosition(line: 0, row: 0)
    }

    /// 视口顶端不越过「最后一行贴底」的位置。
    static func clampTop(_ top: ScrollPosition, lineCount: Int, height: Int, rows: (Int) -> Int) -> ScrollPosition {
        guard lineCount > 0 else { return ScrollPosition(line: 0, row: 0) }
        let maxTop = topShowingEnd(of: lineCount - 1, height: height, rows: rows)
        return min(max(top, ScrollPosition(line: 0, row: 0)), maxTop)
    }
}

/// 打开的一个文件（一个标签页）：各自的文档、视口、换行开关与读入代际，切换时原样保留。
package struct OpenTab: Equatable, Sendable {
    /// 文件；只在测试里构造不带文件的文档时为 nil
    package var url: URL?
    package var document: DocumentState
    package var viewport = Viewport()
    package var wrapsLines = true
    /// 打开时带的行号（1 起算），文档读入后应用一次。
    package var targetLine: Int?
    /// 这个文件最近一次读入的代际；迟到的异步结果代际不符时丢弃。
    package var generation: Int
    /// 正在重读：新内容到达后视口按它对回。
    package var reloadAnchor: ReloadAnchor?

    package init(url: URL?, document: DocumentState, targetLine: Int? = nil, generation: Int) {
        self.url = url
        self.document = document
        self.targetLine = targetLine
        self.generation = generation
    }
}

package struct TUIState: Equatable, Sendable {
    package var size: TerminalSize
    /// 打开的文件，按打开顺序；没有打开文件时为空（正文显示 `emptyDocument`）。
    package var tabs: [OpenTab] = []
    /// 当前文件在 `tabs` 里的下标；没有打开文件时为 nil。
    package var activeTabIndex: Int?
    /// 没有打开文件时正文显示的内容（打开的是目录、文件全关掉了）。
    package var emptyDocument: DocumentState = .noFile(directory: "")
    /// 已经发出过的最大代际：每次读文件取一个新的，各个文件的代际互不相同。
    package var lastGeneration = 0
    /// 状态栏左侧的一次性提示（如「已复制 jq 路径」），下一次按键时清除。
    package var toast: String?
    /// 侧栏；没有文件树时为 nil（只显示正文）。
    package var sidebar: SidebarState?
    package var focus: FocusArea = .content
    /// 鼠标选中的文字；换文档、折叠变化、Markdown 重排时清掉。
    package var selection: TextSelection?
    /// 在正文里按下了鼠标、还没松开：拖动扩展选区。
    package var isSelecting = false
    /// 文件树所在的版本库根；不在版本库里时为 nil（P 复制相对路径用）。
    package var repoRoot: URL?
    package var isHelpVisible = false
    /// `:` 之后输入的行号；不在输入时为 nil。
    package var lineInput: String?
    /// `/` 之后输入的搜索词；不在输入时为 nil。
    package var searchInput: String?
    /// 最近一次搜索；Esc 清掉。换文档、重读、Markdown 重排后用同一个词重搜。
    package var search: SearchState?
    /// 发起过几次搜索（搜索的代际）。
    package var searchCount = 0
    /// 每设一次提示加一；过期计时带着它，后来的提示不会被前一个计时清掉。
    package var toastToken = 0
    /// 终端的明暗；收到 OSC 11 背景色或 DSR 996 回复之前按深色。
    package var appearance: PeekyPalette.Appearance = .dark
    /// 已经按 OSC 11 背景色定过明暗（之后 996 / 2031 的回复只触发再问一次背景色）。
    package var appearanceFromBackground = false
    /// 终端支持 kitty 文字尺寸协议（OSC 66）：Markdown 的 H1 / H2 画成放大文字。启动探测之前为 false。
    package var supportsTextSizing = false
    /// 最近打开的文件（与 app 共用的记录），启动时与每次记一笔之后由运行时送来。
    package var recentFiles: [RecentFiles.Item] = []

    /// 打开一个文档（测试用）：`.noFile` 不算打开了文件。
    package init(size: TerminalSize, document: DocumentState, targetLine: Int? = nil) {
        self.size = size
        if case .noFile = document {
            emptyDocument = document
        } else {
            tabs = [OpenTab(url: nil, document: document, targetLine: targetLine, generation: 0)]
            activeTabIndex = 0
        }
    }

    /// 启动时的状态：树根已知；终端够宽或打开的是目录时显示侧栏，打开目录时焦点在侧栏。
    package static func launching(
        size: TerminalSize,
        target: URL,
        isDirectory: Bool,
        displayPath: String,
        treeRoot: URL,
        targetLine: Int?,
        repoRoot: URL? = nil
    ) -> TUIState {
        var state = TUIState(
            size: size,
            document: isDirectory ? .noFile(directory: displayPath) : .loading(path: displayPath),
            targetLine: targetLine
        )
        state.sidebar = SidebarState(
            tree: FileTree(root: treeRoot),
            isVisible: isDirectory || size.columns >= SidebarState.autoShowColumns
        )
        state.focus = isDirectory ? .sidebar : .content
        state.emptyDocument = .noFile(directory: isDirectory ? displayPath : treeRoot.lastPathComponent)
        if !isDirectory { state.tabs[0].url = target }
        state.repoRoot = repoRoot
        return state
    }

    // MARK: - 当前文件

    package var activeTab: OpenTab? {
        activeTabIndex.map { tabs[$0] }
    }

    /// 正文显示的文件；没有打开文件时为 nil。没有标签页时设它会新开一个（测试用）。
    package var activeFile: URL? {
        get { activeTab?.url }
        set {
            if let index = activeTabIndex {
                tabs[index].url = newValue
            } else if let newValue {
                tabs = [OpenTab(url: newValue, document: emptyDocument, generation: lastGeneration)]
                activeTabIndex = 0
            }
        }
    }

    package var document: DocumentState {
        get { activeTab?.document ?? emptyDocument }
        set {
            if let index = activeTabIndex { tabs[index].document = newValue } else { emptyDocument = newValue }
        }
    }

    package var viewport: Viewport {
        get { activeTab?.viewport ?? Viewport() }
        set { if let index = activeTabIndex { tabs[index].viewport = newValue } }
    }

    package var wrapsLines: Bool {
        get { activeTab?.wrapsLines ?? true }
        set { if let index = activeTabIndex { tabs[index].wrapsLines = newValue } }
    }

    package var targetLine: Int? {
        get { activeTab?.targetLine }
        set { if let index = activeTabIndex { tabs[index].targetLine = newValue } }
    }

    package var reloadAnchor: ReloadAnchor? {
        get { activeTab?.reloadAnchor }
        set { if let index = activeTabIndex { tabs[index].reloadAnchor = newValue } }
    }

    /// 当前文件的读入代际；没有打开文件时是最近发出的代际。
    package var generation: Int {
        get { activeTab?.generation ?? lastGeneration }
        set { if let index = activeTabIndex { tabs[index].generation = newValue } }
    }

    /// 给当前文件取一个新的读入代际（之前发出的异步结果从此作废）。
    package mutating func advanceGeneration() {
        lastGeneration += 1
        generation = lastGeneration
    }

    /// 正文区高度：终端行数减去标题行与状态栏。
    package var contentHeight: Int { max(size.rows - 2, 1) }

    /// 侧栏宽度（不含分隔线）；侧栏收起时为 0。
    package var sidebarWidth: Int {
        guard let sidebar, sidebar.isVisible else { return 0 }
        return SidebarState.width(forColumns: size.columns)
    }

    /// 正文区从第几列开始：侧栏 + 1 列分隔线。
    package var contentOrigin: Int { sidebarWidth == 0 ? 0 : sidebarWidth + 1 }

    package var contentColumns: Int { max(size.columns - contentOrigin, 1) }

    /// Open 页签的行：打开的文件，之后是「Recent」小标题与此刻没有打开的最近文件（没有就不显示小标题）。
    package var openListRows: [OpenListRow] {
        let openPaths = Set(tabs.compactMap { $0.url?.standardizedFileURL.path })
        let recents = recentFiles.filter { !openPaths.contains($0.path) }
        let tabRows = tabs.indices.map(OpenListRow.tab)
        guard !recents.isEmpty else { return tabRows }
        return tabRows + [.recentHeader] + recents.map(OpenListRow.recent)
    }

    /// 侧栏实际显示的页签：选了 Contents 但当前文档没有大纲时显示 Files。
    package var sidebarTab: SidebarTab {
        guard let sidebar else { return .files }
        if sidebar.preferredTab == .contents, outline.isEmpty { return .files }
        return sidebar.preferredTab
    }

    /// 当前文档的大纲（只有排好版的 Markdown 有）。
    package var outline: [MarkdownOutlineEntry] {
        guard case let .loaded(opened) = document else { return [] }
        return opened.markdown?.outline ?? []
    }
}
