import PeekyCore

/// 一份已打开的按行文档在当前终端宽度下的排版参数：行号栏宽、正文宽、每行占几个可视行，
/// 以及某一行显示用的带样式片段。纯函数，渲染与 reducer 共用。
package struct DocumentLayout {
    package let document: OpenedDocument
    package let wrapsLines: Bool
    package let gutterWidth: Int
    package let contentWidth: Int

    /// Markdown 已排好的屏幕行；非 Markdown 或尚未排版时为 nil。
    package let markdownRows: [MarkdownRow]?
    /// JSON / XML 的着色明暗（源码视图固定深色，不看它）。
    package let appearance: PeekyPalette.Appearance

    package init(document: OpenedDocument, columns: Int, wrapsLines: Bool, appearance: PeekyPalette.Appearance = .dark) {
        self.document = document
        self.appearance = appearance
        self.markdownRows = document.markdown?.rows
        self.wrapsLines = markdownRows == nil && wrapsLines
        if markdownRows != nil {
            self.gutterWidth = 0
        } else {
            // JSON 在行号右侧多 2 列画折叠三角（索引建好之前也留出这两列，版面不跳）
            self.gutterWidth = LineLayout.gutterWidth(lineCount: document.store.count) + (document.presentation.isJSON ? 2 : 0)
        }
        self.contentWidth = max(columns - gutterWidth, 1)
    }

    package var lineCount: Int { markdownRows?.count ?? document.json?.visibleStore?.count ?? document.store.count }

    /// 第 `line` 个显示行的原文（JSON 折叠后取折叠后的文本）。
    package func text(_ line: Int) -> String {
        document.json?.visibleStore?.line(line) ?? document.store.line(line)
    }

    /// 显示行对应的源行（行号、路径、坏行都按源行算）。
    package func sourceLine(_ line: Int) -> Int {
        document.json?.sourceLine(forDisplayLine: line) ?? line
    }

    /// JSON 折叠三角：区域开头行显示 ▾（展开）或 ▸（折叠），其余行为 nil。
    package func foldMarker(_ line: Int) -> String? {
        guard let json = document.json else { return nil }
        let source = json.sourceLine(forDisplayLine: line)
        guard json.region(openingAt: source) != nil else { return nil }
        return json.isCollapsed(sourceLine: source) ? "▸" : "▾"
    }

    package func isInvalid(_ line: Int) -> Bool {
        document.json?.invalidSourceLines.contains(sourceLine(line)) ?? false
    }

    /// 第 `line` 行占几个可视行（Markdown 排版行恒为 1）。
    package func rows(_ line: Int) -> Int {
        guard wrapsLines else { return 1 }
        let text = LineLayout.expandTabs([StyledSpan(text: self.text(line), style: .plain)]).first?.text ?? ""
        return LineLayout.rowCount(of: text, width: contentWidth)
    }

    /// 第 `line` 行显示用的片段（已上色、已展开制表符），尚未折行或截取。
    package func spans(_ line: Int, baseStyle: CellStyle) -> [StyledSpan] {
        let text = self.text(line)
        let colored: [StyledSpan]
        switch document.presentation {
        case .source:
            if let tokens = document.highlights[line] {
                colored = tokens.map { token in
                    var style = baseStyle
                    style.foreground = TerminalPalette.color(hex: token.colorHex) ?? baseStyle.foreground
                    return StyledSpan(text: token.text, style: style)
                }
            } else {
                colored = [StyledSpan(text: text, style: baseStyle)]
            }
        case .xml:
            colored = XMLColoring.spans(for: text, baseStyle: baseStyle, appearance: appearance)
        case .json, .jsonLines:
            colored = JSONLineColoring.spans(for: text, appearance: appearance, baseStyle: baseStyle)
        case .plain, .markdown:
            colored = [StyledSpan(text: text, style: baseStyle)]
        }
        return LineLayout.expandTabs(colored)
    }

    // MARK: - 视觉列（选区坐标）

    /// 选词、量宽度用的行文字：Markdown 是排版行显示的文字（含装饰），其余是原文。
    package func selectableText(_ line: Int) -> String {
        if let markdownRows {
            return line < markdownRows.count ? markdownRows[line].spans.map(\.text).joined() : ""
        }
        return text(line)
    }

    /// 一行展开制表符、不折行时的显示宽度。
    package func lineWidth(_ line: Int) -> Int {
        VisualColumns.width(of: selectableText(line))
    }

    /// 换行开启时每个可视行的起始视觉列（规则同 `LineLayout.wrap`：宽字符放不下时整字移到下一行）。
    func rowStartColumns(_ line: Int) -> [Int] {
        guard wrapsLines, markdownRows == nil else { return [0] }
        var starts = [0]
        var used = 0
        for cell in VisualColumns.cells(of: text(line)) {
            if used + cell.width > contentWidth, used > 0 {
                starts.append(cell.column)
                used = 0
            }
            used += cell.width
        }
        return starts
    }

    /// 屏幕上第 `row` 个可视行显示的视觉列区间。
    package func visualRange(line: Int, row: Int, horizontalOffset: Int) -> Range<Int> {
        guard wrapsLines, markdownRows == nil else { return horizontalOffset..<(horizontalOffset + contentWidth) }
        let starts = rowStartColumns(line)
        let index = min(row, starts.count - 1)
        let end = index + 1 < starts.count ? starts[index + 1] : max(lineWidth(line), starts[index])
        return starts[index]..<end
    }

    /// 正文区第 `screenColumn` 列（含行号栏）落在可视行 `position` 上时的文档位置；超出该行时落在行尾。
    package func point(atScreenColumn screenColumn: Int, position: ScrollPosition, horizontalOffset: Int) -> TextPoint {
        let range = visualRange(line: position.line, row: position.row, horizontalOffset: horizontalOffset)
        let column = range.lowerBound + max(screenColumn - gutterWidth, 0)
        let lineEnd = lineWidth(position.line)
        let isLastRow = range.upperBound >= lineEnd
        return TextPoint(line: position.line, column: min(column, isLastRow ? lineEnd : range.upperBound))
    }

    /// 第 `line` 行的第 `row` 个可视行（换行关闭时按水平偏移截取）。
    package func visibleSpans(line: Int, row: Int, baseStyle: CellStyle, horizontalOffset: Int) -> [StyledSpan] {
        if let markdownRows {
            guard line < markdownRows.count else { return [] }
            return LineLayout.clip(markdownRows[line].spans, from: horizontalOffset, width: contentWidth)
        }
        let full = spans(line, baseStyle: baseStyle)
        guard wrapsLines else {
            return LineLayout.clip(full, from: horizontalOffset, width: contentWidth)
        }
        let wrapped = LineLayout.wrap(full, width: contentWidth)
        return row < wrapped.count ? wrapped[row] : []
    }
}

/// PeekyPalette / shiki 的 hex 颜色转终端真彩。
package enum TerminalPalette {
    package static func color(hex: String) -> TerminalColor? {
        guard let rgba = PeekyPalette.rgba(fromHex: hex) else { return nil }
        return .rgb(rgba.red, rgba.green, rgba.blue)
    }

    /// 语义 token 的终端颜色。带透明度的颜色（如坏行底色 `#F8514922`）叠在该外观的编辑器底色上，
    /// 终端没有透明度，直接取 RGB 会变成不透明的纯色。
    package static func color(_ token: PeekyPalette.ThemeColor, appearance: PeekyPalette.Appearance = .dark) -> TerminalColor {
        guard let hex = PeekyPalette.hex(token, appearance: appearance), let rgba = PeekyPalette.rgba(fromHex: hex) else {
            return .default
        }
        guard rgba.alpha < 0xFF,
              let baseHex = PeekyPalette.hex(.editorBackground, appearance: appearance),
              let base = PeekyPalette.rgba(fromHex: baseHex)
        else {
            return .rgb(rgba.red, rgba.green, rgba.blue)
        }
        func blend(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Int(top) * Int(rgba.alpha) + Int(bottom) * (255 - Int(rgba.alpha))) / 255)
        }
        return .rgb(blend(rgba.red, base.red), blend(rgba.green, base.green), blend(rgba.blue, base.blue))
    }
}
