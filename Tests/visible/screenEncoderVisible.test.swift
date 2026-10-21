import Testing
@testable import PeekTUI

// MARK: - CellBuffer / ScreenEncoder 可见样例
//
// CellBuffer 是一帧屏幕内容的格子网格；ScreenEncoder 比较前后两帧，只为变化的格子
// 输出转义序列：光标定位用 CUP（ESC[行;列H，1 起算），样式用 SGR 真彩，超链接用 OSC 8，
// 每次输出结尾把 SGR 复位，避免样式泄漏到终端。宽字符占两格，第二格是续格、不单独输出。

private let esc = "\u{1B}"

private func buffer(_ rows: [String], columns: Int) -> CellBuffer {
    var screen = CellBuffer(columns: columns, rows: rows.count)
    for (row, text) in rows.enumerated() {
        screen.write(text, row: row, column: 0, style: .plain)
    }
    return screen
}

private func cupCount(_ output: String) -> Int {
    output.components(separatedBy: "\(esc)[").dropFirst().filter { part in
        guard let h = part.firstIndex(of: "H") else { return false }
        return part[..<h].allSatisfy { $0.isNumber || $0 == ";" }
    }.count
}

@Suite("Visible_screenEncoder")
struct Visible_screenEncoder {
    @Test("前后两帧相同时不输出任何内容")
    func identicalFramesProduceNothing() {
        let frame = buffer(["hello", "world"], columns: 8)
        #expect(ScreenEncoder.encode(previous: frame, next: frame) == "")
    }

    @Test("单格变化只定位一次光标并写出该字符")
    func singleCellChange() {
        let before = buffer(["hello", "world"], columns: 8)
        let after = buffer(["hello", "wOrld"], columns: 8)
        let output = ScreenEncoder.encode(previous: before, next: after)
        #expect(output.contains("\(esc)[2;2H"))
        #expect(output.contains("O"))
        #expect(cupCount(output) == 1)
        #expect(!output.contains("hello"))
    }

    @Test("同一行相邻的变化合并成一段，只定位一次")
    func adjacentChangesMerge() {
        let before = buffer(["abcdef"], columns: 8)
        let after = buffer(["aXYZef"], columns: 8)
        let output = ScreenEncoder.encode(previous: before, next: after)
        #expect(cupCount(output) == 1)
        #expect(output.contains("XYZ"))
    }

    @Test("样式用 SGR 真彩输出，结尾复位")
    func styledCellUsesTrueColor() {
        var after = CellBuffer(columns: 4, rows: 1)
        after.write("k", row: 0, column: 0, style: CellStyle(foreground: .rgb(0x9C, 0xDC, 0xFE), bold: true))
        let output = ScreenEncoder.encode(previous: CellBuffer(columns: 4, rows: 1), next: after)
        #expect(output.contains("38;2;156;220;254"))
        #expect(output.contains(";1") || output.contains("[1;") || output.contains("[0;1"))
        #expect(output.hasSuffix("\(esc)[0m"))
    }

    @Test("宽字符占两格：后面的字符紧接着输出，不再单独定位")
    func wideCharacterOccupiesTwoColumns() {
        let after = buffer(["中a"], columns: 4)
        #expect(after[0, 0].width == 2)
        #expect(after[0, 1].isContinuation)
        #expect(after[0, 2].text == "a")
        let output = ScreenEncoder.encode(previous: CellBuffer(columns: 4, rows: 1), next: after)
        #expect(output.contains("中a"))
        #expect(cupCount(output) == 1)
    }

    @Test("宽字符放不进行尾最后一格时用空格占位，不越界")
    func wideCharacterAtRowEnd() {
        let after = buffer(["abc中"], columns: 4)
        #expect(after[0, 3].text == " ")
        #expect(after.rowText(0) == "abc ")
    }

    @Test("没有上一帧时整屏重画：每一行都定位一次")
    func fullRedrawWithoutPreviousFrame() {
        let frame = buffer(["one", "two", "three"], columns: 6)
        let output = ScreenEncoder.encode(previous: nil, next: frame)
        #expect(output.contains("\(esc)[1;1H"))
        #expect(output.contains("\(esc)[2;1H"))
        #expect(output.contains("\(esc)[3;1H"))
        #expect(output.contains("three"))
    }

    @Test("带链接的格子用 OSC 8 包起来并在之后关闭")
    func hyperlinkWrapsLinkedCells() {
        var after = CellBuffer(columns: 8, rows: 1)
        after.write("docs", row: 0, column: 0, style: CellStyle(link: "https://example.com"))
        let output = ScreenEncoder.encode(previous: CellBuffer(columns: 8, rows: 1), next: after)
        #expect(output.contains("\(esc)]8;;https://example.com\(esc)\\docs"))
        #expect(output.contains("\(esc)]8;;\(esc)\\"))
    }
}
