/// 一段带样式的文字（不含换行）。`target` 是这段文字所属链接的原始地址（含文档内锚点与相对路径）。
package struct StyledSpan: Equatable, Sendable {
    package var text: String
    package var style: CellStyle
    package var target: String?
    /// 复制时用的文字：nil 复制 `text` 本身；空串表示装饰（项目符号、边框、边距），不复制。
    package var copyText: String?

    package init(text: String, style: CellStyle, target: String? = nil, copyText: String? = nil) {
        self.text = text
        self.style = style
        self.target = target
        self.copyText = copyText
    }

    /// 装饰片段：显示但不复制。
    package static func decoration(_ text: String, style: CellStyle) -> StyledSpan {
        StyledSpan(text: text, style: style, copyText: "")
    }

    /// 换掉文字、保留样式、链接与复制文字。
    func with(text: String) -> StyledSpan {
        StyledSpan(text: text, style: style, target: target, copyText: copyText)
    }
}

/// 纯函数：一行带样式片段的折行、制表符展开、水平截取，以及行号栏宽度。
package enum LineLayout {
    package static let tabWidth = 4

    /// 按格宽折成若干可视行；宽字符放不下时整字移到下一行。`width <= 0` 时不折。
    package static func wrap(_ spans: [StyledSpan], width: Int) -> [[StyledSpan]] {
        guard width > 0 else { return [spans] }
        var rows: [[StyledSpan]] = [[]]
        var used = 0
        for span in spans {
            var pending = ""
            for character in span.text {
                let characterWidth = TextWidth.width(of: character)
                if used + characterWidth > width, used > 0 {
                    if !pending.isEmpty {
                        rows[rows.count - 1].append(span.with(text: pending))
                        pending = ""
                    }
                    rows.append([])
                    used = 0
                }
                pending.append(character)
                used += characterWidth
            }
            if !pending.isEmpty {
                rows[rows.count - 1].append(span.with(text: pending))
            }
        }
        return rows
    }

    /// 代码行折行：优先断在空格、`/`、`,`、`;` 之后或宽字符之后（下一个字符是收尾标点时不断），
    /// 一行里找不到这样的位置时硬断。
    /// 原文一个字符都不丢（断处的空格留在上一行末尾），续行可以比首行窄（续行前面要画续行标记）。
    package static func wrapCode(_ spans: [StyledSpan], firstWidth: Int, continuationWidth: Int) -> [[StyledSpan]] {
        var cells: [(character: Character, width: Int, span: Int)] = []
        for (index, span) in spans.enumerated() {
            for character in span.text {
                cells.append((character, TextWidth.width(of: character), index))
            }
        }
        guard !cells.isEmpty else { return [[]] }
        var ranges: [Range<Int>] = []
        var start = 0
        var limit = max(firstWidth, 1)
        while start < cells.count {
            var used = 0
            var end = start
            var lastBreak: Int?
            while end < cells.count, end == start || used + cells[end].width <= limit {
                used += cells[end].width
                let nextIsClosing = end + 1 < cells.count && WrapEngine.closingPunctuation.contains(cells[end + 1].character)
                if breaksAfter(cells[end]), !nextIsClosing { lastBreak = end + 1 }
                end += 1
            }
            if end < cells.count, let lastBreak, lastBreak > start {
                end = lastBreak
            }
            ranges.append(start..<end)
            start = end
            limit = max(continuationWidth, 1)
        }
        return ranges.map { range in
            var row: [StyledSpan] = []
            var spanIndex: Int?
            var text = ""
            for index in range {
                if cells[index].span != spanIndex, let current = spanIndex {
                    row.append(spans[current].with(text: text))
                    text = ""
                }
                spanIndex = cells[index].span
                text.append(cells[index].character)
            }
            if let current = spanIndex, !text.isEmpty {
                row.append(spans[current].with(text: text))
            }
            return row
        }
    }

    private static func breaksAfter(_ cell: (character: Character, width: Int, span: Int)) -> Bool {
        cell.width == 2 || [" ", "/", ",", ";"].contains(cell.character)
    }

    /// 与 `wrap` 同样的规则只数行数，不分配片段。
    package static func rowCount(of text: String, width: Int) -> Int {
        guard width > 0 else { return 1 }
        var rows = 1
        var used = 0
        for character in text {
            let characterWidth = TextWidth.width(of: character)
            if used + characterWidth > width, used > 0 {
                rows += 1
                used = 0
            }
            used += characterWidth
        }
        return rows
    }

    /// 制表符按 `tabWidth` 列制表位展开，列号跨片段累计。
    package static func expandTabs(_ spans: [StyledSpan]) -> [StyledSpan] {
        guard spans.contains(where: { $0.text.contains("\t") }) else { return spans }
        var column = 0
        return spans.map { span in
            var expanded = ""
            for character in span.text {
                if character == "\t" {
                    let spaces = tabWidth - column % tabWidth
                    expanded += String(repeating: " ", count: spaces)
                    column += spaces
                } else {
                    expanded.append(character)
                    column += TextWidth.width(of: character)
                }
            }
            return span.with(text: expanded)
        }
    }

    /// 不换行时的水平滚动：从第 `offset` 列起取 `width` 列。截到半个宽字符的位置补空格。
    package static func clip(_ spans: [StyledSpan], from offset: Int, width: Int) -> [StyledSpan] {
        var result: [StyledSpan] = []
        var column = 0
        let end = offset + width
        for span in spans {
            var kept = ""
            for character in span.text {
                let characterWidth = TextWidth.width(of: character)
                let start = column
                column += characterWidth
                if column <= offset || start >= end { continue }
                if start < offset || column > end {
                    kept += String(repeating: " ", count: min(column, end) - max(start, offset))
                } else {
                    kept.append(character)
                }
            }
            if !kept.isEmpty {
                result.append(span.with(text: kept))
            }
            if column >= end { break }
        }
        return result
    }

    /// 行号栏宽度：最大行号的位数 + 左右各 1 格空白。
    package static func gutterWidth(lineCount: Int) -> Int {
        String(max(lineCount, 1)).count + 2
    }
}
