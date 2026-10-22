import Foundation
import PeekyCore

/// 纯函数：把侧栏画进一帧的左侧（第 1 行到状态栏上一行），右侧一列画分隔线。
///
/// 第 1 行是页签；Open 列出打开的文件（当前文件加粗并用强调色，后面是变淡的所在目录），之后是
/// 「Recent」小标题与最近打开的文件（打不开的变淡并写原因）。文件树每层缩进 2 列，祖先的导轨画在
/// 祖先自己的三角那一列，选中项所在分支那一列加亮；当前打开的文件加粗并用强调色。大纲按标题级别缩进，
/// 1–2 级加粗、3–4 级变淡。
enum SidebarRenderer {
    static let openLabel = "Open"
    static let filesLabel = "Files"
    static let contentsLabel = "Contents"
    static let recentLabel = "Recent"
    /// 页签名在页签行里的列范围（左边距 1 列，页签之间空 2 列）。
    static let openColumns = 1..<(1 + openLabel.count)
    static let filesColumns = (openColumns.upperBound + 2)..<(openColumns.upperBound + 2 + filesLabel.count)
    static let contentsColumns = (filesColumns.upperBound + 2)..<(filesColumns.upperBound + 2 + contentsLabel.count)

    static func tab(atColumn column: Int) -> SidebarTab? {
        if openColumns.contains(column) { return .open }
        if filesColumns.contains(column) { return .files }
        if contentsColumns.contains(column) { return .contents }
        return nil
    }

    static func draw(_ frame: inout CellBuffer, state: TUIState, sidebar: SidebarState, width: Int) {
        let lastRow = frame.rows - 2
        guard lastRow >= 1 else { return }
        let chrome = ChromeColors.forAppearance(state.appearance)
        let separator = CellStyle(foreground: TerminalPalette.color(.treeIndentGuide, appearance: state.appearance))
        for row in 1...lastRow {
            frame.fill(row: row, from: 0, to: width, style: .plain)
            frame.write("│", row: row, column: width, style: separator)
        }
        drawTabs(&frame, state: state, width: width)
        let height = TUIReducer.sidebarListHeight(state)
        let selectionBackground = state.focus == .sidebar ? chrome.listFocusedSelection : chrome.listUnfocusedSelection
        switch state.sidebarTab {
        case .open:
            drawOpenList(&frame, state: state, sidebar: sidebar, width: width, height: height, selectionBackground: selectionBackground)
        case .files:
            drawTree(&frame, state: state, sidebar: sidebar, width: width, height: height, selectionBackground: selectionBackground)
        case .contents:
            drawOutline(&frame, state: state, sidebar: sidebar, width: width, height: height, selectionBackground: selectionBackground)
        }
    }

    private static func drawTabs(_ frame: inout CellBuffer, state: TUIState, width: Int) {
        let active = state.sidebarTab
        let contentsAvailable = !state.outline.isEmpty
        func style(for tab: SidebarTab) -> CellStyle {
            if tab == active {
                return CellStyle(foreground: state.focus == .sidebar ? ChromeColors.forAppearance(state.appearance).accent : .default, bold: true, underline: true)
            }
            return CellStyle(dim: tab == .contents && !contentsAvailable)
        }
        frame.write(openLabel, row: 1, column: openColumns.lowerBound, style: style(for: .open), limit: width)
        frame.write(filesLabel, row: 1, column: filesColumns.lowerBound, style: style(for: .files), limit: width)
        frame.write(contentsLabel, row: 1, column: contentsColumns.lowerBound, style: style(for: .contents), limit: width)
    }

    private static func drawTree(_ frame: inout CellBuffer, state: TUIState, sidebar: SidebarState, width: Int, height: Int, selectionBackground: TerminalColor) {
        let rows = sidebar.tree.rows()
        let selected = rows.first { $0.entry?.path == sidebar.selectedPath }
        let branch = SidebarState.activeBranch(of: selected)
        let activePath = state.activeFile?.standardizedFileURL.path
        let appearance = state.appearance
        for offset in 0..<height {
            let index = sidebar.treeTop + offset
            guard rows.indices.contains(index) else { break }
            let row = rows[index]
            let screenRow = 1 + SidebarState.headerRows + offset
            var base = CellStyle.plain
            if row.entry != nil, row.entry?.path == sidebar.selectedPath {
                base.background = selectionBackground
                frame.fill(row: screenRow, from: 0, to: width, style: base)
            }
            for (depth, ancestor) in row.ancestors.enumerated() {
                var guide = base
                guide.foreground = TerminalPalette.color(ancestor == branch ? .gutterDisclosure : .treeIndentGuide, appearance: appearance)
                frame.write("│", row: screenRow, column: 1 + depth * 2, style: guide, limit: width)
            }
            let markerColumn = 1 + row.depth * 2
            switch row.content {
            case .unreadablePlaceholder:
                var placeholder = base
                placeholder.dim = true
                frame.write(fitted(FileTree.unreadableText, width: width - markerColumn - 2), row: screenRow, column: markerColumn + 2, style: placeholder, limit: width)
            case let .entry(entry, isExpanded):
                if entry.isDirectory {
                    var marker = base
                    marker.foreground = TerminalPalette.color(.gutterDisclosure, appearance: appearance)
                    frame.write(isExpanded ? "▾" : "▸", row: screenRow, column: markerColumn, style: marker, limit: width)
                }
                var name = base
                if entry.path == activePath {
                    name.bold = true
                    name.foreground = ChromeColors.forAppearance(appearance).accent
                }
                frame.write(fitted(entry.name, width: width - markerColumn - 2), row: screenRow, column: markerColumn + 2, style: name, limit: width)
            }
        }
    }

    private static func drawOpenList(_ frame: inout CellBuffer, state: TUIState, sidebar: SidebarState, width: Int, height: Int, selectionBackground: TerminalColor) {
        let rows = state.openListRows
        let accent = ChromeColors.forAppearance(state.appearance).accent
        for offset in 0..<height {
            let index = sidebar.openTop + offset
            guard rows.indices.contains(index) else { break }
            let screenRow = 1 + SidebarState.headerRows + offset
            var base = CellStyle.plain
            if index == sidebar.openSelection, rows[index].isSelectable {
                base.background = selectionBackground
                frame.fill(row: screenRow, from: 0, to: width, style: base)
            }
            var name = base
            var detail = base
            detail.dim = true
            let title: String
            let location: String
            switch rows[index] {
            case let .tab(tabIndex):
                let url = state.tabs[tabIndex].url
                title = url?.lastPathComponent ?? ""
                location = url.map { openLocation(of: $0, root: sidebar.tree.root) } ?? ""
                if tabIndex == state.activeTabIndex {
                    name.bold = true
                    name.foreground = accent
                }
            case .recentHeader:
                var header = base
                header.dim = true
                frame.write(recentLabel, row: screenRow, column: 1, style: header, limit: width)
                continue
            case let .recent(item):
                title = item.name
                location = item.reason ?? item.location
                name.dim = !item.isOpenable
            }
            let nameEnd = frame.write(fitted(title, width: width - 2), row: screenRow, column: 1, style: name, limit: width)
            if !location.isEmpty, nameEnd + 2 < width - 1 {
                frame.write(fitted(location, width: width - 1 - nameEnd - 2), row: screenRow, column: nameEnd + 2, style: detail, limit: width)
            }
        }
    }

    /// 打开的文件后面写的位置：在树根下时是仓库里的目录（就在树根下时为空），否则是家目录缩成 `~` 的父目录。
    static func openLocation(of url: URL, root: URL) -> String {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        let rootPath = root.standardizedFileURL.path
        if parent == rootPath { return "" }
        if parent.hasPrefix(rootPath + "/") { return String(parent.dropFirst(rootPath.count + 1)) }
        let home = NSHomeDirectory()
        return parent.hasPrefix(home + "/") ? "~/" + parent.dropFirst(home.count + 1) : parent
    }

    private static func drawOutline(_ frame: inout CellBuffer, state: TUIState, sidebar: SidebarState, width: Int, height: Int, selectionBackground: TerminalColor) {
        let outline = state.outline
        for offset in 0..<height {
            let index = sidebar.outlineTop + offset
            guard outline.indices.contains(index) else { break }
            let entry = outline[index]
            let screenRow = 1 + SidebarState.headerRows + offset
            var style = CellStyle(bold: entry.level <= 2, dim: entry.level > 2)
            if index == sidebar.outlineSelection {
                style.background = selectionBackground
                frame.fill(row: screenRow, from: 0, to: width, style: CellStyle(background: selectionBackground))
            }
            let column = 1 + (entry.level - 1) * 2
            frame.write(fitted(entry.title, width: width - column - 1), row: screenRow, column: column, style: style, limit: width)
        }
    }

    /// 放不下时截断并以「…」结尾（按显示宽度）。
    static func fitted(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard TextWidth.width(of: text) > width else { return text }
        var result = ""
        var used = 0
        for character in text {
            let characterWidth = TextWidth.width(of: character)
            guard used + characterWidth <= width - 1 else { break }
            result.append(character)
            used += characterWidth
        }
        return result + "…"
    }

    /// 放不下时从左边截断并以「…」开头，保留结尾（按显示宽度）。
    static func fittedKeepingEnd(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        guard TextWidth.width(of: text) > width else { return text }
        var result = ""
        var used = 0
        for character in text.reversed() {
            let characterWidth = TextWidth.width(of: character)
            guard used + characterWidth <= width - 1 else { break }
            result.insert(character, at: result.startIndex)
            used += characterWidth
        }
        return "…" + result
    }
}
