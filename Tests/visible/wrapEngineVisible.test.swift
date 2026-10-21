import Testing
@testable import PeekTUI

// MARK: - WrapEngine 可见样例
//
// 正文按词折行：西文在空格处断，CJK 在任意两个字之间可断，行首不出现「，。、；：？！）」』」
// 这类收尾标点（回退一个字一起换行），超过一整行的长词硬断，换行处的空格不带到下一行。

private func wrapped(_ text: String, _ width: Int) -> [String] {
    WrapEngine.wrap([StyledSpan(text: text, style: .plain)], width: width).map { $0.map(\.text).joined() }
}

@Suite("Visible_wrapEngine")
struct Visible_wrapEngine {
    @Test("西文在空格处断，换行处的空格不带到下一行")
    func latinBreaksAtSpaces() {
        #expect(wrapped("the quick brown fox", 10) == ["the quick", "brown fox"])
        #expect(wrapped("aaa bbb", 3) == ["aaa", "bbb"])
    }

    @Test("CJK 在任意两个字之间可断")
    func cjkBreaksAnywhere() {
        #expect(wrapped("一二三四五六", 4) == ["一二", "三四", "五六"])
    }

    @Test("中英混排：西文词整体放不下时整词换行")
    func mixedScripts() {
        #expect(wrapped("用 peek 查看", 6) == ["用", "peek", "查看"])
        #expect(wrapped("查看peek文件", 8) == ["查看peek", "文件"])
    }

    @Test("收尾标点不落在行首：回退一个字一起换行")
    func closingPunctuationNotAtLineStart() {
        #expect(wrapped("一二三，四", 6) == ["一二", "三，四"])
        // 连着的收尾标点（「）。」）放不下时，连同前面的词一起换行，不让「）」落在行首
        #expect(wrapped("ab cd）。", 8) == ["ab", "cd）。"])
    }

    @Test("超过一整行的长词硬断")
    func longWordHardBreaks() {
        #expect(wrapped("abcdefghij", 4) == ["abcd", "efgh", "ij"])
    }

    @Test("西文标点属于所在的词，不会从词中间断开")
    func asciiPunctuationStaysInWord() {
        #expect(wrapped("see .hg now", 6) == ["see", ".hg", "now"])
        #expect(wrapped("path[:line] ok", 11) == ["path[:line]", "ok"])
    }

    @Test("折行保留每段样式")
    func stylesSurviveWrapping() {
        let rows = WrapEngine.wrap([StyledSpan(text: "hello", style: CellStyle(bold: true)), StyledSpan(text: " world", style: .plain)], width: 6)
        #expect(rows.map { $0.map(\.text).joined() } == ["hello", "world"])
        #expect(rows[0].first?.style.bold == true)
        #expect(rows[1].first?.style.bold == false)
    }
}
