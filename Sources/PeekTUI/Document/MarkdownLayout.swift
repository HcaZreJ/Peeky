import Foundation
import Markdown
import PeekyCore

/// Markdown 的终端配色，取 github-markdown.css（Primer）的值，与 app 的 Markdown 预览同源。
package struct MarkdownTheme: Equatable, Sendable {
    package var appearance: PeekyPalette.Appearance
    /// 代码块是否按 shiki 结果上色：高亮服务只有 Dark Modern 一套配色，浅色下不上色（与 app 一致）
    package var highlightsCode: Bool
    package var link: TerminalColor
    package var muted: TerminalColor
    package var border: TerminalColor
    package var headingAccent: TerminalColor
    package var headingBar: TerminalColor
    package var quoteBar: TerminalColor
    package var codeBlockBackground: TerminalColor
    package var inlineCodeBackground: TerminalColor

    package static let dark = MarkdownTheme(
        appearance: .dark,
        highlightsCode: true,
        link: .rgb(0x44, 0x93, 0xF8),
        muted: .rgb(0x91, 0x98, 0xA1),
        border: .rgb(0x3D, 0x44, 0x4D),
        headingAccent: .rgb(0x44, 0x93, 0xF8),
        headingBar: .rgb(0x1C, 0x2B, 0x41),
        quoteBar: .rgb(0x3D, 0x44, 0x4D),
        codeBlockBackground: .rgb(0x15, 0x1B, 0x23),
        inlineCodeBackground: .rgb(0x2D, 0x33, 0x3B)
    )

    package static let light = MarkdownTheme(
        appearance: .light,
        highlightsCode: false,
        link: .rgb(0x09, 0x69, 0xDA),
        muted: .rgb(0x59, 0x63, 0x6E),
        border: .rgb(0xD1, 0xD9, 0xE0),
        headingAccent: .rgb(0x09, 0x69, 0xDA),
        headingBar: .rgb(0xDD, 0xF4, 0xFF),
        quoteBar: .rgb(0xD1, 0xD9, 0xE0),
        codeBlockBackground: .rgb(0xF6, 0xF8, 0xFA),
        inlineCodeBackground: .rgb(0xEF, 0xF1, 0xF3)
    )
}

/// 一行的底色铺法：从第 `column` 列起铺到正文右边界（`toEdge` 时铺到整行最右）。
package struct RowFill: Equatable, Sendable {
    package var column: Int
    package var style: CellStyle
    package var toEdge: Bool
}

/// 排好的一屏行。`spans` 从第 0 列起（含左边距）。
package struct MarkdownRow: Equatable, Sendable {
    package var spans: [StyledSpan]
    /// 来源于源文件的第几行（0 起算）
    package var sourceLine: Int
    package var fill: RowFill?
    /// 标题锚点（GitHub 规则的 slug），供文档内 `#…` 链接跳转
    package var anchor: String?
    /// 这一行里链接的原始地址，按出现顺序
    package var links: [String]
    /// 是上一行的软换行续行时，复制时用它接回上一行（折行处去掉了空格时是 " "）；新的一行为 nil
    package var joinsPrevious: String?
    /// 放大标题（kitty OSC 66）的上半行或下半行；上半行的 `spans` 是不放大时的样子
    package var scaledHeading: ScaledHeading?
}

/// 放大标题的一个折行：占上下两个排版行。`column` 是放大块左上格所在的列（含左边距）。
package struct ScaledHeading: Equatable, Sendable {
    /// 0 上半行，1 下半行
    package var part: Int
    package var text: String
    package var scale: ScaleSpec
    package var column: Int
}

/// 大纲里的一项：1–4 级标题（与 app 侧栏 Contents 的取法一致），`row` 是标题第一行的排版行号。
package struct MarkdownOutlineEntry: Equatable, Sendable {
    package static let untitled = "Untitled heading"
    package static let maximumLevel = 4

    package var level: Int
    package var title: String
    package var row: Int
}

package struct MarkdownRendering: Equatable, Sendable {
    package var rows: [MarkdownRow]
    package var width: Int
    package var outline: [MarkdownOutlineEntry] = []
    /// 排版时用的明暗；与当前明暗不同时重排
    package var appearance: PeekyPalette.Appearance = .dark
    /// 排版时 H1 / H2 是否按放大文字排（每个折行两行）；与终端能力不同时重排
    package var scaledHeadings = false
}

extension MarkdownTheme {
    package static func forAppearance(_ appearance: PeekyPalette.Appearance) -> MarkdownTheme {
        appearance == .light ? .light : .dark
    }
}

package struct MarkdownCodeBlock: Equatable, Sendable {
    package var index: Int
    package var code: String
    package var language: String?
}

/// 纯函数：按终端宽度把 Markdown 排成屏幕行。左右各留 2 列边距，块与块之间空一行。
package enum MarkdownLayout {
    static let margin = 2
    static let bullets = ["•", "◦", "▪"]

    package static func render(
        _ source: String,
        width: Int,
        theme: MarkdownTheme,
        codeTokens: [Int: [[HighlightedToken]]] = [:],
        scaledHeadings: Bool = false
    ) -> MarkdownRendering {
        let (frontmatter, body, bodyOffset) = splitFrontmatter(source)
        let contentWidth = max(width - 2 * margin, 10)
        var builder = Builder(theme: theme, codeTokens: codeTokens, lineOffset: bodyOffset)
        builder.scaledHeadings = scaledHeadings
        var lines: [Line] = []
        if !frontmatter.isEmpty {
            lines = frontmatter.enumerated().map { index, text in
                Line(
                    spans: [.decoration(" ", style: .plain), StyledSpan(text: text, style: CellStyle(foreground: theme.muted))],
                    sourceLine: index,
                    fill: LineFill(column: 0, style: CellStyle(background: theme.codeBlockBackground), toEdge: false)
                )
            }
        }
        let document = Document(parsing: body, options: [.disableSmartOpts])
        let bodyLines = builder.blocks(Array(document.children), width: contentWidth)
        if !lines.isEmpty, !bodyLines.isEmpty {
            lines.append(Line(spans: [], sourceLine: bodyLines[0].sourceLine))
        }
        lines.append(contentsOf: bodyLines)
        let marginSpan = StyledSpan.decoration(String(repeating: " ", count: margin), style: .plain)
        let outline = lines.enumerated().compactMap { index, line in
            line.heading.map { MarkdownOutlineEntry(level: $0.level, title: $0.title, row: index) }
        }
        let rows = lines.map { line in
            MarkdownRow(
                spans: line.spans.isEmpty ? [] : [marginSpan] + line.spans,
                sourceLine: line.sourceLine,
                fill: line.fill.map { fill in
                    RowFill(column: fill.toEdge ? 0 : fill.column + margin, style: fill.style, toEdge: fill.toEdge)
                },
                anchor: line.anchor,
                links: line.links,
                joinsPrevious: line.joinsPrevious,
                scaledHeading: line.scaledHeading.map { heading in
                    var shifted = heading
                    shifted.column += margin
                    return shifted
                }
            )
        }
        return MarkdownRendering(rows: rows, width: width, outline: outline, appearance: theme.appearance, scaledHeadings: scaledHeadings)
    }

    /// 文档里的代码块（按出现顺序编号，与排版时的编号一致），供运行时逐块高亮。
    package static func codeBlocks(in source: String) -> [MarkdownCodeBlock] {
        let (_, body, _) = splitFrontmatter(source)
        var result: [MarkdownCodeBlock] = []
        func visit(_ markup: Markup) {
            if let code = markup as? CodeBlock {
                result.append(MarkdownCodeBlock(index: result.count, code: trimmedCode(code.code), language: code.language))
                return
            }
            for child in markup.children { visit(child) }
        }
        visit(Document(parsing: body, options: [.disableSmartOpts]))
        return result
    }

    static func trimmedCode(_ code: String) -> String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    /// 开头的 `---` … `---` frontmatter：返回其内容行、正文、正文在源文件里的起始行。
    static func splitFrontmatter(_ source: String) -> (lines: [String], body: String, bodyOffset: Int) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first.map({ $0.trimmingCharacters(in: .whitespaces) == "---" }) == true,
              let closing = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else {
            return ([], source, 0)
        }
        let content = lines[1..<closing].map(String.init)
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (content, body, closing + 1)
    }

    // MARK: - 排版

    private struct LineFill {
        var column: Int
        var style: CellStyle
        var toEdge: Bool
    }

    private struct Line {
        var spans: [StyledSpan]
        var sourceLine: Int
        var fill: LineFill?
        var anchor: String?
        var links: [String] = []
        /// 进大纲的标题只在第一行记级别与标题
        var heading: (level: Int, title: String)?
        var joinsPrevious: String?
        var scaledHeading: ScaledHeading?
    }

    private enum InlinePiece {
        case text(StyledSpan)
        case lineBreak
    }

    private struct Builder {
        let theme: MarkdownTheme
        let codeTokens: [Int: [[HighlightedToken]]]
        let lineOffset: Int
        var codeBlockIndex = 0
        var listDepth = 0
        var slugCounts: [String: Int] = [:]
        /// H1 / H2 按放大文字排；只放大顶层标题（列表、引用的前缀会让放大块错位）
        var scaledHeadings = false
        var containerDepth = 0

        init(theme: MarkdownTheme, codeTokens: [Int: [[HighlightedToken]]], lineOffset: Int) {
            self.theme = theme
            self.codeTokens = codeTokens
            self.lineOffset = lineOffset
        }

        func sourceLine(_ markup: Markup) -> Int {
            (markup.range?.lowerBound.line ?? 1) - 1 + lineOffset
        }

        /// `tight` 时子块之间不空行（列表项内部：段落后紧跟嵌套列表，与 GitHub 一致）。
        mutating func blocks(_ children: [Markup], width: Int, tight: Bool = false) -> [Line] {
            var lines: [Line] = []
            for child in children {
                let rendered = block(child, width: width)
                guard !rendered.isEmpty else { continue }
                if !lines.isEmpty, !tight {
                    lines.append(Line(spans: [], sourceLine: rendered[0].sourceLine))
                }
                lines.append(contentsOf: rendered)
            }
            return lines
        }

        mutating func block(_ markup: Markup, width: Int) -> [Line] {
            let line = sourceLine(markup)
            switch markup {
            case let heading as Heading:
                return self.heading(heading, width: width)
            case let paragraph as Paragraph:
                return wrapInline(Array(paragraph.children), style: .plain, width: width, sourceLine: line)
            case let list as UnorderedList:
                return self.list(Array(list.listItems), ordered: nil, width: width)
            case let list as OrderedList:
                return self.list(Array(list.listItems), ordered: Int(list.startIndex), width: width)
            case let quote as BlockQuote:
                return blockQuote(quote, width: width)
            case let code as CodeBlock:
                return codeBlock(code, width: width)
            case let table as Table:
                return self.table(table, width: width, sourceLine: line)
            case is ThematicBreak:
                return [Line(spans: [.decoration(String(repeating: "─", count: width), style: CellStyle(foreground: theme.border))], sourceLine: line)]
            case let html as HTMLBlock:
                return trimmedCode(html.rawHTML).split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { offset, text in
                    Line(spans: [StyledSpan(text: String(text), style: CellStyle(foreground: theme.muted))], sourceLine: line + offset)
                }
            default:
                return blocks(Array(markup.children), width: width)
            }
        }

        mutating func heading(_ heading: Heading, width: Int) -> [Line] {
            var lines = headingLines(heading, width: width)
            if heading.level <= MarkdownOutlineEntry.maximumLevel, !lines.isEmpty {
                let title = MarkdownRenderer.plainDisplayText(of: heading)
                lines[0].heading = (heading.level, title.isEmpty ? MarkdownOutlineEntry.untitled : title)
            }
            return lines
        }

        mutating func headingLines(_ heading: Heading, width: Int) -> [Line] {
            let line = sourceLine(heading)
            let anchor = slug(for: heading)
            var style = CellStyle(bold: true)
            let scales = scaledHeadings && containerDepth == 0
            switch heading.level {
            case 1 where scales:
                return scaledLines(heading, spec: .h1, style: style, width: width, leading: 1, line: line, anchor: anchor)
            case 2 where scales:
                style.foreground = theme.headingAccent
                var rows = scaledLines(heading, spec: .h2, style: style, width: width, leading: 0, line: line, anchor: anchor)
                rows.append(Line(spans: [.decoration(String(repeating: "─", count: width), style: CellStyle(foreground: theme.border))], sourceLine: line))
                return rows
            case 1:
                let wrapped = wrapInline(Array(heading.children), style: style, width: width - 1, sourceLine: line)
                return wrapped.enumerated().map { index, row in
                    Line(
                        spans: [.decoration(" ", style: .plain)] + row.spans,
                        sourceLine: line,
                        fill: LineFill(column: 0, style: CellStyle(background: theme.headingBar), toEdge: true),
                        anchor: index == 0 ? anchor : nil,
                        links: row.links,
                        joinsPrevious: row.joinsPrevious
                    )
                }
            case 2:
                style.foreground = theme.headingAccent
                var rows = wrapInline(Array(heading.children), style: style, width: width, sourceLine: line)
                if !rows.isEmpty { rows[0].anchor = anchor }
                rows.append(Line(spans: [.decoration(String(repeating: "─", count: width), style: CellStyle(foreground: theme.border))], sourceLine: line))
                return rows
            case 3:
                style.foreground = theme.headingAccent
                fallthrough
            default:
                var rows = wrapInline(Array(heading.children), style: style, width: width, sourceLine: line)
                if !rows.isEmpty { rows[0].anchor = anchor }
                return rows
            }
        }

        /// 放大标题：按一半宽度折行，每个折行排成上下两行；上半行的片段是不放大时的样子（视口截断时用）。
        /// H1 左侧留 1 列并铺整行标题底色，与不放大的 H1 一致。
        mutating func scaledLines(_ heading: Heading, spec: ScaleSpec, style: CellStyle, width: Int, leading: Int, line: Int, anchor: String) -> [Line] {
            let wrapped = wrapInline(Array(heading.children), style: style, width: max((width - leading) / spec.scale, 4), sourceLine: line)
            let fill = leading > 0 ? LineFill(column: 0, style: CellStyle(background: theme.headingBar), toEdge: true) : nil
            let leadingSpans: [StyledSpan] = leading > 0 ? [.decoration(String(repeating: " ", count: leading), style: .plain)] : []
            return wrapped.enumerated().flatMap { index, row -> [Line] in
                let text = row.spans.map(\.text).joined()
                let top = ScaledHeading(part: 0, text: text, scale: spec, column: leading)
                var bottom = top
                bottom.part = 1
                return [
                    Line(
                        spans: leadingSpans + row.spans,
                        sourceLine: line,
                        fill: fill,
                        anchor: index == 0 ? anchor : nil,
                        links: row.links,
                        joinsPrevious: row.joinsPrevious,
                        scaledHeading: top
                    ),
                    Line(spans: [], sourceLine: line, fill: fill, joinsPrevious: "", scaledHeading: bottom),
                ]
            }
        }

        mutating func list(_ items: [ListItem], ordered start: Int?, width: Int) -> [Line] {
            let lastNumber = (start ?? 1) + max(items.count - 1, 0)
            let numberWidth = "\(lastNumber).".count
            var lines: [Line] = []
            for (index, item) in items.enumerated() {
                let marker: String
                if let checkbox = item.checkbox {
                    marker = checkbox == .checked ? "[✓]" : "[ ]"
                } else if let start {
                    let number = "\(start + index)."
                    marker = number + String(repeating: " ", count: numberWidth - number.count)
                } else {
                    marker = MarkdownLayout.bullets[listDepth % MarkdownLayout.bullets.count]
                }
                let markerWidth = TextWidth.width(of: marker) + 1
                listDepth += 1
                containerDepth += 1
                let itemLines = blocks(Array(item.children), width: max(width - markerWidth, 4), tight: true)
                listDepth -= 1
                containerDepth -= 1
                let markerStyle = CellStyle(foreground: item.checkbox == nil ? theme.muted : (item.checkbox == .checked ? theme.link : theme.muted))
                for (lineIndex, itemLine) in itemLines.enumerated() {
                    var prefixed = itemLine
                    let prefix = lineIndex == 0
                        ? StyledSpan.decoration(marker + " ", style: markerStyle)
                        : StyledSpan.decoration(String(repeating: " ", count: markerWidth), style: .plain)
                    prefixed.spans = itemLine.spans.isEmpty && lineIndex > 0 ? [] : [prefix] + itemLine.spans
                    prefixed.fill = itemLine.fill.map { LineFill(column: $0.column + markerWidth, style: $0.style, toEdge: $0.toEdge) }
                    lines.append(prefixed)
                }
                if itemLines.isEmpty {
                    lines.append(Line(spans: [.decoration(marker, style: markerStyle)], sourceLine: sourceLine(item)))
                }
            }
            return lines
        }

        mutating func blockQuote(_ quote: BlockQuote, width: Int) -> [Line] {
            containerDepth += 1
            let inner = blocks(Array(quote.children), width: max(width - 2, 4))
            containerDepth -= 1
            let barStyle = CellStyle(foreground: theme.quoteBar)
            return inner.map { line in
                var prefixed = line
                let content = line.spans.map { span -> StyledSpan in
                    var muted = span
                    if muted.style.foreground == .default { muted.style.foreground = theme.muted }
                    return muted
                }
                prefixed.spans = content.isEmpty
                    ? [.decoration("▎", style: barStyle)]
                    : [.decoration("▎ ", style: barStyle)] + content
                prefixed.fill = line.fill.map { LineFill(column: $0.column + 2, style: $0.style, toEdge: $0.toEdge) }
                return prefixed
            }
        }

        mutating func codeBlock(_ code: CodeBlock, width: Int) -> [Line] {
            let index = codeBlockIndex
            codeBlockIndex += 1
            let firstLine = sourceLine(code) + 1
            let fill = LineFill(column: 0, style: CellStyle(background: theme.codeBlockBackground), toEdge: false)
            let tokens = theme.highlightsCode ? codeTokens[index] : nil
            let sourceLines = MarkdownLayout.trimmedCode(code.code).split(separator: "\n", omittingEmptySubsequences: false)
            var lines: [Line] = []
            for (offset, text) in sourceLines.enumerated() {
                let spans: [StyledSpan]
                if let tokens, offset < tokens.count {
                    spans = tokens[offset].map { token in
                        StyledSpan(text: token.text, style: CellStyle(foreground: TerminalPalette.color(hex: token.colorHex) ?? .default))
                    }
                } else {
                    spans = [StyledSpan(text: String(text), style: .plain)]
                }
                // 长行软折行：续行先补上原行的缩进，再画暗色的 ↪（都不复制）
                let expanded = LineLayout.expandTabs(spans)
                let codeWidth = max(width - 2, 4)
                let indent = min(expanded.map(\.text).joined().prefix { $0 == " " }.count, codeWidth / 2)
                let continuation: [StyledSpan] = [
                    .decoration(" " + String(repeating: " ", count: indent), style: .plain),
                    .decoration("↪ ", style: CellStyle(foreground: theme.muted)),
                ]
                let wrapped = LineLayout.wrapCode(expanded, firstWidth: codeWidth, continuationWidth: max(codeWidth - indent - 2, 4))
                for (rowIndex, row) in wrapped.enumerated() {
                    lines.append(Line(
                        spans: (rowIndex == 0 ? [.decoration(" ", style: .plain)] : continuation) + row,
                        sourceLine: firstLine + offset,
                        fill: fill,
                        joinsPrevious: rowIndex == 0 ? nil : ""
                    ))
                }
            }
            if lines.isEmpty {
                lines.append(Line(spans: [.decoration(" ", style: .plain)], sourceLine: firstLine, fill: fill))
            }
            return lines
        }

        mutating func table(_ table: Table, width: Int, sourceLine line: Int) -> [Line] {
            var header: [[StyledSpan]] = []
            for cell in table.head.cells {
                header.append(plainSpans(Array(cell.children), style: .plain))
            }
            var rows: [[[StyledSpan]]] = []
            for row in table.body.rows {
                var cells: [[StyledSpan]] = []
                for cell in row.cells {
                    cells.append(plainSpans(Array(cell.children), style: .plain))
                }
                rows.append(cells)
            }
            let alignments: [TableAlignment] = table.columnAlignments.map { alignment in
                switch alignment {
                case .center: return .center
                case .right: return .right
                default: return .left
                }
            }
            let rendered = TableLayout.render(
                header: Array(header),
                rows: Array(rows),
                alignments: alignments,
                width: width,
                borderStyle: CellStyle(foreground: theme.border),
                headerStyle: CellStyle(bold: true)
            )
            return rendered.map { Line(spans: $0, sourceLine: line, links: Self.targets(in: $0)) }
        }

        // MARK: 行内

        mutating func wrapInline(_ children: [Markup], style: CellStyle, width: Int, sourceLine line: Int) -> [Line] {
            var segments: [[StyledSpan]] = [[]]
            for piece in children.flatMap({ inline($0, style: style) }) {
                switch piece {
                case let .text(span): segments[segments.count - 1].append(span)
                case .lineBreak: segments.append([])
                }
            }
            return segments.flatMap { segment in
                let rows = WrapEngine.wrap(segment, width: width)
                let joiners = Self.joiners(original: segment, rows: rows)
                return rows.enumerated().map { index, row in
                    Line(spans: row, sourceLine: line, links: Self.targets(in: row), joinsPrevious: joiners[index])
                }
            }
        }

        /// 每个折出来的行怎样接回上一行：第一行 nil；折行处原文有空格（被折行去掉了）时为 " "，否则为 ""。
        static func joiners(original: [StyledSpan], rows: [[StyledSpan]]) -> [String?] {
            let characters = Array(original.map(\.text).joined())
            var position = 0
            return rows.enumerated().map { index, row in
                var skippedSpace = false
                while position < characters.count, characters[position] == " " {
                    position += 1
                    skippedSpace = true
                }
                position += row.map(\.text).joined().count
                guard index > 0 else { return nil }
                return skippedSpace ? " " : ""
            }
        }

        /// 一行里各链接的原始地址，按出现顺序去重。
        static func targets(in spans: [StyledSpan]) -> [String] {
            var result: [String] = []
            for target in spans.compactMap(\.target) where !result.contains(target) {
                result.append(target)
            }
            return result
        }

        /// 表格单元格等不折行的行内内容：换行一律当空格。
        mutating func plainSpans(_ children: [Markup], style: CellStyle) -> [StyledSpan] {
            children.flatMap { inline($0, style: style) }.map { piece in
                switch piece {
                case let .text(span): return span
                case .lineBreak: return StyledSpan(text: " ", style: style)
                }
            }
        }

        mutating func inline(_ markup: Markup, style: CellStyle, target: String? = nil) -> [InlinePiece] {
            func span(_ text: String, _ style: CellStyle) -> InlinePiece {
                .text(StyledSpan(text: text, style: style, target: target))
            }
            switch markup {
            case let text as Text:
                return [span(text.string, style)]
            case let emphasis as Emphasis:
                var italic = style
                italic.italic = true
                return emphasis.children.flatMap { inline($0, style: italic, target: target) }
            case let strong as Strong:
                var bold = style
                bold.bold = true
                return strong.children.flatMap { inline($0, style: bold, target: target) }
            case let strike as Strikethrough:
                var struck = style
                struck.strikethrough = true
                return strike.children.flatMap { inline($0, style: struck, target: target) }
            case let code as InlineCode:
                var codeStyle = style
                codeStyle.background = theme.inlineCodeBackground
                return [span(code.code, codeStyle)]
            case let link as Link:
                let destination = link.destination ?? ""
                var linkStyle = style
                linkStyle.underline = true
                linkStyle.foreground = theme.link
                linkStyle.link = Self.resolvedLink(destination)
                return link.children.flatMap { inline($0, style: linkStyle, target: destination) }
            case let image as Image:
                let source = image.source ?? ""
                var imageStyle = style
                imageStyle.foreground = theme.muted
                imageStyle.link = Self.resolvedLink(source)
                let alt = image.children.compactMap { ($0 as? Text)?.string }.joined()
                return [.text(StyledSpan(text: "[图片] " + (alt.isEmpty ? source : alt), style: imageStyle, target: source))]
            case is SoftBreak:
                return [span(" ", style)]
            case is LineBreak:
                return [.lineBreak]
            case let html as InlineHTML:
                var htmlStyle = style
                htmlStyle.foreground = theme.muted
                return [span(html.rawHTML, htmlStyle)]
            default:
                return markup.children.flatMap { inline($0, style: style, target: target) }
            }
        }

        /// 终端超链接只认绝对地址：带 scheme 的原样用，文档内锚点（`#…`）与相对路径不设 OSC 8。
        static func resolvedLink(_ destination: String) -> String? {
            guard let url = URL(string: destination), let scheme = url.scheme, !scheme.isEmpty else { return nil }
            return destination
        }

        /// GitHub 规则的标题锚点：小写、去掉标点（保留字母数字与 - _）、空格换成 -，重复的加 -1、-2。
        mutating func slug(for heading: Heading) -> String {
            let plain = MarkdownRenderer.plainDisplayText(of: heading).lowercased()
            var slug = ""
            for character in plain {
                if character == " " {
                    slug.append("-")
                } else if character.isLetter || character.isNumber || character == "-" || character == "_" {
                    slug.append(character)
                }
            }
            let count = slugCounts[slug, default: 0]
            slugCounts[slug] = count + 1
            return count == 0 ? slug : "\(slug)-\(count)"
        }
    }
}
