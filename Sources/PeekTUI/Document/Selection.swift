import Foundation
import PeekyCore

/// 正文里的一个位置：第 `line` 个显示行（Markdown 为排版行）的第 `column` 个视觉列
/// （展开制表符、不折行时的列，0 起算）。
package struct TextPoint: Equatable, Comparable, Sendable {
    package var line: Int
    package var column: Int

    package init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    package static func < (lhs: TextPoint, rhs: TextPoint) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// 程序管理的选区：`anchor` 是按下鼠标的位置，`head` 随拖动移动；`[start, end)` 半开区间。
package struct TextSelection: Equatable, Sendable {
    package var anchor: TextPoint
    package var head: TextPoint

    package init(anchor: TextPoint, head: TextPoint) {
        self.anchor = anchor
        self.head = head
    }

    package var start: TextPoint { min(anchor, head) }
    package var end: TextPoint { max(anchor, head) }
    package var isEmpty: Bool { anchor == head }

    /// 第 `line` 行被选中的视觉列区间（`upperBound` 为 `Int.max` 表示到行尾）；该行不在选区里时为 nil。
    package func columns(onLine line: Int) -> Range<Int>? {
        guard !isEmpty, line >= start.line, line <= end.line else { return nil }
        let lower = line == start.line ? start.column : 0
        let upper = line == end.line ? end.column : Int.max
        return lower < upper ? lower..<upper : nil
    }
}

/// 纯函数：视觉列与原文字符之间的换算（制表符按 `LineLayout.tabWidth` 列制表位展开）。
package enum VisualColumns {
    /// 一行里每个字符的起始视觉列与宽度。
    static func cells(of text: String) -> [(character: Character, column: Int, width: Int)] {
        var result: [(Character, Int, Int)] = []
        var column = 0
        for character in text {
            let width = character == "\t"
                ? LineLayout.tabWidth - column % LineLayout.tabWidth
                : TextWidth.width(of: character)
            result.append((character, column, width))
            column += width
        }
        return result
    }

    /// 起始列落在 `range` 里的字符（原样，制表符保留）。
    package static func substring(of text: String, columns range: Range<Int>) -> String {
        String(cells(of: text).filter { range.contains($0.column) }.map(\.character))
    }

    /// 一行展开制表符后的显示宽度。
    package static func width(of text: String) -> Int {
        cells(of: text).last.map { $0.column + $0.width } ?? 0
    }

    /// 从第 `column` 列起排下 `text` 之后到达的列（制表符按制表位展开）。
    package static func column(after text: String, from column: Int) -> Int {
        var column = column
        for character in text {
            column += character == "\t" ? LineLayout.tabWidth - column % LineLayout.tabWidth : TextWidth.width(of: character)
        }
        return column
    }

    /// `column` 处的词的视觉列区间：字母数字与下划线连成一个词，空白连成一段，其余字符各自成段；
    /// 越过行尾时为空区间。
    package static func word(in text: String, at column: Int) -> Range<Int> {
        let cells = cells(of: text)
        guard let index = cells.firstIndex(where: { column >= $0.column && column < $0.column + $0.width }) else {
            let end = width(of: text)
            return end..<end
        }
        func kind(_ character: Character) -> Int {
            if character.isLetter || character.isNumber || character == "_" { return 0 }
            if character.isWhitespace { return 1 }
            return 2
        }
        let clickedKind = kind(cells[index].character)
        guard clickedKind != 2 else { return cells[index].column..<(cells[index].column + cells[index].width) }
        var lower = index
        while lower > 0, kind(cells[lower - 1].character) == clickedKind { lower -= 1 }
        var upper = index
        while upper + 1 < cells.count, kind(cells[upper + 1].character) == clickedKind { upper += 1 }
        return cells[lower].column..<(cells[upper].column + cells[upper].width)
    }
}

/// 纯函数：选区里要复制的文字。
package enum SelectionText {
    package static func text(_ selection: TextSelection, layout: DocumentLayout) -> String {
        if let rows = layout.markdownRows {
            return markdownText(selection, rows: rows)
        }
        if let json = layout.document.json, let range = json.visibleUTF16Range(selection: selection) {
            return json.expandedText(visibleRange: range, sourceText: layout.document.store.text)
        }
        let lastLine = min(selection.end.line, layout.lineCount - 1)
        guard selection.start.line <= lastLine else { return "" }
        return (selection.start.line...lastLine).compactMap { line in
            selection.columns(onLine: line).map { VisualColumns.substring(of: layout.text(line), columns: $0) }
        }.joined(separator: "\n")
    }

    /// Markdown：只取可复制的片段；只有装饰的行（分隔线、表格边框行）整行跳过；
    /// 软换行续行用 `joinsPrevious` 接回上一行。每行去掉行尾空白。
    static func markdownText(_ selection: TextSelection, rows: [MarkdownRow]) -> String {
        var result = ""
        var previousLine: Int?
        let lastLine = min(selection.end.line, rows.count - 1)
        guard selection.start.line <= lastLine else { return "" }
        for line in selection.start.line...lastLine {
            guard let columns = selection.columns(onLine: line) else { continue }
            let row = rows[line]
            if !row.spans.isEmpty, row.spans.allSatisfy({ $0.copyText == "" }) { continue }
            let text = copyableText(row.spans, columns: columns)
            if let previousLine {
                result += previousLine == line - 1 ? (row.joinsPrevious ?? "\n") : "\n"
            }
            result += text
            previousLine = line
        }
        return result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    /// 一行片段里落在 `columns` 里的可复制文字；替换了复制文字的片段只要有一格被选中就整段替换。
    static func copyableText(_ spans: [StyledSpan], columns: Range<Int>) -> String {
        var result = ""
        var column = 0
        for span in spans {
            let width = TextWidth.width(of: span.text)
            defer { column += width }
            if let copyText = span.copyText {
                if columns.overlaps(column..<(column + max(width, 1))) { result += copyText }
                continue
            }
            var characterColumn = column
            for character in span.text {
                if columns.contains(characterColumn) { result.append(character) }
                characterColumn += TextWidth.width(of: character)
            }
        }
        return result
    }
}

extension JSONView {
    /// 选区在折叠后可见文本里的 UTF-16 区间；没有折叠时为 nil（显示文本即源文本）。
    func visibleUTF16Range(selection: TextSelection) -> NSRange? {
        guard let store = visibleStore else { return nil }
        func offset(_ point: TextPoint) -> Int {
            let line = min(max(point.line, 0), max(store.count - 1, 0))
            let lineStart = store.utf16Offset(ofLine: line)
            let text = store.line(line)
            let prefix = VisualColumns.cells(of: text).prefix { $0.column < point.column }
            return lineStart + String(prefix.map(\.character)).utf16.count
        }
        let start = offset(selection.start)
        let end = offset(selection.end)
        return NSRange(location: start, length: max(end - start, 0))
    }
}
