import Foundation
import PeekyCore

/// 侧栏相关的状态变化：文件树、大纲、焦点与显隐。
extension TUIReducer {
    static let outlineUnavailableToast = "这个文件没有大纲"

    // MARK: - 文件树数据

    static func directoryListed(_ directory: URL, _ listing: DirectoryListing, state: inout TUIState) {
        guard var sidebar = state.sidebar else { return }
        sidebar.tree.setListing(listing, for: directory)
        if sidebar.selectedPath == nil, let first = sidebar.tree.rows().first(where: { $0.entry != nil })?.entry {
            sidebar.selectedPath = first.path
        }
        state.sidebar = sidebar
        keepSidebarSelectionVisible(&state)
    }

    /// 只重新列举已展开的目录；当前文件所在目录变了时再查一次文件戳。
    static func filesChanged(paths: [String], mustScanSubDirectories: Bool, state: inout TUIState) -> [TUIEffect] {
        guard let sidebar = state.sidebar else { return [] }
        let scope = FileTreeRefresh.scope(
            changedPaths: paths,
            mustScanSubDirectories: mustScanSubDirectories,
            loadedDirectories: sidebar.tree.loadedDirectories,
            activeFileURL: state.activeFile
        )
        var effects = scope.directoriesToReload.map { TUIEffect.listDirectory($0) }
        if scope.touchesActiveFile, let file = state.activeFile {
            effects.append(.checkFileStamp(file, generation: state.generation))
        }
        return effects
    }

    // MARK: - 焦点、显隐、页签

    /// Tab：焦点在正文与侧栏之间切换；侧栏收起时先显示出来。
    static func toggleFocus(_ state: inout TUIState) -> [TUIEffect] {
        guard state.sidebar != nil else { return [] }
        if state.focus == .sidebar {
            state.focus = .content
            return []
        }
        let effects = setSidebarVisible(true, state: &state)
        focusSidebar(&state)
        return effects
    }

    /// s：显示 / 收起侧栏；收起时焦点回到正文。
    static func toggleSidebar(_ state: inout TUIState) -> [TUIEffect] {
        guard let sidebar = state.sidebar else { return [] }
        if sidebar.isVisible { state.focus = .content }
        return setSidebarVisible(!sidebar.isVisible, state: &state)
    }

    /// 1 / 2：切到 Files / Contents 并把焦点给侧栏；没有大纲的文档不能切到 Contents。
    static func showSidebarTab(_ tab: SidebarTab, state: inout TUIState) -> [TUIEffect] {
        guard state.sidebar != nil else { return [] }
        if tab == .contents, state.outline.isEmpty {
            return [showToast(outlineUnavailableToast, state: &state)]
        }
        state.sidebar?.preferredTab = tab
        let effects = setSidebarVisible(true, state: &state)
        focusSidebar(&state)
        return effects
    }

    private static func setSidebarVisible(_ isVisible: Bool, state: inout TUIState) -> [TUIEffect] {
        guard state.sidebar?.isVisible != isVisible else { return [] }
        state.sidebar?.isVisible = isVisible
        return contentWidthChanged(&state)
    }

    /// 焦点进侧栏；在大纲里时选中光标所在的那一节。
    private static func focusSidebar(_ state: inout TUIState) {
        state.focus = .sidebar
        if state.sidebarTab == .contents {
            let current = currentOutlineIndex(state)
            state.sidebar?.outlineSelection = current
        }
        keepSidebarSelectionVisible(&state)
    }

    /// 光标所在的那一节：标题行不晚于光标的最后一个大纲项。
    private static func currentOutlineIndex(_ state: TUIState) -> Int {
        state.outline.lastIndex { $0.row <= state.viewport.cursor } ?? 0
    }

    /// 列表高度：正文区高度减去页签行。
    static func sidebarListHeight(_ state: TUIState) -> Int {
        max(state.contentHeight - SidebarState.headerRows, 1)
    }

    static func keepSidebarSelectionVisible(_ state: inout TUIState) {
        guard var sidebar = state.sidebar else { return }
        let height = sidebarListHeight(state)
        let rows = sidebar.tree.rows()
        if let index = rows.firstIndex(where: { $0.entry?.path == sidebar.selectedPath }) {
            sidebar.treeTop = SidebarState.top(showing: index, currentTop: sidebar.treeTop, height: height)
        }
        sidebar.treeTop = min(sidebar.treeTop, max(rows.count - height, 0))
        let outline = state.outline
        sidebar.outlineSelection = min(sidebar.outlineSelection, max(outline.count - 1, 0))
        sidebar.outlineTop = SidebarState.top(showing: sidebar.outlineSelection, currentTop: sidebar.outlineTop, height: height)
        sidebar.outlineTop = min(sidebar.outlineTop, max(outline.count - height, 0))
        state.sidebar = sidebar
    }

    // MARK: - 侧栏按键

    static func handleSidebarKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect] {
        if case .escape = press.key {
            state.focus = .content
            return []
        }
        let count = state.sidebarTab == .files ? selectableTreeRows(state).count : state.outline.count
        if let target = movedIndex(press, current: selectionIndex(state), count: count, height: sidebarListHeight(state)) {
            select(index: target, state: &state)
            return []
        }
        switch state.sidebarTab {
        case .files:
            return handleTreeKey(press, state: &state)
        case .contents:
            return handleOutlineKey(press, state: &state)
        }
    }

    /// 方向键与翻页键移到的列表下标；不是移动键时返回 nil。
    private static func movedIndex(_ press: KeyPress, current: Int, count: Int, height: Int) -> Int? {
        guard count > 0 else { return nil }
        let target: Int
        switch (press.key, press.modifiers) {
        case (.character("j"), []), (.down, []):
            target = current + 1
        case (.character("k"), []), (.up, []):
            target = current - 1
        case (.character(" "), []), (.character("f"), []), (.pageDown, []):
            target = current + height
        case (.character("b"), []), (.pageUp, []):
            target = current - height
        case (.character("d"), .control):
            target = current + height / 2
        case (.character("u"), .control):
            target = current - height / 2
        case (.character("g"), []), (.home, []):
            target = 0
        case (.character("G"), []), (.end, []):
            target = count - 1
        default:
            return nil
        }
        return min(max(target, 0), count - 1)
    }

    /// 文件树里能选中的行（「(无法读取)」占位不能选）。
    private static func selectableTreeRows(_ state: TUIState) -> [TreeRow] {
        state.sidebar?.tree.rows().filter { $0.entry != nil } ?? []
    }

    /// 当前选中项在列表里的下标。
    private static func selectionIndex(_ state: TUIState) -> Int {
        guard let sidebar = state.sidebar else { return 0 }
        switch state.sidebarTab {
        case .files:
            return selectableTreeRows(state).firstIndex { $0.entry?.path == sidebar.selectedPath } ?? 0
        case .contents:
            return sidebar.outlineSelection
        }
    }

    private static func select(index: Int, state: inout TUIState) {
        switch state.sidebarTab {
        case .files:
            let rows = selectableTreeRows(state)
            guard rows.indices.contains(index) else { return }
            state.sidebar?.selectedPath = rows[index].entry?.path
        case .contents:
            state.sidebar?.outlineSelection = index
        }
        keepSidebarSelectionVisible(&state)
    }

    private static func handleTreeKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect] {
        let rows = selectableTreeRows(state)
        let index = selectionIndex(state)
        guard rows.indices.contains(index), let entry = rows[index].entry else { return [] }
        switch (press.key, press.modifiers) {
        case (.enter, []):
            if entry.isDirectory { return toggleDirectory(entry, state: &state) }
            let effects = openFile(entry.url, state: &state)
            state.focus = .content
            return effects
        case (.character("l"), []), (.right, []):
            guard entry.isDirectory else { return openFile(entry.url, state: &state) }
            if state.sidebar?.tree.isExpanded(entry.path) == true {
                select(index: index + 1, state: &state)
                return []
            }
            return toggleDirectory(entry, state: &state)
        case (.character("h"), []), (.left, []):
            if entry.isDirectory, state.sidebar?.tree.isExpanded(entry.path) == true {
                return toggleDirectory(entry, state: &state)
            }
            if let parent = rows[index].ancestors.last {
                state.sidebar?.selectedPath = parent
                keepSidebarSelectionVisible(&state)
            }
            return []
        default:
            return []
        }
    }

    /// 展开 / 收起目录；展开时重新列举（与 app 一致，展开时总拿最新的磁盘内容）。
    private static func toggleDirectory(_ entry: TreeEntry, state: inout TUIState) -> [TUIEffect] {
        guard var sidebar = state.sidebar else { return [] }
        let willExpand = !sidebar.tree.isExpanded(entry.path)
        sidebar.tree.setExpanded(entry.path, willExpand)
        state.sidebar = sidebar
        keepSidebarSelectionVisible(&state)
        return willExpand ? [.listDirectory(entry.url)] : []
    }

    private static func handleOutlineKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect] {
        switch (press.key, press.modifiers) {
        case (.enter, []):
            jumpToOutlineSelection(&state)
            state.focus = .content
        case (.character("l"), []), (.right, []):
            jumpToOutlineSelection(&state)
        default:
            break
        }
        return []
    }

    /// 跳到选中的标题：标题所在的排版行放到视口顶端，光标落在它上面。
    private static func jumpToOutlineSelection(_ state: inout TUIState) {
        guard let sidebar = state.sidebar, state.outline.indices.contains(sidebar.outlineSelection) else { return }
        let row = state.outline[sidebar.outlineSelection].row
        withLayout(&state) { viewport, layout, height in
            viewport.cursor = Viewport.clamp(row, lineCount: layout.lineCount)
            viewport.top = Viewport.clampTop(ScrollPosition(line: viewport.cursor, row: 0), lineCount: layout.lineCount, height: height, rows: layout.rows)
        }
    }

    // MARK: - 侧栏鼠标

    /// 页签行点页签名切换；列表里点一项：目录展开 / 收起，文件打开，大纲项跳过去。焦点留在侧栏。
    static func handleSidebarMouse(_ mouse: MouseEvent, state: inout TUIState) -> [TUIEffect] {
        switch mouse.kind {
        case .scrollUp, .scrollDown:
            scrollSidebar(by: mouse.kind == .scrollDown ? wheelStep : -wheelStep, state: &state)
            return []
        case .press(.left):
            break
        default:
            return []
        }
        state.focus = .sidebar
        if mouse.row == 1 {
            guard let tab = SidebarRenderer.tab(atColumn: mouse.column) else { return [] }
            return showSidebarTab(tab, state: &state)
        }
        guard let sidebar = state.sidebar else { return [] }
        let listRow = mouse.row - 1 - SidebarState.headerRows
        switch state.sidebarTab {
        case .files:
            let rows = sidebar.tree.rows()
            let index = sidebar.treeTop + listRow
            guard rows.indices.contains(index), let entry = rows[index].entry else { return [] }
            state.sidebar?.selectedPath = entry.path
            if entry.isDirectory { return toggleDirectory(entry, state: &state) }
            return openFile(entry.url, state: &state)
        case .contents:
            let index = sidebar.outlineTop + listRow
            guard state.outline.indices.contains(index) else { return [] }
            state.sidebar?.outlineSelection = index
            jumpToOutlineSelection(&state)
            return []
        }
    }

    private static func scrollSidebar(by delta: Int, state: inout TUIState) {
        guard var sidebar = state.sidebar else { return }
        let height = sidebarListHeight(state)
        switch state.sidebarTab {
        case .files:
            sidebar.treeTop = min(max(sidebar.treeTop + delta, 0), max(sidebar.tree.rows().count - height, 0))
        case .contents:
            sidebar.outlineTop = min(max(sidebar.outlineTop + delta, 0), max(state.outline.count - height, 0))
        }
        state.sidebar = sidebar
    }
}
