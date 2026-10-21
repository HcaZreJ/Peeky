import Testing
@testable import PeekTUI

// MARK: - LineStore / LineLayout 可见样例
//
// LineStore 只存全文与每行起点，取行时才切片：结尾换行不多出空行，CRLF 去掉 \r。
// LineLayout 处理一行带样式片段的显示：按格宽折行（宽字符不拆开）、制表符跨片段展开、
// 不换行时按列偏移水平截取（截到半个宽字符补空格），以及行号栏宽度。

private func text(_ rows: [[StyledSpan]]) -> [String] {
    rows.map { $0.map(\.text).joined() }
}

@Suite("Visible_lineLayout")
struct Visible_lineLayout {
    @Test("按行切分：结尾换行不多出空行，CRLF 去掉 \\r，空文本是一行空行")
    func lineStoreSplitting() {
        let store = LineStore("one\r\ntwo\n\nfour\n")
        #expect(store.count == 4)
        #expect(store.line(0) == "one")
        #expect(store.line(2) == "")
        #expect(store.line(3) == "four")
        #expect(LineStore("").count == 1)
        #expect(LineStore("no newline").count == 1)
    }

    @Test("按格宽折行，宽字符不拆到两行")
    func wrapByColumns() {
        let rows = LineLayout.wrap([StyledSpan(text: "abcdef中文gh", style: .plain)], width: 4)
        #expect(text(rows) == ["abcd", "ef中", "文gh"])
        #expect(LineLayout.rowCount(of: "abcdef中文gh", width: 4) == 3)
        #expect(LineLayout.rowCount(of: "", width: 4) == 1)
    }

    @Test("折行保留每段的样式")
    func wrapKeepsStyles() {
        let keyword = CellStyle(foreground: .rgb(0x56, 0x9C, 0xD6))
        let rows = LineLayout.wrap([StyledSpan(text: "let ", style: keyword), StyledSpan(text: "value", style: .plain)], width: 6)
        #expect(text(rows) == ["let va", "lue"])
        #expect(rows[0].first?.style == keyword)
        #expect(rows[1].first?.style == .plain)
    }

    @Test("代码行在空格、/ 或中文字之后断开，不让收尾标点落到续行开头；找不到断点时硬断")
    func codeWrap() {
        let spans = [StyledSpan(text: "ab cd/efgh", style: .plain)]
        #expect(text(LineLayout.wrapCode(spans, firstWidth: 7, continuationWidth: 7)) == ["ab cd/", "efgh"])
        let cjk = [StyledSpan(text: "一二三) x", style: .plain)]
        #expect(text(LineLayout.wrapCode(cjk, firstWidth: 6, continuationWidth: 6)) == ["一二", "三) x"])
        #expect(text(LineLayout.wrapCode([StyledSpan(text: "abcdefgh", style: .plain)], firstWidth: 3, continuationWidth: 3)) == ["abc", "def", "gh"])
    }

    @Test("制表符按 4 列制表位跨片段展开")
    func tabsExpandAcrossSpans() {
        let spans = LineLayout.expandTabs([StyledSpan(text: "ab", style: .plain), StyledSpan(text: "\tc", style: CellStyle(bold: true))])
        #expect(spans.map(\.text).joined() == "ab  c")
        #expect(spans.last?.style.bold == true)
    }

    @Test("水平截取：从第 N 列起取固定列宽，截到半个宽字符时补空格")
    func clipHorizontally() {
        let spans = [StyledSpan(text: "ab中cd", style: .plain)]
        #expect(text([LineLayout.clip(spans, from: 1, width: 3)]) == ["b中"])
        #expect(text([LineLayout.clip(spans, from: 3, width: 3)]) == [" cd"])
    }

    @Test("行号栏宽度 = 最大行号的位数 + 2", arguments: [(9, 3), (10, 4), (1234, 6)] as [(Int, Int)])
    func gutterWidth(lineCount: Int, expected: Int) {
        #expect(LineLayout.gutterWidth(lineCount: lineCount) == expected)
    }
}
