import Darwin
import Foundation
import PeekyCore

/// 终端版唯一的有状态对象：事件循环、执行副作用、调度渲染。
///
/// 所有状态变化都经 `TUIReducer.reduce`；这里只负责把外部世界（键盘、终端尺寸、
/// 后台读文件的结果）变成 `TUIEvent`，以及把 `TUIEffect` 落到外部世界。
@MainActor
package final class TUIRuntime {
    private let terminal: TerminalIO
    private var state: TUIState
    private var parser = InputParser()
    private var lastFrame: CellBuffer?
    private var renderScheduled = false
    private var escapeFlushGeneration = 0
    private var sources: [DispatchSourceProtocol] = []
    private var watcher: DirectoryWatcher?
    /// 正在进行的搜索；发起新搜索时取消它。
    private var searchTask: Task<Void, Never>?
    /// 已经传给终端（或正在准备）的图片编号；退出时删掉，挂起回来后终端里已经没有了，清空重传。
    private var sentImages: Set<UInt32> = []
    /// 上一次按下鼠标的时间、位置与连击次数，用来认双击 / 三击。
    private var lastPress: (time: ContinuousClock.Instant, row: Int, column: Int, count: Int)?

    /// 两次按下间隔不超过这么久、位置相差不超过 1 格时算连击。
    private static let multiClickInterval = Duration.milliseconds(400)
    /// 提示显示多久。
    private static let toastDuration = DispatchTimeInterval.seconds(2)

    /// 孤立 ESC 等待后续字节的时间。
    private static let escapeTimeout = DispatchTimeInterval.milliseconds(30)

    /// 树根取版本库根；不在版本库里时取打开的目录，或文件所在的目录（与 app 一致）。
    package init(terminal: TerminalIO, request: OpenRequest) {
        self.terminal = terminal
        let target = request.url
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        let opensDirectory = exists && isDirectory.boolValue
        let repoRoot = RepoRoot.discover(from: target)
        let treeRoot = repoRoot ?? (opensDirectory ? target : target.deletingLastPathComponent())
        self.state = TUIState.launching(
            size: terminal.size,
            target: target,
            isDirectory: opensDirectory,
            displayPath: DisplayPath.make(for: target),
            treeRoot: treeRoot,
            targetLine: request.line,
            repoRoot: repoRoot
        )
    }

    /// 问终端背景色（OSC 11，回 `11;rgb:RRRR/GGGG/BBBB`）。
    static let backgroundQuery = "\u{1B}]11;?\u{1B}\\"
    /// 启动时问终端明暗：DSR 996（回 `CSI ? 997 ; 1|2 n`）与背景色；回复经输入解析送进 reducer。
    static let appearanceQueries = "\u{1B}[?996n" + backgroundQuery
    /// 启动时问显示图片要的三样：格子像素尺寸（`CSI 16 t`）、终端名（XTVERSION）、kitty 图片协议（`a=q`，
    /// 支持的终端回 `ESC _ G i=31;OK ESC \`）。
    static let imageQueries = "\u{1B}[16t\u{1B}[>0q\u{1B}_Gi=\(TUIReducer.graphicsProbeID),s=1,v=1,a=q,t=d,f=24;AAAA\u{1B}\\"
    /// 放大文字探测：在左上角打一个 2 倍空格（OSC 66）再问光标位置（CPR），随后清屏。
    /// 支持的终端光标到第 3 列；不认识 OSC 66 的终端忽略它，光标停在第 1 列。
    static let textSizingProbe = "\u{1B}[H\u{1B}]66;s=2; \u{07}\u{1B}[6n\u{1B}[2J\u{1B}[H"

    package func start() {
        terminal.enter()
        terminal.write(Self.textSizingProbe + Self.appearanceQueries + Self.imageQueries)
        installSources()
        render()
        dispatch(.launched)
        Task.detached(priority: .background) { HighlightService.shared.warmUp() }
    }

    // MARK: - 事件

    private func dispatch(_ event: TUIEvent) {
        let effects = TUIReducer.reduce(&state, event)
        scheduleRender()
        for effect in effects {
            perform(effect)
        }
    }

    private func perform(_ effect: TUIEffect) {
        switch effect {
        case .quit:
            DiagramRenderer.removeFiles()
            terminal.write(sentImages.map(ImagePlaceholder.deletion).joined())
            terminal.restore()
            exit(0)
        case .suspend:
            suspend()
        case let .load(url, generation, width, isReload, appearance, scaledHeadings, images):
            loadDocument(url: url, generation: generation, width: width, isReload: isReload, style: (appearance, scaledHeadings, images))
        case let .listDirectory(directory):
            Task.detached(priority: .userInitiated) { [weak self] in
                let listing = Self.list(directory)
                await self?.dispatch(.directoryListed(directory, listing))
            }
        case let .watch(root):
            watch(root: root)
        case let .checkFileStamp(url, generation):
            Task.detached(priority: .userInitiated) { [weak self] in
                let stamp = Self.stamp(of: url)
                await self?.dispatch(.fileStamp(stamp, generation: generation))
            }
        case let .startHighlight(generation, text, language):
            startHighlight(generation: generation, text: text, language: language)
        case let .highlightMarkdownCode(generation, source):
            highlightMarkdownCode(generation: generation, source: source)
        case let .layoutMarkdown(generation, source, width, codeTokens, appearance, scaledHeadings, images):
            Task.detached(priority: .userInitiated) { [weak self] in
                let rendering = MarkdownLayout.render(source, width: width, theme: .forAppearance(appearance), codeTokens: codeTokens, scaledHeadings: scaledHeadings, images: images)
                await self?.dispatch(.markdownLaidOut(rendering, generation: generation))
            }
        case let .open(target, baseDirectory):
            Self.openExternally(target: target, baseDirectory: baseDirectory)
        case let .copy(text, _):
            copyToClipboard(text)
        case let .copyFileText(url):
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let text = try? TextFileLoader.load(url: url).text else { return }
                await self?.copyToClipboard(text)
            }
        case let .reveal(url):
            Self.runOpen(["-R", url.path])
        case let .openInEditor(url):
            Self.runOpen(["-t", url.path])
        case .queryBackground:
            terminal.write(Self.backgroundQuery)
        case let .search(id, generation, query, corpus):
            search(id: id, generation: generation, query: query, corpus: corpus)
        case .loadRecentFiles:
            Task.detached(priority: .utility) { [weak self] in
                let items = Self.recentFileItems(RecentFiles.load())
                await self?.dispatch(.recentFilesLoaded(items))
            }
        case let .recordRecentFile(url):
            Task.detached(priority: .utility) { [weak self] in
                let items = Self.recentFileItems(RecentFiles.record(url))
                await self?.dispatch(.recentFilesLoaded(items))
            }
        case let .probeImages(paths, generation):
            Task.detached(priority: .utility) { [weak self] in
                var sizes: [String: PixelSize] = [:]
                for path in paths {
                    sizes[path] = ImageRasterizer.pixelSize(ofImageAt: path) ?? .unreadable
                }
                await self?.dispatch(.imagesProbed(sizes, generation: generation))
            }
        case let .renderDiagrams(sources, generation):
            renderDiagrams(sources, generation: generation)
        case let .discoverTreeRoot(url):
            Task.detached(priority: .userInitiated) { [weak self] in
                let repoRoot = RepoRoot.discover(from: url)
                let root = repoRoot ?? url.deletingLastPathComponent()
                await self?.dispatch(.treeRootDiscovered(root: root, repoRoot: repoRoot, file: url))
            }
        case let .expireToast(token):
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.toastDuration) { [weak self] in
                MainActor.assumeIsolated {
                    self?.dispatch(.toastExpired(token))
                }
            }
        }
    }

    /// 最近打开的显示条目：每条能否打开在这里现查磁盘。终端版打包在 app 里时 `UserDefaults.standard`
    /// 就是 app 的偏好域，与 app 共用一份记录。
    nonisolated private static func recentFileItems(_ entries: [RecentFiles.Entry]) -> [RecentFiles.Item] {
        RecentFiles.items(for: entries, pathExists: FileManager.default.fileExists(atPath:), homePath: NSHomeDirectory(), now: Date())
    }

    /// 写剪贴板：本机用 `pbcopy`；在 SSH 会话里或 pbcopy 失败时改用终端的 OSC 52。
    private func copyToClipboard(_ text: String) {
        if ProcessInfo.processInfo.environment["SSH_TTY"] == nil, Self.pbcopy(text) {
            return
        }
        terminal.write("\u{1B}]52;c;" + Data(text.utf8).base64EncodedString() + "\u{07}")
    }

    nonisolated private static func pbcopy(_ text: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// 逐块高亮 Markdown 代码块（只高亮 shiki 认得的语言），全部完成后一次送回。
    private func highlightMarkdownCode(generation: Int, source: String) {
        Task.detached(priority: .utility) { [weak self] in
            var tokens: [Int: [[HighlightedToken]]] = [:]
            for block in MarkdownLayout.codeBlocks(in: source) {
                guard let language = CodeFenceLanguage.shikiLanguage(for: block.language),
                      let lines = await HighlightService.shared.highlight(text: block.code, language: language)
                else { continue }
                tokens[block.index] = lines
            }
            guard !tokens.isEmpty else { return }
            await self?.dispatch(.markdownCodeHighlighted(tokens, generation: generation))
        }
    }

    /// 画 Mermaid 图的程序（与 peek-tui 同目录的 Peeky）；找不到时 Mermaid 块按代码显示。
    nonisolated private static let diagramRenderer = DiagramRenderer.executable(
        nextTo: DiagramRenderer.runningBinaryPath(),
        isExecutable: FileManager.default.isExecutableFile(atPath:)
    )

    /// 在后台请 app 把 Mermaid 源码画成 PNG，画好（或画不出）后一次送回。
    private func renderDiagrams(_ sources: [MarkdownDiagramSource], generation: Int) {
        guard let renderer = Self.diagramRenderer else { return }
        Task.detached(priority: .utility) { [weak self] in
            let images = await DiagramRenderer.render(sources, executable: renderer)
            await self?.dispatch(.diagramsRendered(images, generation: generation))
        }
    }

    /// 带 scheme 的地址原样交给 `open`；相对路径（去掉 `#…`）相对文档所在目录。
    nonisolated private static func runOpen(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    nonisolated private static func openExternally(target: String, baseDirectory: URL?) {
        let url: URL
        if let absolute = URL(string: target), let scheme = absolute.scheme, !scheme.isEmpty {
            url = absolute
        } else {
            let path = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            guard !path.isEmpty else { return }
            let decoded = path.removingPercentEncoding ?? path
            url = baseDirectory.map { $0.appendingPathComponent(decoded) } ?? URL(fileURLWithPath: decoded)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.isFileURL ? url.path : url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// 在后台按块搜索（`SearchEngine.chunks`），每块有结果就回主线程派发一批，最后一批标 `isComplete`；
    /// 匹配数到上限时提前结束。发起新搜索时取消旧的。
    private func search(id: Int, generation: Int, query: String, corpus: SearchCorpus) {
        searchTask?.cancel()
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let chunks = SearchEngine.chunks(of: corpus)
            var found = 0
            for (index, chunk) in chunks.enumerated() {
                guard !Task.isCancelled else { return }
                let matches = SearchEngine.matches(in: corpus, query: query, lines: chunk, limit: SearchEngine.maximumMatches - found)
                found += matches.count
                let isTruncated = found >= SearchEngine.maximumMatches
                let isComplete = isTruncated || index == chunks.count - 1
                if !matches.isEmpty || isComplete {
                    await self?.dispatch(.searchResults(matches, id: id, generation: generation, isComplete: isComplete, isTruncated: isTruncated))
                }
                if isTruncated { return }
            }
            if chunks.isEmpty {
                await self?.dispatch(.searchResults([], id: id, generation: generation, isComplete: true, isTruncated: false))
            }
        }
    }

    /// 高亮在后台任务里流式进行，每块结果回主线程派发；代际不符的块由 reducer 丢弃。
    private func startHighlight(generation: Int, text: String, language: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let stream = HighlightService.shared.highlightStream(text: text, language: language) else { return }
            for await chunk in stream {
                await self?.dispatch(.highlighted(chunk, generation: generation))
            }
        }
    }

    private func handleInput(_ bytes: [UInt8]) {
        for event in parser.feed(bytes) {
            dispatch(.input(countingClicks(event)))
        }
        escapeFlushGeneration += 1
        let generation = escapeFlushGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.escapeTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.escapeFlushGeneration == generation else { return }
                for event in self.parser.flushPendingEscape() {
                    self.dispatch(.input(event))
                }
            }
        }
    }

    /// 终端不报告连击：两次左键按下间隔短、位置几乎相同时累加次数（三击之后从头算）。
    private func countingClicks(_ event: InputEvent) -> InputEvent {
        guard case var .mouse(mouse) = event, case .press(.left) = mouse.kind else { return event }
        let now = ContinuousClock.now
        var count = 1
        if let last = lastPress, now - last.time <= Self.multiClickInterval,
           last.row == mouse.row, abs(last.column - mouse.column) <= 1, last.count < 3 {
            count = last.count + 1
        }
        lastPress = (now, mouse.row, mouse.column, count)
        mouse.clickCount = count
        return .mouse(mouse)
    }

    private func handleResize() {
        lastFrame = nil
        terminal.write("\u{1B}[2J")
        dispatch(.resized(terminal.size))
    }

    /// Ctrl-Z：还原终端交还给 shell；`fg` 回来后重新进入并整屏重画。
    private func suspend() {
        terminal.write(sentImages.map(ImagePlaceholder.deletion).joined())
        sentImages = []
        terminal.restore()
        signal(SIGTSTP, SIG_DFL)
        raise(SIGTSTP)
        terminal.enter()
        handleResize()
    }

    // MARK: - 外部输入源

    private func installSources() {
        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
                guard count > 0 else { return }
                self?.handleInput(Array(buffer[0..<count]))
            }
        }
        input.resume()
        sources.append(input)

        for signalNumber in [SIGWINCH, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if signalNumber == SIGWINCH {
                        self.handleResize()
                    } else {
                        DiagramRenderer.removeFiles()
                        self.terminal.restore()
                        exit(128 + signalNumber)
                    }
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    // MARK: - 文件树与监听

    nonisolated private static func list(_ directory: URL) -> DirectoryListing {
        guard let entries = try? DirectoryLister.list(dir: directory) else { return .unreadable }
        return .entries(entries.map(TreeEntry.init))
    }

    /// FSEvents 的回调已在主线程送达。
    private func watch(root: URL) {
        let watcher = DirectoryWatcher { [weak self] paths, mustScanSubDirectories in
            MainActor.assumeIsolated {
                self?.dispatch(.filesChanged(paths: paths, mustScanSubDirectories: mustScanSubDirectories))
            }
        }
        watcher.watch(root: root)
        self.watcher = watcher
    }

    /// 文件不存在时为 nil。直接读文件属性：`URL.resourceValues` 会把值缓存在 URL 实例上，
    /// 后台任务里没有 RunLoop 轮转来清缓存，同一个 URL 反复取会一直拿到旧值。
    nonisolated private static func stamp(of url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return FileStamp(size: size.int64Value, modifiedAt: attributes[.modificationDate] as? Date)
    }

    // MARK: - 读文件

    /// 读文件、格式化、切行在后台任务里做（不继承主线程隔离），结果分阶段回主线程派发。
    private func loadDocument(url: URL, generation: Int, width: Int, isReload: Bool, style: DocumentStyle) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let runtime = self
            await Self.loadStages(url: url, generation: generation, width: width, isReload: isReload, style: style) { event in
                await runtime?.dispatch(event)
            }
        }
    }

    /// Markdown 的排版条件：明暗、标题是否放大、显示图片的条件。
    typealias DocumentStyle = (appearance: PeekyPalette.Appearance, scaledHeadings: Bool, images: MarkdownImageContext?)

    /// 超过这个大小、又需要格式化的文件（JSON / JSONL / XML / plist）先显示原文，格式化好了再替换。
    nonisolated static let progressiveThreshold = 1 * 1024 * 1024

    /// 分阶段读入：① 大文件先送原文；② 送格式化后的文档；③ JSON 再送折叠与路径索引。
    /// 重读时跳过 ①：旧内容留在屏幕上，直到格式化后的新内容到达。
    nonisolated private static func loadStages(
        url: URL,
        generation: Int,
        width: Int,
        isReload: Bool,
        style: DocumentStyle,
        emit: @Sendable (TUIEvent) async -> Void
    ) async {
        var trace = PhaseTrace(url.lastPathComponent)
        let stamp = stamp(of: url)
        let loaded: LoadedText
        do {
            loaded = try TextFileLoader.load(url: url)
        } catch {
            await emit(.loadFailed("读不了 \(DisplayPath.make(for: url))：\(error.localizedDescription)", generation: generation))
            return
        }
        trace.mark("读文件")
        let modifiedAt = stamp?.modifiedAt
        let repoRoot = RepoRoot.discover(from: url.deletingLastPathComponent())

        let isProgressive = !isReload && loaded.kind.hasFormattedPreview && loaded.readBytes > progressiveThreshold
        if isProgressive {
            let interim = PreparedText(text: loaded.text, note: "Raw", presentation: .plain, isLargeFile: true)
            let header = DocumentHeaderBuilder.make(loaded: loaded, prepared: interim, modifiedAt: modifiedAt, repoRoot: repoRoot)
            let document = OpenedDocument(header: header, store: LineStore(loaded.text), presentation: .plain, prefersWrapping: false, formattingPending: true, stamp: stamp)
            await emit(.loaded(document, generation: generation))
            trace.mark("先显示原文")
        }

        let prepared = DocumentPreparer.prepare(loaded)
        trace.mark("格式化")
        let header = DocumentHeaderBuilder.make(loaded: loaded, prepared: prepared, modifiedAt: modifiedAt, repoRoot: repoRoot)
        let markdown = prepared.presentation == .markdown
            ? MarkdownLayout.render(prepared.text, width: width, theme: .forAppearance(style.appearance), scaledHeadings: style.scaledHeadings, images: style.images)
            : nil
        let store = LineStore(prepared.text)
        trace.mark("排版与切行")
        var document = OpenedDocument(
            header: header,
            store: store,
            presentation: prepared.presentation,
            prefersWrapping: !prepared.isLargeFile,
            markdown: markdown,
            baseDirectory: url.deletingLastPathComponent(),
            stamp: stamp
        )
        document.imageSizes = style.images?.sizes ?? [:]
        document.diagramImages = style.images?.diagrams ?? [:]
        guard prepared.presentation.isJSON else {
            await emit(.loaded(document, generation: generation))
            return
        }
        // 小文件带着索引一次送达；大文件先送着色文本，索引建好再补上
        if isProgressive {
            await emit(.loaded(document, generation: generation))
        }
        let view = jsonView(for: prepared)
        trace.mark("JSON 折叠与路径索引")
        if isProgressive {
            await emit(.jsonIndexed(view, generation: generation))
        } else {
            document.json = view
            await emit(.loaded(document, generation: generation))
        }
    }

    nonisolated private static func jsonView(for prepared: PreparedText) -> JSONView {
        if case let .json(structureIsValid) = prepared.presentation {
            return JSONView(prettyText: prepared.text, structureIsValid: structureIsValid)
        }
        return JSONView(prettyText: prepared.text, structureIsValid: true, invalidSourceLines: prepared.invalidLines)
    }

    // MARK: - 渲染

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.renderScheduled = false
                self?.render()
            }
        }
    }

    private func render() {
        let frame = FrameRenderer.render(state)
        let update = ScreenEncoder.encode(previous: lastFrame, next: frame)
        lastFrame = frame
        sendImages(frame.images)
        guard !update.isEmpty else { return }
        terminal.write("\u{1B}[?2026h" + update + "\u{1B}[?2026l")
    }

    private func writeToTerminal(_ text: String) {
        terminal.write(text)
    }

    /// 把这一帧里还没传过的图在后台画成 PNG，画好后传给终端（占位符已经在屏幕上，图一到就显示）。
    /// 画不出来的图也记为已传，不反复重试。
    private func sendImages(_ images: [TerminalImage]) {
        for image in images where !sentImages.contains(image.id) {
            sentImages.insert(image.id)
            Task.detached(priority: .utility) { [weak self] in
                guard let png = ImageRasterizer.png(for: image) else { return }
                let escape = ImagePlaceholder.transmission(id: image.id, png: png, columns: image.columns, rows: image.rows)
                await self?.writeToTerminal(escape)
            }
        }
    }
}
