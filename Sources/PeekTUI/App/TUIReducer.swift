import Foundation
import PeekyCore

package enum TUIEvent: Equatable, Sendable {
    /// 界面已进入：读文件、列目录、开始监听
    case launched
    case input(InputEvent)
    case resized(TerminalSize)
    case loaded(OpenedDocument, generation: Int)
    case loadFailed(String, generation: Int)
    case highlighted(HighlightChunk, generation: Int)
    case markdownLaidOut(MarkdownRendering, generation: Int)
    case markdownCodeHighlighted([Int: [[HighlightedToken]]], generation: Int)
    /// JSON 折叠与路径索引建好：行内容不变，视口保持原位
    case jsonIndexed(JSONView, generation: Int)
    case directoryListed(URL, DirectoryListing)
    /// 目录监听报告的变化（FSEvents 的目录路径）
    case filesChanged(paths: [String], mustScanSubDirectories: Bool)
    /// 当前文件此刻的文件戳；文件不存在时为 nil
    case fileStamp(FileStamp?, generation: Int)
    /// 提示到时间了；令牌不是最新提示的就不清
    case toastExpired(Int)
    /// 一批搜索结果（按文档顺序）；`isComplete` 时是最后一批
    case searchResults([SearchMatch], id: Int, generation: Int, isComplete: Bool, isTruncated: Bool)
    /// 最近打开的文件（与 app 共用的记录，每条能否打开已现查磁盘）
    case recentFilesLoaded([RecentFiles.Item])
    /// 当前文件不在文件树下时找到的新树根；`repoRoot` 是它所在的版本库根
    case treeRootDiscovered(root: URL, repoRoot: URL?, file: URL)
    /// Markdown 里本地图片的像素尺寸（读不了的是 `PixelSize.unreadable`）
    case imagesProbed([String: PixelSize], generation: Int)
}

/// reducer 产出的副作用，由 `TUIRuntime` 执行。
package enum TUIEffect: Equatable, Sendable {
    case quit
    /// Ctrl-Z：把终端交还给 shell，`fg` 后回来
    case suspend
    /// 读文件，结果以 `.loaded` / `.loadFailed` 送回；重读时不先显示原文
    case load(url: URL, generation: Int, width: Int, isReload: Bool, appearance: PeekyPalette.Appearance, scaledHeadings: Bool = false, images: MarkdownImageContext? = nil)
    /// 用 shiki 高亮全文，结果以 `.highlighted` 分块送回
    case startHighlight(generation: Int, text: String, language: String)
    /// 逐块高亮 Markdown 里的代码块，结果以 `.markdownCodeHighlighted` 送回
    case highlightMarkdownCode(generation: Int, source: String)
    /// 按新宽度 / 新明暗重排 Markdown，结果以 `.markdownLaidOut` 送回
    case layoutMarkdown(generation: Int, source: String, width: Int, codeTokens: [Int: [[HighlightedToken]]], appearance: PeekyPalette.Appearance, scaledHeadings: Bool = false, images: MarkdownImageContext? = nil)
    /// 用系统默认程序打开链接：带 scheme 的原样打开，相对路径相对文档所在目录
    case open(target: String, baseDirectory: URL?)
    /// 写入系统剪贴板；`description` 用于状态栏提示
    case copy(text: String, description: String)
    /// 列举目录的直接子项，结果以 `.directoryListed` 送回
    case listDirectory(URL)
    /// 监听树根下的磁盘变化，结果以 `.filesChanged` 送回
    case watch(root: URL)
    /// 读当前文件的文件戳，结果以 `.fileStamp` 送回
    case checkFileStamp(URL, generation: Int)
    /// 从磁盘读原文写进剪贴板（与 app 的「复制全文」一致，不是格式化后的文本）
    case copyFileText(URL)
    /// 在 Finder 中显示（`open -R`）
    case reveal(URL)
    /// 用默认编辑器打开（`open -t`）
    case openInEditor(URL)
    /// 2 秒后送回 `.toastExpired`
    case expireToast(Int)
    /// 再问一次终端背景色（OSC 11），回复以 `.input(.backgroundColor)` 送回
    case queryBackground
    /// 在后台搜索，结果以 `.searchResults` 分批送回；发起新搜索时旧的停掉
    case search(id: Int, generation: Int, query: String, corpus: SearchCorpus)
    /// 读最近打开的文件，结果以 `.recentFilesLoaded` 送回
    case loadRecentFiles
    /// 把文件记进最近打开（与 app 共用），之后以 `.recentFilesLoaded` 送回新列表
    case recordRecentFile(URL)
    /// 找文件所在的版本库根作为新树根，结果以 `.treeRootDiscovered` 送回
    case discoverTreeRoot(URL)
    /// 读本地图片的像素尺寸，结果以 `.imagesProbed` 送回
    case probeImages(paths: [String], generation: Int)
}

/// 纯函数：根据事件更新状态，返回要执行的副作用。
package enum TUIReducer {
    /// 滚轮一格滚动的行数。
    static let wheelStep = 3
    /// 不换行时左右滚动一次的列数。
    static let horizontalStep = 8

    package static func reduce(_ state: inout TUIState, _ event: TUIEvent) -> [TUIEffect] {
        switch event {
        case .launched:
            return launch(&state)
        case let .loaded(document, generation):
            guard generation == state.generation else { return [] }
            // 文件第一次读进来（不是重读）时记进最近打开，与 app 一致
            var record: [TUIEffect] = []
            if case .loading = state.document, let file = state.activeFile { record = [.recordRecentFile(file)] }
            return documentLoaded(document, state: &state) + record
        case let .loadFailed(message, generation):
            guard generation == state.generation else { return [] }
            state.document = .failed(message: message)
            return []
        case let .markdownLaidOut(rendering, generation):
            guard generation == state.generation, case var .loaded(document) = state.document else { return [] }
            let cursorSource = document.sourceLine(forLine: state.viewport.cursor)
            let topSource = document.sourceLine(forLine: state.viewport.top.line)
            document.markdown = rendering
            state.document = .loaded(document)
            state.selection = nil
            state.viewport.top = ScrollPosition(line: document.line(forSourceLine: topSource), row: 0)
            withLayout(&state) { viewport, layout, height in
                viewport.moveCursor(to: document.line(forSourceLine: cursorSource), lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
            return rerunSearch(&state) + probeImagesIfNeeded(&state)
        case let .jsonIndexed(view, generation):
            guard generation == state.generation, case var .loaded(document) = state.document else { return [] }
            document.json = view
            state.document = .loaded(document)
            return []
        case let .markdownCodeHighlighted(tokens, generation):
            guard generation == state.generation, case var .loaded(document) = state.document else { return [] }
            document.markdownCodeTokens = tokens
            state.document = .loaded(document)
            return [.layoutMarkdown(generation: generation, source: document.store.text, width: state.contentColumns, codeTokens: tokens, appearance: state.appearance, scaledHeadings: state.supportsTextSizing, images: imageContext(state, document: document))]
        case let .highlighted(chunk, generation):
            guard generation == state.generation, case var .loaded(document) = state.document else { return [] }
            for (offset, line) in chunk.lines.enumerated() {
                document.highlights[chunk.firstLine + offset] = line
            }
            state.document = .loaded(document)
            return []
        case let .resized(size):
            state.size = size
            return contentWidthChanged(&state)
        case let .directoryListed(directory, listing):
            directoryListed(directory, listing, state: &state)
            return []
        case let .filesChanged(paths, mustScanSubDirectories):
            return filesChanged(paths: paths, mustScanSubDirectories: mustScanSubDirectories, state: &state)
        case let .fileStamp(stamp, generation):
            guard generation == state.generation else { return [] }
            switch state.document {
            case let .loaded(document) where document.stamp != stamp:
                return reload(&state)
            case .failed where stamp != nil:
                return reload(&state)
            default:
                return []
            }
        case let .toastExpired(token):
            if token == state.toastToken { state.toast = nil }
            return []
        case let .recentFilesLoaded(items):
            recentFilesLoaded(items, state: &state)
            return []
        case let .treeRootDiscovered(root, repoRoot, file):
            return treeRootDiscovered(root: root, repoRoot: repoRoot, file: file, state: &state)
        case let .imagesProbed(sizes, generation):
            guard generation == state.generation, case var .loaded(document) = state.document else { return [] }
            document.imageSizes.merge(sizes) { _, new in new }
            state.document = .loaded(document)
            return relayoutMarkdownIfNeeded(state)
        case let .searchResults(matches, id, generation, isComplete, isTruncated):
            guard generation == state.generation else { return [] }
            return searchResultsArrived(matches, id: id, isComplete: isComplete, isTruncated: isTruncated, state: &state)
        case let .input(.paste(text)):
            pasteIntoSearchInput(text, state: &state)
            return []
        case let .input(.key(rawPress)):
            let press = normalized(rawPress)
            state.toast = nil
            if state.isHelpVisible { return handleHelpKey(&state) }
            if let input = state.lineInput { return handleLineInput(press, input: input, state: &state) }
            if let input = state.searchInput { return handleSearchInput(press, input: input, state: &state) }
            if let effects = handleGlobalKey(press, state: &state) { return effects }
            if let effects = handleActionKey(press, state: &state) { return effects }
            if let effects = handleSearchKey(press, state: &state) { return effects }
            return state.focus == .sidebar ? handleSidebarKey(press, state: &state) : handleKey(press, state: &state)
        case let .input(.mouse(mouse)):
            if case .press = mouse.kind { state.toast = nil }
            return routeMouse(mouse, state: &state)
        case let .input(.colorScheme(isDark)):
            // 终端的 996 / 2031 可能跟着系统明暗而不是它自己的配色：知道背景色时以背景为准，再问一次背景
            guard !state.appearanceFromBackground else { return [.queryBackground] }
            return setAppearance(isDark ? .dark : .light, state: &state)
        case let .input(.backgroundColor(red, green, blue)):
            state.appearanceFromBackground = true
            return setAppearance(appearance(ofBackground: red, green, blue), state: &state)
        case let .input(.terminalName(name)):
            return terminalReported(&state) { $0.terminalName = name }
        case let .input(.cellPixelSize(width, height)):
            return terminalReported(&state) { $0.cellPixelSize = PixelSize(width: width, height: height) }
        case let .input(.graphicsReply(id, message)):
            guard id == graphicsProbeID else { return [] }
            return terminalReported(&state) { $0.graphicsReady = message == "OK" }
        case let .input(.cursorPosition(_, column)):
            // 只在启动探测时问光标位置：第 1 列打的 2 倍空格让光标到了第 3 列，说明支持放大文字
            state.supportsTextSizing = column == textSizingProbeColumn
            return relayoutMarkdownIfNeeded(state)
        case .input:
            return []
        }
    }

    // MARK: - 明暗与放大标题

    /// 放大文字探测：在第 1 列打一个 2 倍空格后，支持的终端把光标推到第 3 列。
    static let textSizingProbeColumn = 3

    /// 按背景亮度判断明暗（Rec. 709 亮度，过半为浅色）。
    static func appearance(ofBackground red: Int, _ green: Int, _ blue: Int) -> PeekyPalette.Appearance {
        let luminance = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        return luminance > 127.5 ? .light : .dark
    }

    private static func setAppearance(_ appearance: PeekyPalette.Appearance, state: inout TUIState) -> [TUIEffect] {
        guard appearance != state.appearance else { return [] }
        state.appearance = appearance
        return relayoutMarkdownIfNeeded(state)
    }

    /// Markdown 的排版宽度、明暗、标题放大方式或图片条件与当前不同时重排。
    static func relayoutMarkdownIfNeeded(_ state: TUIState) -> [TUIEffect] {
        guard case let .loaded(document) = state.document, let rendering = document.markdown else { return [] }
        let images = imageContext(state, document: document)
        guard rendering.width != state.contentColumns
                || rendering.appearance != state.appearance
                || rendering.scaledHeadings != state.supportsTextSizing
                || rendering.imageContext != images
        else { return [] }
        return [.layoutMarkdown(
            generation: state.generation,
            source: document.store.text,
            width: state.contentColumns,
            codeTokens: document.markdownCodeTokens,
            appearance: state.appearance,
            scaledHeadings: state.supportsTextSizing,
            images: images
        )]
    }

    // MARK: - 图片

    /// kitty 图片协议探测用的图片编号（`a=q` 不真的存图）。
    static let graphicsProbeID = 31

    /// 排版时显示图片的条件：终端能显示图片时才有，带上这个文档已读到的图片尺寸。
    static func imageContext(_ state: TUIState, document: OpenedDocument) -> MarkdownImageContext? {
        guard state.supportsImages, let cell = state.cellPixelSize else { return nil }
        return MarkdownImageContext(cell: cell, sizes: document.imageSizes, baseDirectory: document.baseDirectory)
    }

    /// 读入时的图片条件（文档还没读进来，图片尺寸沿用 `sizes`）。
    static func imageContext(_ state: TUIState, file: URL, sizes: [String: PixelSize] = [:]) -> MarkdownImageContext? {
        guard state.supportsImages, let cell = state.cellPixelSize else { return nil }
        return MarkdownImageContext(cell: cell, sizes: sizes, baseDirectory: file.deletingLastPathComponent())
    }

    /// 排版里出现了还没读尺寸的本地图片：请运行时去读。
    static func probeImagesIfNeeded(_ state: inout TUIState) -> [TUIEffect] {
        guard state.supportsImages, case var .loaded(document) = state.document, let rendering = document.markdown else { return [] }
        let missing = rendering.imageSources.filter { document.imageSizes[$0] == nil && !document.requestedImages.contains($0) }
        guard !missing.isEmpty else { return [] }
        document.requestedImages.formUnion(missing)
        state.document = .loaded(document)
        return [.probeImages(paths: missing, generation: state.generation)]
    }

    /// 终端名、格子像素尺寸、图片协议探测的回复到了：能显示图片与否变了就重排 Markdown。
    private static func terminalReported(_ state: inout TUIState, _ update: (inout TUIState) -> Void) -> [TUIEffect] {
        update(&state)
        return relayoutMarkdownIfNeeded(state)
    }

    // MARK: - 打开与重读

    private static func launch(_ state: inout TUIState) -> [TUIEffect] {
        var effects: [TUIEffect] = [.loadRecentFiles]
        if let file = state.activeFile {
            effects.append(.load(url: file, generation: state.generation, width: state.contentColumns, isReload: false, appearance: state.appearance, scaledHeadings: state.supportsTextSizing, images: imageContext(state, file: file)))
        }
        guard var sidebar = state.sidebar else { return effects }
        let directories = state.activeFile.map { sidebar.tree.reveal($0) } ?? [sidebar.tree.root]
        sidebar.selectedPath = state.activeFile?.standardizedFileURL.path
        state.sidebar = sidebar
        effects += directories.map { .listDirectory($0) }
        effects.append(.watch(root: sidebar.tree.root))
        return effects
    }

    /// 重读当前文件：记下视口顶端与光标的源行，新内容到达后对回去。
    /// 读取失败（文件被删）时保留上一次记下的位置，文件再出现时回到那里。
    static func reload(_ state: inout TUIState) -> [TUIEffect] {
        guard let file = state.activeFile else { return [] }
        var imageSizes: [String: PixelSize] = [:]
        if case let .loaded(document) = state.document {
            imageSizes = document.imageSizes
            state.reloadAnchor = ReloadAnchor(
                topSourceLine: document.sourceLine(forLine: state.viewport.top.line),
                cursorSourceLine: document.sourceLine(forLine: state.viewport.cursor),
                wrapsLines: state.wrapsLines,
                horizontalOffset: state.viewport.horizontalOffset
            )
        }
        state.advanceGeneration()
        return [.load(url: file, generation: state.generation, width: state.contentColumns, isReload: true, appearance: state.appearance, scaledHeadings: state.supportsTextSizing, images: imageContext(state, file: file, sizes: imageSizes))]
    }

    private static func documentLoaded(_ document: OpenedDocument, state: inout TUIState) -> [TUIEffect] {
        state.document = .loaded(document)
        state.selection = nil
        state.isSelecting = false
        if let anchor = state.reloadAnchor, !document.formattingPending {
            state.reloadAnchor = nil
            restore(anchor, document: document, state: &state)
        } else {
            state.viewport = Viewport()
            state.wrapsLines = document.prefersWrapping
            state.sidebar?.outlineSelection = 0
            state.sidebar?.outlineTop = 0
            // 目标行指格式化后的行号，原文阶段先不跳
            if let target = state.targetLine, !document.formattingPending {
                withLayout(&state) { viewport, layout, height in
                    viewport.jump(to: document.line(forSourceLine: target - 1), lineCount: layout.lineCount, height: height, rows: layout.rows)
                }
                state.targetLine = nil
            }
        }
        // 读文件期间明暗变了时按新明暗重排；有搜索词时在新内容里重搜
        let relayout = relayoutMarkdownIfNeeded(state) + rerunSearch(&state) + probeImagesIfNeeded(&state)
        switch document.presentation {
        case let .source(language):
            return [.startHighlight(generation: state.generation, text: document.store.text, language: language)]
        case .markdown:
            return relayout + [.highlightMarkdownCode(generation: state.generation, source: document.store.text)]
        default:
            return relayout
        }
    }

    /// 视口顶端与光标按源行对回；文件变短时钳到最后一行。
    private static func restore(_ anchor: ReloadAnchor, document: OpenedDocument, state: inout TUIState) {
        let lastSourceLine = max(document.store.count - 1, 0)
        state.wrapsLines = anchor.wrapsLines
        state.viewport = Viewport(
            top: ScrollPosition(line: document.line(forSourceLine: min(anchor.topSourceLine, lastSourceLine)), row: 0),
            horizontalOffset: anchor.horizontalOffset
        )
        withLayout(&state) { viewport, layout, height in
            viewport.top = Viewport.clampTop(viewport.top, lineCount: layout.lineCount, height: height, rows: layout.rows)
            viewport.moveCursor(
                to: document.line(forSourceLine: min(anchor.cursorSourceLine, lastSourceLine)),
                lineCount: layout.lineCount,
                height: height,
                rows: layout.rows
            )
        }
    }

    // MARK: - 布局

    /// 在当前文档的排版参数下修改视口；文档未读入时什么也不做。
    static func withLayout(_ state: inout TUIState, _ body: (inout Viewport, DocumentLayout, Int) -> Void) {
        guard case let .loaded(document) = state.document else { return }
        let layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines, appearance: state.appearance)
        body(&state.viewport, layout, state.contentHeight)
    }

    /// 终端尺寸或侧栏显隐改变了正文宽度：光标留在视口里，Markdown 按新宽度重排。
    static func contentWidthChanged(_ state: inout TUIState) -> [TUIEffect] {
        withLayout(&state) { viewport, layout, height in
            viewport.moveCursor(to: viewport.cursor, lineCount: layout.lineCount, height: height, rows: layout.rows)
        }
        keepSidebarSelectionVisible(&state)
        return relayoutMarkdownIfNeeded(state)
    }

    // MARK: - 按键

    /// 终端对符号与大写字母的上报有的带 shift、有的不带，统一去掉 shift。
    private static func normalized(_ press: KeyPress) -> KeyPress {
        guard case .character = press.key, press.modifiers == .shift else { return press }
        return KeyPress(key: press.key)
    }

    /// 不论焦点在哪都生效的键；不是这些键时返回 nil。
    private static func handleGlobalKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect]? {
        switch (press.key, press.modifiers) {
        case (.character("q"), []), (.character("c"), .control):
            return [.quit]
        case (.character("z"), .control):
            return [.suspend]
        case (.tab, []):
            return toggleFocus(&state)
        case (.character("s"), []):
            return toggleSidebar(&state)
        case (.character("1"), []):
            return showSidebarTab(.open, state: &state)
        case (.character("2"), []):
            return showSidebarTab(.files, state: &state)
        case (.character("3"), []):
            return showSidebarTab(.contents, state: &state)
        case (.character("["), []):
            return cycleTab(by: -1, state: &state)
        case (.character("]"), []):
            return cycleTab(by: 1, state: &state)
        case (.character("x"), []):
            return closeFileKey(&state)
        case (.character("r"), []):
            return reload(&state)
        case (.character("?"), []):
            state.isHelpVisible = true
            return []
        case (.character(":"), []):
            guard case .loaded = state.document else { return [] }
            state.lineInput = ""
            return []
        case (.character("/"), []):
            guard case .loaded = state.document else { return [] }
            state.searchInput = ""
            return []
        default:
            return nil
        }
    }

    private static func handleKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect] {
        switch (press.key, press.modifiers) {
        case (.character("w"), []):
            state.wrapsLines.toggle()
            state.viewport.horizontalOffset = 0
            state.viewport.top.row = 0
            withLayout(&state) { viewport, layout, height in
                viewport.moveCursor(to: viewport.cursor, lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
            return []
        case (.character("h"), []), (.left, []):
            if !state.wrapsLines {
                state.viewport.horizontalOffset = max(state.viewport.horizontalOffset - horizontalStep, 0)
            }
            return []
        case (.character("l"), []), (.right, []):
            if !state.wrapsLines {
                state.viewport.horizontalOffset += horizontalStep
            }
            return []
        case (.escape, []):
            if state.selection != nil {
                state.selection = nil
            } else {
                state.search = nil
            }
            return []
        case (.enter, []):
            if toggleFold(atDisplayLine: state.viewport.cursor, state: &state) { return [] }
            return activateLink(state: &state)
        case (.character("M"), []):
            changeFolds(state: &state) { json, text in json.collapseAll(sourceText: text) }
            return []
        case (.character("R"), []):
            changeFolds(state: &state) { json, _ in json.expandAll() }
            return []
        case (.character("J"), []):
            return copyPath(state: &state, dot: false)
        case (.character("D"), []):
            return copyPath(state: &state, dot: true)
        default:
            break
        }
        withLayout(&state) { viewport, layout, height in
            moveByKey(press, viewport: &viewport, lineCount: layout.lineCount, height: height, rows: layout.rows)
        }
        return []
    }

    /// 折叠 / 展开以该显示行开头的 JSON 容器；该行不是容器开头时返回 false。
    private static func toggleFold(atDisplayLine line: Int, state: inout TUIState) -> Bool {
        guard case let .loaded(document) = state.document, let json = document.json else { return false }
        let source = json.sourceLine(forDisplayLine: line)
        guard json.region(openingAt: source) != nil else { return false }
        changeFolds(state: &state) { json, text in _ = json.toggle(sourceLine: source, sourceText: text) }
        return true
    }

    /// 改变折叠状态，并让视口顶端与光标按源行对回（光标所在的源行被折起时落到折叠行上）。
    private static func changeFolds(state: inout TUIState, _ change: (inout JSONView, String) -> Void) {
        guard case var .loaded(document) = state.document, var json = document.json else { return }
        let cursorSource = json.sourceLine(forDisplayLine: state.viewport.cursor)
        let topSource = json.sourceLine(forDisplayLine: state.viewport.top.line)
        change(&json, document.store.text)
        document.json = json
        state.document = .loaded(document)
        state.selection = nil
        state.viewport.top = ScrollPosition(line: json.displayLine(forSourceLine: topSource), row: 0)
        withLayout(&state) { viewport, layout, height in
            viewport.moveCursor(to: json.displayLine(forSourceLine: cursorSource), lineCount: layout.lineCount, height: height, rows: layout.rows)
        }
    }

    /// J / D：复制光标行的 jq 表达式 / 点分路径。
    private static func copyPath(state: inout TUIState, dot: Bool) -> [TUIEffect] {
        guard case let .loaded(document) = state.document, let json = document.json,
              let paths = json.paths(forSourceLine: json.sourceLine(forDisplayLine: state.viewport.cursor))
        else { return [] }
        let description = dot ? "点分路径" : "jq 路径"
        let toast = showToast(dot ? "已复制点分路径" : "已复制 jq 路径", state: &state)
        return [.copy(text: dot ? paths.dot : paths.jq, description: description), toast]
    }

    /// 点在 JSON 行号栏的折叠三角那一列上时，返回该行的显示行号（坐标相对正文区）。
    private static func foldMarkerLine(at mouse: MouseEvent, state: TUIState) -> Int? {
        guard case let .loaded(document) = state.document, document.json != nil else { return nil }
        let layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines)
        let markerColumn = layout.gutterWidth - 2
        guard mouse.column == markerColumn || mouse.column == markerColumn - 1 else { return nil }
        let contentRow = mouse.row - 1
        guard contentRow >= 0, contentRow < state.contentHeight else { return nil }
        let positions = state.viewport.visibleRows(lineCount: layout.lineCount, height: state.contentHeight, rows: layout.rows)
        guard let position = positions[contentRow], position.row == 0, layout.foldMarker(position.line) != nil else { return nil }
        return position.line
    }

    /// 回车：打开光标行上的第一个链接。文档内锚点（`#…`）跳到对应标题，其余交给系统打开。
    private static func activateLink(state: inout TUIState) -> [TUIEffect] {
        guard case let .loaded(document) = state.document, let rows = document.markdown?.rows,
              state.viewport.cursor < rows.count, let target = rows[state.viewport.cursor].links.first
        else { return [] }
        guard target.hasPrefix("#") else {
            return [.open(target: target, baseDirectory: document.baseDirectory)]
        }
        let fragment = String(target.dropFirst())
        let anchor = (fragment.removingPercentEncoding ?? fragment).lowercased()
        if let row = rows.firstIndex(where: { $0.anchor == anchor }) {
            withLayout(&state) { viewport, layout, height in
                viewport.moveCursor(to: row, lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
        }
        return []
    }

    private static func moveByKey(_ press: KeyPress, viewport: inout Viewport, lineCount: Int, height: Int, rows: (Int) -> Int) {
        let cursor = viewport.cursor
        switch (press.key, press.modifiers) {
        case (.character("j"), []), (.down, []):
            viewport.moveCursor(to: cursor + 1, lineCount: lineCount, height: height, rows: rows)
        case (.character("k"), []), (.up, []):
            viewport.moveCursor(to: cursor - 1, lineCount: lineCount, height: height, rows: rows)
        case (.character(" "), []), (.character("f"), []), (.pageDown, []):
            viewport.scroll(by: height, lineCount: lineCount, height: height, rows: rows)
            viewport.moveCursor(to: max(viewport.cursor, cursor + height), lineCount: lineCount, height: height, rows: rows)
        case (.character("b"), []), (.pageUp, []):
            viewport.scroll(by: -height, lineCount: lineCount, height: height, rows: rows)
            viewport.moveCursor(to: min(viewport.cursor, cursor - height), lineCount: lineCount, height: height, rows: rows)
        case (.character("d"), .control):
            viewport.scroll(by: height / 2, lineCount: lineCount, height: height, rows: rows)
            viewport.moveCursor(to: max(viewport.cursor, cursor + height / 2), lineCount: lineCount, height: height, rows: rows)
        case (.character("u"), .control):
            viewport.scroll(by: -(height / 2), lineCount: lineCount, height: height, rows: rows)
            viewport.moveCursor(to: min(viewport.cursor, cursor - height / 2), lineCount: lineCount, height: height, rows: rows)
        case (.character("e"), .control):
            viewport.scroll(by: 1, lineCount: lineCount, height: height, rows: rows)
        case (.character("y"), .control):
            viewport.scroll(by: -1, lineCount: lineCount, height: height, rows: rows)
        case (.character("g"), []), (.home, []):
            viewport.moveCursor(to: 0, lineCount: lineCount, height: height, rows: rows)
        case (.character("G"), []), (.end, []):
            viewport.moveCursor(to: lineCount - 1, lineCount: lineCount, height: height, rows: rows)
        default:
            break
        }
    }

    // MARK: - 鼠标

    /// 侧栏范围内的鼠标交给侧栏；其余换算成正文区坐标交给正文。按下鼠标时焦点跟到那一块。
    /// 在正文里按下后的拖动与松开一律交给正文（拖出正文区也在扩展选区）。
    private static func routeMouse(_ mouse: MouseEvent, state: inout TUIState) -> [TUIEffect] {
        if state.isHelpVisible {
            if case .press = mouse.kind { state.isHelpVisible = false }
            return []
        }
        let sidebarWidth = state.sidebarWidth
        let inBodyRows = mouse.row >= 1 && mouse.row < state.size.rows - 1
        let continuesSelection: Bool
        switch mouse.kind {
        case .drag, .release: continuesSelection = state.isSelecting
        default: continuesSelection = false
        }
        if !continuesSelection, sidebarWidth > 0, inBodyRows, mouse.column < sidebarWidth {
            return handleSidebarMouse(mouse, state: &state)
        }
        if !continuesSelection, sidebarWidth > 0, mouse.column == sidebarWidth { return [] }
        if case .press = mouse.kind { state.focus = .content }
        var local = mouse
        local.column = max(mouse.column - state.contentOrigin, 0)
        handleContentMouse(local, state: &state)
        return []
    }

    private static func handleContentMouse(_ mouse: MouseEvent, state: inout TUIState) {
        if case .press(.left) = mouse.kind, let line = foldMarkerLine(at: mouse, state: state) {
            _ = toggleFold(atDisplayLine: line, state: &state)
            return
        }
        switch mouse.kind {
        case .drag(.left), .release(.left):
            updateSelection(mouse, state: &state)
            return
        case .press(.left):
            guard mouse.row >= 1, mouse.row <= state.contentHeight else { return }
            updateSelection(mouse, state: &state)
        default:
            break
        }
        withLayout(&state) { viewport, layout, height in
            switch mouse.kind {
            case .scrollDown:
                viewport.scroll(by: wheelStep, lineCount: layout.lineCount, height: height, rows: layout.rows)
            case .scrollUp:
                viewport.scroll(by: -wheelStep, lineCount: layout.lineCount, height: height, rows: layout.rows)
            case .press(.left):
                let contentRow = mouse.row - 1
                guard contentRow >= 0, contentRow < height else { return }
                let positions = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows)
                if let position = positions[contentRow] {
                    viewport.moveCursor(to: position.line, lineCount: layout.lineCount, height: height, rows: layout.rows)
                }
            default:
                break
            }
        }
    }
}
