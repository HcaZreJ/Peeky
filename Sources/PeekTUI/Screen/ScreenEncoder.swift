/// 比较前后两帧，生成把屏幕从前一帧更新到后一帧所需的最少转义序列。
///
/// - 没有前一帧或尺寸变了：逐行整行重画。
/// - 否则只输出变化的格子；同一行相邻的变化合并成一段，只定位一次光标（CUP）。
/// - 样式用 SGR（每次以 0 复位开头，再叠加属性与真彩），超链接用 OSC 8；
///   先 SGR 后 OSC 8，链接标记与文字紧挨着。
/// - 有任何输出时，结尾关闭未关的链接并 `ESC[0m` 复位，样式不泄漏到终端。
/// - 放大文字（kitty OSC 66）：在放大块的格子上写普通字会擦掉整个大字，所以前后任一帧里含放大块的行
///   作为一组处理——组里任何一行有变化，就先把这些行全部清掉（`ESC[2K`），再逐行整行重画。
package enum ScreenEncoder {
    package static func encode(previous: CellBuffer?, next: CellBuffer) -> String {
        var encoder = Encoder()
        let redrawAll = previous.map { $0.columns != next.columns || $0.rows != next.rows } ?? true
        let scaledRows = redrawAll ? [] : Self.rowsWithScaledText(previous, next)
        for row in 0..<next.rows {
            if redrawAll {
                encoder.emitRun(next, row: row, start: 0, end: next.columns)
                continue
            }
            guard let previous, !scaledRows.contains(row) else { continue }
            var column = 0
            while column < next.columns {
                guard previous[row, column] != next[row, column] else {
                    column += 1
                    continue
                }
                var start = column
                if start > 0, next[row, start].isContinuation || previous[row, start].isContinuation {
                    start -= 1
                }
                var end = column + 1
                while end < next.columns, previous[row, end] != next[row, end] {
                    end += 1
                }
                if end < next.columns, next[row, end].isContinuation {
                    end += 1
                }
                encoder.emitRun(next, row: row, start: start, end: end)
                column = end
            }
        }
        if let previous, scaledRows.contains(where: { !Self.rowsEqual(previous, next, row: $0) }) {
            for row in scaledRows { encoder.eraseRow(row) }
            for row in scaledRows { encoder.emitRun(next, row: row, start: 0, end: next.columns) }
        }
        return encoder.finish()
    }

    /// 前后任一帧里含放大块格子的行，从上到下。
    private static func rowsWithScaledText(_ previous: CellBuffer?, _ next: CellBuffer) -> [Int] {
        (0..<next.rows).filter { row in
            (0..<next.columns).contains { column in
                next[row, column].isScaledBlock || previous?[row, column].isScaledBlock == true
            }
        }
    }

    private static func rowsEqual(_ previous: CellBuffer, _ next: CellBuffer, row: Int) -> Bool {
        (0..<next.columns).allSatisfy { previous[row, $0] == next[row, $0] }
    }

    private struct Encoder {
        var output = ""
        var currentStyle: CellStyle?
        var currentLink: String?

        /// 跳过放大块的格子后（光标位置不一定在下一格上）重新定位再写。
        mutating func emitRun(_ buffer: CellBuffer, row: Int, start: Int, end: Int) {
            guard start < end else { return }
            output += "\u{1B}[\(row + 1);\(start + 1)H"
            var needsPosition = false
            for column in start..<end {
                let cell = buffer[row, column]
                if cell.isCovered {
                    needsPosition = true
                    continue
                }
                guard !cell.isContinuation else { continue }
                if needsPosition {
                    output += "\u{1B}[\(row + 1);\(column + 1)H"
                    needsPosition = false
                }
                apply(cell.style)
                if let scaled = cell.scaled {
                    output += "\u{1B}]66;\(scaled.spec.metadata);\(ScreenEncoder.sanitized(scaled.text))\u{07}"
                    needsPosition = true
                } else {
                    output += cell.text
                }
            }
        }

        /// 清掉一整行（先复位样式，清行时用默认底色）。
        mutating func eraseRow(_ row: Int) {
            if currentLink != nil {
                output += ScreenEncoder.closeLink
                currentLink = nil
            }
            output += "\u{1B}[\(row + 1);1H\u{1B}[0m\u{1B}[2K"
            currentStyle = CellStyle.plain
        }

        mutating func finish() -> String {
            guard !output.isEmpty else { return "" }
            if currentLink != nil {
                output += ScreenEncoder.closeLink
            }
            output += "\u{1B}[0m"
            return output
        }

        private mutating func apply(_ style: CellStyle) {
            var visual = style
            visual.link = nil
            if visual != currentStyle {
                output += ScreenEncoder.sgr(for: visual)
                currentStyle = visual
            }
            if style.link != currentLink {
                if currentLink != nil {
                    output += ScreenEncoder.closeLink
                }
                if let link = style.link {
                    output += "\u{1B}]8;;\(ScreenEncoder.sanitized(link))\u{1B}\\"
                }
                currentLink = style.link
            }
        }
    }

    static let closeLink = "\u{1B}]8;;\u{1B}\\"

    static func sgr(for style: CellStyle) -> String {
        var parameters = ["0"]
        if style.bold { parameters.append("1") }
        if style.dim { parameters.append("2") }
        if style.italic { parameters.append("3") }
        if style.underline { parameters.append("4") }
        if style.inverse { parameters.append("7") }
        if style.strikethrough { parameters.append("9") }
        if case let .rgb(red, green, blue) = style.foreground {
            parameters.append("38;2;\(red);\(green);\(blue)")
        }
        if case let .rgb(red, green, blue) = style.background {
            parameters.append("48;2;\(red);\(green);\(blue)")
        }
        return "\u{1B}[" + parameters.joined(separator: ";") + "m"
    }

    /// 链接地址里的控制字符会提前结束 OSC 序列，一律去掉。
    static func sanitized(_ link: String) -> String {
        String(String.UnicodeScalarView(link.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
    }
}
