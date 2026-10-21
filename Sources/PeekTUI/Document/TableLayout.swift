package enum TableAlignment: Equatable, Sendable {
    case left
    case center
    case right
}

/// 纯函数：Markdown 表格的列宽分配与框线排版。
///
/// 列宽：自然宽度之和放得下就照用；放不下时每次把当前最宽的列减 1，每列不低于
/// `min(minimum, 自然宽度)`。单元格内容在格内按词折行，一行表格的高度取最高的格。
package enum TableLayout {
    package static let minimumColumnWidth = 6

    package static func columnWidths(natural: [Int], available: Int, minimum: Int = minimumColumnWidth) -> [Int] {
        var widths = natural.map { max($0, 1) }
        let floors = widths.map { min($0, minimum) }
        while widths.reduce(0, +) > available {
            let candidates = widths.indices.filter { widths[$0] > floors[$0] }
            guard let widest = candidates.max(by: { widths[$0] < widths[$1] || (widths[$0] == widths[$1] && $0 > $1) }) else {
                break
            }
            widths[widest] -= 1
        }
        return widths
    }

    package static func render(
        header: [[StyledSpan]],
        rows: [[[StyledSpan]]],
        alignments: [TableAlignment],
        width: Int,
        borderStyle: CellStyle,
        headerStyle: CellStyle
    ) -> [[StyledSpan]] {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }
        let allRows = [header] + rows
        let natural = (0..<columnCount).map { column in
            allRows.map { row in column < row.count ? TextWidth.width(of: row[column].map(\.text).joined()) : 0 }.max() ?? 1
        }
        let available = max(width - (columnCount + 1) - 2 * columnCount, columnCount)
        let widths = columnWidths(natural: natural, available: available)

        func border(_ left: String, _ middle: String, _ right: String) -> [StyledSpan] {
            let segments = widths.map { String(repeating: "─", count: $0 + 2) }
            return [.decoration(left + segments.joined(separator: middle) + right, style: borderStyle)]
        }

        func tableRow(_ cells: [[StyledSpan]], emphasize: Bool) -> [[StyledSpan]] {
            let wrappedCells = (0..<columnCount).map { column -> [[StyledSpan]] in
                var content = column < cells.count ? cells[column] : []
                if emphasize {
                    content = content.map { span in
                        var styled = span
                        styled.style.bold = styled.style.bold || headerStyle.bold
                        return styled
                    }
                }
                return WrapEngine.wrap(content, width: widths[column])
            }
            let height = wrappedCells.map(\.count).max() ?? 1
            return (0..<height).map { lineIndex in
                // 复制时单元格之间是制表符，边框与补白不复制
                var line = [StyledSpan.decoration("│", style: borderStyle)]
                for column in 0..<columnCount {
                    let content = lineIndex < wrappedCells[column].count ? wrappedCells[column][lineIndex] : []
                    let alignment = column < alignments.count ? alignments[column] : .left
                    line.append(.decoration(" ", style: .plain))
                    line.append(contentsOf: aligned(content, width: widths[column], alignment: alignment))
                    line.append(.decoration(" ", style: .plain))
                    line.append(StyledSpan(text: "│", style: borderStyle, copyText: column + 1 < columnCount ? "\t" : ""))
                }
                return line
            }
        }

        var lines = [border("┌", "┬", "┐")]
        lines.append(contentsOf: tableRow(header, emphasize: true))
        lines.append(border("├", "┼", "┤"))
        for row in rows {
            lines.append(contentsOf: tableRow(row, emphasize: false))
        }
        lines.append(border("└", "┴", "┘"))
        return lines
    }

    private static func aligned(_ content: [StyledSpan], width: Int, alignment: TableAlignment) -> [StyledSpan] {
        let contentWidth = TextWidth.width(of: content.map(\.text).joined())
        let padding = max(width - contentWidth, 0)
        let left: Int
        switch alignment {
        case .left: left = 0
        case .right: left = padding
        case .center: left = padding / 2
        }
        var result: [StyledSpan] = []
        if left > 0 { result.append(.decoration(String(repeating: " ", count: left), style: .plain)) }
        result.append(contentsOf: content)
        if padding - left > 0 { result.append(.decoration(String(repeating: " ", count: padding - left), style: .plain)) }
        return result
    }
}
