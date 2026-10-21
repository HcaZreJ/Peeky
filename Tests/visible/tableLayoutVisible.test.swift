import Testing
@testable import PeekTUI

// MARK: - TableLayout 可见样例
//
// 表格列宽：各列自然宽度之和放得下就照用；放不下时每次把当前最宽的列减 1，直到放得下，
// 每列不低于最小宽度（自然宽度更小时取自然宽度）。画出来的每一行显示宽度相同，
// 竖线在中英混排时也落在同一列；单元格按 GFM 对齐方式补空格。

private func cell(_ text: String) -> [StyledSpan] { [StyledSpan(text: text, style: .plain)] }

@Suite("Visible_tableLayout")
struct Visible_tableLayout {
    @Test("放得下时照用自然宽度")
    func naturalWidthsWhenFitting() {
        #expect(TableLayout.columnWidths(natural: [3, 5], available: 20) == [3, 5])
    }

    @Test("放不下时从最宽的列开始收缩")
    func shrinkWidestFirst() {
        #expect(TableLayout.columnWidths(natural: [10, 40], available: 30) == [10, 20])
        #expect(TableLayout.columnWidths(natural: [2, 30, 30], available: 20) == [2, 9, 9])
    }

    @Test("中英混排：每行显示宽度相同，竖线对齐")
    func cjkTableAlignment() {
        let lines = TableLayout.render(
            header: [cell("名称"), cell("说明")],
            rows: [[cell("peek"), cell("终端查看器")], [cell("中文"), cell("ok")]],
            alignments: [.left, .left],
            width: 40,
            borderStyle: .plain,
            headerStyle: .plain
        ).map { $0.map(\.text).joined() }
        let widths = Set(lines.map { TextWidth.width(of: $0) })
        #expect(widths.count == 1)
        let barColumns = lines.map { line -> [Int] in
            var column = 0
            var bars: [Int] = []
            for character in line {
                if "│┌┬┐├┼┤└┴┘".contains(character) { bars.append(column) }
                column += TextWidth.width(of: character)
            }
            return bars
        }
        #expect(Set(barColumns).count == 1)
        #expect(lines.contains { $0.contains("终端查看器") })
    }

    @Test("右对齐与居中补空格")
    func alignment() {
        let lines = TableLayout.render(
            header: [cell("n"), cell("name")],
            rows: [[cell("1"), cell("ab")]],
            alignments: [.right, .center],
            width: 40,
            borderStyle: .plain,
            headerStyle: .plain
        ).map { $0.map(\.text).joined() }
        #expect(lines.contains("│ 1 │  ab  │"))
    }

    @Test("放不下的单元格在格内折行，整行高度取最高的格")
    func cellWrapping() {
        let lines = TableLayout.render(
            header: [cell("a"), cell("b")],
            rows: [[cell("x"), cell("one two three four")]],
            alignments: [.left, .left],
            width: 16,
            borderStyle: .plain,
            headerStyle: .plain
        ).map { $0.map(\.text).joined() }
        #expect(lines.count > 5)
        #expect(Set(lines.map { TextWidth.width(of: $0) }).count == 1)
    }
}
