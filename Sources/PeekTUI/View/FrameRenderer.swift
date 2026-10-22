import PeekyCore

/// 纯函数：把 `TUIState` 画成一帧 `CellBuffer`。
///
/// 布局：第一行标题（路径 + 详情），最后一行状态栏，中间是正文。正文左侧是行号栏，
/// 软换行的续行不编号；光标行整行铺光标行底色。颜色跟随终端明暗；源码视图固定铺 Dark Modern
/// 背景与前景（与 app 的源码视图一致），它的行号栏、光标行也按深色画。
package enum FrameRenderer {
    static let helpHint = "? 帮助  q 退出"

    static let noFileHint = "从左侧选择一个文件"
    static let recentFilesHint = "按 1 在 Open 里打开最近的文件"

    package static func render(_ state: TUIState) -> CellBuffer {
        var frame = CellBuffer(columns: state.size.columns, rows: state.size.rows)
        let statusRow = state.size.rows - 1
        let appearance = state.appearance
        // 正文先画进一块正文区宽的缓冲区，再贴到侧栏右侧
        var body = CellBuffer(columns: state.contentColumns, rows: state.size.rows)
        var statusLeft = state.toast ?? ""
        var statusRight = helpHint
        switch state.document {
        case let .loading(path):
            drawTitle(&frame, path: path, details: "")
            body.write("正在读取 \(path)…", row: 1, column: 1, style: CellStyle(dim: true))
        case let .failed(message):
            drawTitle(&frame, path: "", details: "")
            body.write(message, row: 1, column: 1, style: CellStyle(foreground: TerminalPalette.color(.invalidLineForeground, appearance: appearance)))
        case let .noFile(directory):
            drawTitle(&frame, path: directory, details: "")
            body.write(noFileHint, row: 1, column: 1, style: CellStyle(dim: true))
            if !state.recentFiles.isEmpty, state.sidebar != nil {
                body.write(recentFilesHint, row: 2, column: 1, style: CellStyle(dim: true))
            }
        case let .loaded(document):
            drawTitle(&frame, path: document.header.displayPath, details: document.header.details)
            let layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines, appearance: appearance)
            let contentAppearance = contentAppearance(for: document, appearance: appearance)
            drawContent(&body, layout: layout, viewport: state.viewport, height: state.contentHeight, appearance: contentAppearance)
            frame.images = visibleImages(layout: layout, viewport: state.viewport, height: state.contentHeight)
            if let search = state.search, !search.matches.isEmpty {
                drawSearchMatches(&body, search: search, layout: layout, viewport: state.viewport, height: state.contentHeight, colors: ChromeColors.forAppearance(contentAppearance))
            }
            if let selection = state.selection, !selection.isEmpty {
                drawSelection(&body, selection: selection, layout: layout, viewport: state.viewport, height: state.contentHeight, color: ChromeColors.forAppearance(contentAppearance).selection)
            }
            let cursorSource = document.sourceLine(forLine: state.viewport.cursor)
            let position = "Ln \(cursorSource + 1)/\(document.store.count)"
            let wrapHint = state.wrapsLines || layout.markdownRows != nil ? "" : "不换行  "
            let jqPath = document.json?.paths(forSourceLine: cursorSource).map { JSONPathMap.truncatedForDisplay($0.jq, limit: 60) + "  " } ?? ""
            let selected = state.selection.flatMap { $0.isEmpty ? nil : "选中 \(SelectionText.text($0, layout: layout).count) 字符  " } ?? ""
            let searchSummary = state.search.map { searchSummaryText($0) + "  " } ?? ""
            let fileIndex = state.tabs.count > 1 ? "文件 \((state.activeTabIndex ?? 0) + 1)/\(state.tabs.count)  " : ""
            statusRight = "\(selected)\(searchSummary)\(jqPath)\(wrapHint)\(fileIndex)\(position)  \(helpHint)"
            let leftWidth = state.size.columns - TextWidth.width(of: statusRight) - 3
            statusLeft = state.toast ?? document.progressNote ?? selectionReferenceHint(state, width: leftWidth) ?? ""
        }
        frame.paste(body, rows: 1..<max(statusRow, 1), atColumn: state.contentOrigin)
        if let sidebar = state.sidebar, sidebar.isVisible {
            SidebarRenderer.draw(&frame, state: state, sidebar: sidebar, width: state.sidebarWidth)
        }
        if let input = state.lineInput { statusLeft = ":" + input }
        if let input = state.searchInput { statusLeft = "/" + input }
        drawStatusBar(&frame, row: statusRow, left: statusLeft, right: statusRight, appearance: appearance)
        if state.isHelpVisible { HelpOverlay.draw(&frame, appearance: appearance) }
        return frame
    }

    static let referenceKeyHint = "L 复制 "

    /// 有选区时状态栏左侧的「L 复制 路径:行号」；路径放不下时从左边截断，行号始终可见。
    private static func selectionReferenceHint(_ state: TUIState, width: Int) -> String? {
        guard let selection = state.selection, !selection.isEmpty, let reference = TUIReducer.lineReference(state) else { return nil }
        let referenceWidth = width - TextWidth.width(of: referenceKeyHint)
        guard referenceWidth > 0 else { return nil }
        return referenceKeyHint + SidebarRenderer.fittedKeepingEnd(reference, width: referenceWidth)
    }

    /// 视口里出现的图（按出现顺序、不重复）。
    private static func visibleImages(layout: DocumentLayout, viewport: Viewport, height: Int) -> [TerminalImage] {
        guard let rows = layout.markdownRows else { return [] }
        var images: [TerminalImage] = []
        for position in viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows) {
            guard let position, position.line < rows.count, let image = rows[position.line].image, !images.contains(image) else { continue }
            images.append(image)
        }
        return images
    }

    /// 正文用哪套颜色：源码视图固定深色，其余跟随终端。
    private static func contentAppearance(for document: OpenedDocument, appearance: PeekyPalette.Appearance) -> PeekyPalette.Appearance {
        if case .source = document.presentation { return .dark }
        return appearance
    }

    /// 状态栏里的搜索概况：`/词 3/17`（有当前匹配）、`/词 17 处`、`/词 无匹配`；还在搜时末尾加「…」，
    /// 超过上限时数目后加「+」。
    static func searchSummaryText(_ search: SearchState) -> String {
        let query = "/" + SidebarRenderer.fitted(search.query, width: 20)
        let count = search.matchCount
        if search.isComplete, count == 0 { return "\(query) 无匹配" }
        if !search.isComplete, count == 0 { return "\(query) 搜索中…" }
        let total = "\(count)\(search.isTruncated ? "+" : "")"
        let pending = search.isComplete ? "" : "…"
        guard let current = search.current else { return "\(query) \(total) 处\(pending)" }
        let ordinal = search.matches[...current].count(where: { !$0.isContinuation })
        return "\(query) \(ordinal)/\(total)\(pending)"
    }

    /// 视口里的匹配铺底色，当前匹配用更深的颜色。JSON 的折叠行不画（它显示的不是源行原文）。
    private static func drawSearchMatches(_ frame: inout CellBuffer, search: SearchState, layout: DocumentLayout, viewport: Viewport, height: Int, colors: ChromeColors) {
        let current = search.currentSegments
        let positions = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows)
        for (index, position) in positions.enumerated() {
            guard let position else { continue }
            let line = TUIReducer.searchLine(forDisplayLine: position.line, document: layout.document)
            if layout.document.json?.isCollapsed(sourceLine: line) == true { continue }
            let visible = layout.visualRange(line: position.line, row: position.row, horizontalOffset: viewport.horizontalOffset)
            let offset = layout.gutterWidth - visible.lowerBound
            var matchIndex = search.firstIndex(onOrAfter: line)
            while matchIndex < search.matches.count, search.matches[matchIndex].line == line {
                let columns = search.matches[matchIndex].columns
                let lower = max(columns.lowerBound, visible.lowerBound)
                let upper = min(columns.upperBound, visible.upperBound)
                if lower < upper {
                    let color = current?.contains(matchIndex) == true ? colors.currentSearchMatch : colors.searchMatch
                    frame.setBackground(row: index + 1, from: lower + offset, to: upper + offset, color: color)
                }
                matchIndex += 1
            }
        }
    }

    /// 选中的格子铺选区底色；整行选中的行在行尾多铺一格，表示换行也在选区里。
    private static func drawSelection(_ frame: inout CellBuffer, selection: TextSelection, layout: DocumentLayout, viewport: Viewport, height: Int, color: TerminalColor) {
        let positions = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows)
        for (index, position) in positions.enumerated() {
            guard let position, let selected = selection.columns(onLine: position.line) else { continue }
            let visible = layout.visualRange(line: position.line, row: position.row, horizontalOffset: viewport.horizontalOffset)
            let lineWidth = layout.lineWidth(position.line)
            let isLastRow = visible.upperBound >= lineWidth
            let rowEnd = isLastRow ? lineWidth + (selected.upperBound == .max ? 1 : 0) : visible.upperBound
            let lower = max(selected.lowerBound, visible.lowerBound)
            let upper = min(selected.upperBound, rowEnd)
            guard lower < upper else { continue }
            let offset = layout.gutterWidth - visible.lowerBound
            frame.setBackground(row: index + 1, from: lower + offset, to: upper + offset, color: color)
        }
    }

    private static func drawContent(_ frame: inout CellBuffer, layout: DocumentLayout, viewport: Viewport, height: Int, appearance: PeekyPalette.Appearance) {
        let isSource: Bool
        if case .source = layout.document.presentation { isSource = true } else { isSource = false }
        let baseStyle = isSource
            ? CellStyle(
                foreground: TerminalPalette.color(.editorForeground, appearance: appearance),
                background: TerminalPalette.color(.editorBackground, appearance: appearance)
            )
            : CellStyle.plain
        let gutterStyle = CellStyle(foreground: TerminalPalette.color(.gutterText, appearance: appearance), background: baseStyle.background)
        let cursorLine = ChromeColors.forAppearance(appearance).cursorLine
        let positions = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows)
        // 放大标题的块等所有行铺完底色再写，免得下一行铺底色时冲掉块覆盖的格子
        var scaledBlocks: [(row: Int, line: Int, heading: ScaledHeading)] = []
        for (index, position) in positions.enumerated() {
            let row = index + 1
            frame.fill(row: row, from: 0, to: frame.columns, style: baseStyle)
            guard let position else { continue }
            var lineStyle = baseStyle
            let invalid = layout.isInvalid(position.line)
            if invalid {
                lineStyle.foreground = TerminalPalette.color(.invalidLineForeground, appearance: appearance)
                lineStyle.background = TerminalPalette.color(.invalidLineBackground, appearance: appearance)
                frame.fill(row: row, from: 0, to: frame.columns, style: lineStyle)
            } else if position.line == viewport.cursor {
                lineStyle.background = cursorLine
                frame.fill(row: row, from: 0, to: frame.columns, style: lineStyle)
            }
            if let markdownRows = layout.markdownRows, position.line < markdownRows.count, let fill = markdownRows[position.line].fill {
                let end = fill.toEdge ? frame.columns : frame.columns - MarkdownLayout.margin
                frame.fill(row: row, from: fill.column, to: end, style: fill.style)
            }
            if position.row == 0, layout.gutterWidth > 0 {
                let number = String(layout.sourceLine(position.line) + 1)
                var numberStyle = gutterStyle
                numberStyle.background = lineStyle.background
                let markerColumns = layout.document.presentation.isJSON ? 2 : 0
                let padding = layout.gutterWidth - 1 - markerColumns - number.count
                frame.write(String(repeating: " ", count: max(padding, 0)) + number, row: row, column: 0, style: numberStyle)
                if markerColumns > 0, let marker = invalid ? "!" : layout.foldMarker(position.line) {
                    var markerStyle = numberStyle
                    markerStyle.foreground = invalid ? lineStyle.foreground : TerminalPalette.color(.gutterDisclosure, appearance: appearance)
                    frame.write(marker, row: row, column: layout.gutterWidth - 2, style: markerStyle)
                }
            }
            var spansLine = position.line
            if let heading = layout.markdownRows?[position.line].scaledHeading {
                // 上下两半都在视口里才放大；只露出一半时画不放大的样子（放大块不能只显示一半）
                let partnerIndex = heading.part == 0 ? index + 1 : index - 1
                let partnerLine = heading.part == 0 ? position.line + 1 : position.line - 1
                let partnerVisible = positions.indices.contains(partnerIndex) && positions[partnerIndex]?.line == partnerLine
                if partnerVisible, viewport.horizontalOffset == 0 {
                    if heading.part == 0 { scaledBlocks.append((row, position.line, heading)) }
                    continue
                }
                if heading.part == 1 { spansLine = position.line - 1 }
            }
            drawSpans(&frame, layout: layout, line: spansLine, row: row, wrapRow: position.row, lineStyle: lineStyle, invalid: invalid, horizontalOffset: viewport.horizontalOffset)
        }
        for block in scaledBlocks {
            drawScaledHeading(&frame, block.heading, row: block.row, line: block.line, layout: layout)
        }
    }

    /// 写放大块：字的样式取标题文字片段的样式，底色取该格已铺的底色；放不进正文区时画不放大的样子。
    private static func drawScaledHeading(_ frame: inout CellBuffer, _ heading: ScaledHeading, row: Int, line: Int, layout: DocumentLayout) {
        let spans = layout.visibleSpans(line: line, row: 0, baseStyle: .plain, horizontalOffset: 0)
        var style = spans.first { $0.copyText == nil }?.style ?? CellStyle(bold: true)
        style.background = frame[row, heading.column].style.background
        style.link = nil
        let scaled = ScaledText(text: heading.text, spec: heading.scale)
        if !frame.writeScaled(scaled, row: row, column: heading.column, style: style) {
            drawSpans(&frame, layout: layout, line: line, row: row, wrapRow: 0, lineStyle: .plain, invalid: false, horizontalOffset: 0)
        }
    }

    private static func drawSpans(
        _ frame: inout CellBuffer,
        layout: DocumentLayout,
        line: Int,
        row: Int,
        wrapRow: Int,
        lineStyle: CellStyle,
        invalid: Bool,
        horizontalOffset: Int
    ) {
        let spans = layout.visibleSpans(line: line, row: wrapRow, baseStyle: lineStyle, horizontalOffset: horizontalOffset)
        var column = layout.gutterWidth
        for span in spans {
            var style = span.style
            if style.background == .default || (layout.markdownRows == nil && !layout.document.presentation.isJSON) {
                style.background = frame[row, min(column, frame.columns - 1)].style.background
            }
            if invalid { style.foreground = lineStyle.foreground }
            column = frame.write(span.text, row: row, column: column, style: style)
        }
    }

    private static func drawTitle(_ frame: inout CellBuffer, path: String, details: String) {
        guard frame.rows > 0 else { return }
        let end = frame.write(" " + path, row: 0, column: 0, style: CellStyle(bold: true))
        if !details.isEmpty {
            frame.write("  " + details, row: 0, column: end, style: CellStyle(dim: true))
        }
    }

    private static func drawStatusBar(_ frame: inout CellBuffer, row: Int, left: String, right: String, appearance: PeekyPalette.Appearance) {
        guard row > 0, row < frame.rows else { return }
        let style = CellStyle(
            foreground: TerminalPalette.color(.statusBarText, appearance: appearance),
            background: TerminalPalette.color(.statusBarBackground, appearance: appearance)
        )
        frame.fill(row: row, from: 0, to: frame.columns, style: style)
        let rightWidth = TextWidth.width(of: right)
        let rightStart = max(frame.columns - rightWidth - 1, 0)
        frame.write(" " + left, row: row, column: 0, style: style, limit: max(rightStart - 1, 0))
        frame.write(right, row: row, column: rightStart, style: style)
    }
}
