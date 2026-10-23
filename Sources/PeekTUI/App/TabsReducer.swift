import Foundation
import PeekyCore

/// 多个打开的文件：打开、切换、关闭，最近打开的记录，文件树跟随当前文件。
///
/// 只有当前文件接收后台结果：切走的文件迟到的结果代际不符被丢掉，切回来时由 `refreshActiveTab`
/// 补做（没读完的重读，源码高亮、Markdown 代码块高亮与重排重新发起）并查一次文件戳。
extension TUIReducer {
    // MARK: - 打开、切换、关闭

    /// 打开文件：已经开着就切过去，否则在末尾新开一个并读入（与 app 的标签页一致）。
    static func openFile(_ url: URL, state: inout TUIState) -> [TUIEffect] {
        let path = url.standardizedFileURL.path
        if let index = state.tabs.firstIndex(where: { $0.url?.standardizedFileURL.path == path }) {
            return activateTab(index, state: &state)
        }
        state.tabs.append(OpenTab(url: url, document: .loading(path: url.lastPathComponent), generation: state.lastGeneration))
        return activateTab(state.tabs.count - 1, state: &state)
    }

    /// 切到第 `index` 个文件；已经是当前文件时什么也不做。选区清掉，侧栏的大纲回到开头、Open 列表选中它，
    /// 文件树定位到它；有搜索词时在它里面重搜。
    static func activateTab(_ index: Int, state: inout TUIState) -> [TUIEffect] {
        guard state.tabs.indices.contains(index), state.activeTabIndex != index else { return [] }
        state.activeTabIndex = index
        state.selection = nil
        state.isSelecting = false
        state.sidebar?.outlineSelection = 0
        state.sidebar?.outlineTop = 0
        state.sidebar?.openSelection = index
        var effects = refreshActiveTab(&state)
        effects += followInTree(&state)
        effects += rerunSearch(&state)
        keepSidebarSelectionVisible(&state)
        return effects
    }

    /// 当前文件补做切走期间被丢掉的后台工作：没读完的（读取中、只显示了原文、JSON 索引未到）重读；
    /// 读完的查一次文件戳，源码高亮不全时重新高亮，Markdown 按当前宽度与明暗重排、补上代码块高亮。
    /// 正文宽度可能已经变了，光标留在视口里。
    static func refreshActiveTab(_ state: inout TUIState) -> [TUIEffect] {
        guard let url = state.activeFile else { return [] }
        switch state.document {
        case .loading:
            state.advanceGeneration()
            return [.load(url: url, generation: state.generation, width: state.contentColumns, isReload: false, appearance: state.appearance, scaledHeadings: state.supportsTextSizing, images: imageContext(state, file: url))]
        case .failed:
            return reload(&state)
        case .noFile:
            return []
        case let .loaded(document):
            if document.formattingPending || (document.presentation.isJSON && document.json == nil) {
                return reload(&state)
            }
            withLayout(&state) { viewport, layout, height in
                viewport.moveCursor(to: viewport.cursor, lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
            var effects: [TUIEffect] = [.checkFileStamp(url, generation: state.generation)]
            switch document.presentation {
            case let .source(language) where document.highlights.count < document.store.count:
                effects.append(.startHighlight(generation: state.generation, text: document.store.text, language: language))
            case .markdown:
                effects += relayoutMarkdownIfNeeded(state)
                // 切走期间画好的 Mermaid 图因代际不符被丢掉了：没拿到结果的重新画
                if case var .loaded(refreshed) = state.document {
                    refreshed.requestedDiagrams = []
                    state.document = .loaded(refreshed)
                }
                effects += renderDiagramsIfNeeded(&state)
                if document.markdownCodeTokens.isEmpty {
                    effects.append(.highlightMarkdownCode(generation: state.generation, source: document.store.text))
                }
            default:
                break
            }
            return effects
        }
    }

    /// 关掉第 `index` 个文件：关的是当前文件时切到它右边的（没有就左边的）；全关掉后正文回到空白页。
    static func closeTab(_ index: Int, state: inout TUIState) -> [TUIEffect] {
        guard state.tabs.indices.contains(index), let active = state.activeTabIndex else { return [] }
        state.tabs.remove(at: index)
        if state.tabs.isEmpty {
            state.activeTabIndex = nil
            state.selection = nil
            state.isSelecting = false
            keepSidebarSelectionVisible(&state)
            return []
        }
        if index != active {
            if index < active { state.activeTabIndex = active - 1 }
            keepSidebarSelectionVisible(&state)
            return []
        }
        state.activeTabIndex = nil
        return activateTab(min(index, state.tabs.count - 1), state: &state)
    }

    /// `[` / `]`：切到上一个 / 下一个打开的文件，到头从另一端继续。
    static func cycleTab(by delta: Int, state: inout TUIState) -> [TUIEffect] {
        guard let active = state.activeTabIndex, state.tabs.count > 1 else { return [] }
        let count = state.tabs.count
        return activateTab(((active + delta) % count + count) % count, state: &state)
    }

    /// `x`：侧栏 Open 页里关掉选中的文件，其余时候关掉当前文件。
    static func closeFileKey(_ state: inout TUIState) -> [TUIEffect] {
        if state.focus == .sidebar, state.sidebarTab == .open, let sidebar = state.sidebar {
            let rows = state.openListRows
            guard rows.indices.contains(sidebar.openSelection), case let .tab(index) = rows[sidebar.openSelection] else { return [] }
            return closeTab(index, state: &state)
        }
        guard let active = state.activeTabIndex else { return [] }
        return closeTab(active, state: &state)
    }

    // MARK: - 文件树跟随

    /// 文件树定位到当前文件：在树根下时展开到它并选中（只列还没列过的目录）；不在树根下时按它换树根。
    static func followInTree(_ state: inout TUIState) -> [TUIEffect] {
        guard var sidebar = state.sidebar, let url = state.activeFile else { return [] }
        guard sidebar.tree.contains(url) else { return [.discoverTreeRoot(url)] }
        let directories = sidebar.tree.reveal(url).filter { !sidebar.tree.isListed($0) }
        sidebar.selectedPath = url.standardizedFileURL.path
        state.sidebar = sidebar
        return directories.map { .listDirectory($0) }
    }

    /// 新树根找到了（当前文件所在的版本库根，不在版本库里时是它所在的目录）：重建文件树、
    /// 展开到当前文件并开始监听新树根；在此期间已经切到别的文件时不换。
    static func treeRootDiscovered(root: URL, repoRoot: URL?, file: URL, state: inout TUIState) -> [TUIEffect] {
        guard var sidebar = state.sidebar, state.activeFile?.standardizedFileURL.path == file.standardizedFileURL.path else { return [] }
        sidebar.tree = FileTree(root: root)
        sidebar.treeTop = 0
        let directories = sidebar.tree.reveal(file)
        sidebar.selectedPath = file.standardizedFileURL.path
        state.sidebar = sidebar
        state.repoRoot = repoRoot
        state.emptyDocument = .noFile(directory: root.lastPathComponent)
        keepSidebarSelectionVisible(&state)
        return directories.map { .listDirectory($0) } + [.watch(root: root)]
    }

    // MARK: - 最近打开

    static func recentFilesLoaded(_ items: [RecentFiles.Item], state: inout TUIState) {
        state.recentFiles = items
        keepSidebarSelectionVisible(&state)
    }
}
