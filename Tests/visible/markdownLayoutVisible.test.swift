import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - MarkdownLayout 可见样例
//
// Markdown 按终端宽度排成屏幕行：左右各留 2 列边距；块与块之间空一行。
// 标题不放大时：H1 整行铺标题底色、H2 下方一行分隔线、H3 强调色粗体。列表按层级换项目符号，
// 任务列表用 [ ] / [✓]；引用每层前缀 ▎；代码块铺底色，有高亮结果时按 token 上色；
// 表格画框线；链接带 OSC 8 地址；每一行记着它来自源文件的第几行。

private let theme = MarkdownTheme.dark

private func rows(_ source: String, width: Int = 40, codeTokens: [Int: [[HighlightedToken]]] = [:]) -> [MarkdownRow] {
    MarkdownLayout.render(source, width: width, theme: theme, codeTokens: codeTokens).rows
}

private func text(_ row: MarkdownRow) -> String {
    row.spans.map(\.text).joined()
}

@Suite("Visible_markdownLayout")
struct Visible_markdownLayout {
    @Test("标题：H1 整行底色、H2 带分隔线、块之间空一行")
    func headings() {
        let laid = rows("# Title\n\n## Sub\n\ntext")
        #expect(text(laid[0]).trimmingCharacters(in: .whitespaces) == "Title")
        #expect(laid[0].fill?.style.background == theme.headingBar)
        #expect(laid[0].spans.contains { $0.style.bold })
        #expect(text(laid[1]).isEmpty)
        #expect(text(laid[2]).trimmingCharacters(in: .whitespaces) == "Sub")
        #expect(text(laid[3]).trimmingCharacters(in: .whitespaces).allSatisfy { $0 == "─" })
        #expect(text(laid[5]).trimmingCharacters(in: .whitespaces) == "text")
        #expect(laid[0].anchor == "title")
    }

    @Test("段落按词折行，左边距 2 列")
    func paragraphWraps() {
        let laid = rows("one two three four five six seven", width: 20)
        #expect(laid.count == 3)
        #expect(laid.allSatisfy { text($0).hasPrefix("  ") })
        #expect(laid.allSatisfy { TextWidth.width(of: text($0)) <= 18 })
    }

    @Test("嵌套列表按层级换项目符号，有序列表编号")
    func lists() {
        let laid = rows("- a\n  - b\n\n1. one\n2. two").map { text($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(laid == ["• a", "◦ b", "1. one", "2. two"])
    }

    @Test("任务列表用 [ ] 与 [✓]")
    func taskList() {
        let laid = rows("- [ ] todo\n- [x] done").map { text($0).trimmingCharacters(in: .whitespaces) }
        #expect(laid == ["[ ] todo", "[✓] done"])
    }

    @Test("嵌套引用每层一个 ▎ 前缀")
    func nestedQuotes() {
        let laid = rows("> outer\n>\n> > inner").map { text($0).trimmingCharacters(in: .whitespaces) }.filter { $0 != "▎" }
        #expect(laid.first == "▎ outer")
        #expect(laid.last == "▎ ▎ inner")
    }

    @Test("代码块铺底色；有高亮结果时按 token 上色")
    func codeBlock() {
        let source = "```swift\nlet a = 1\n```"
        let plain = rows(source)
        #expect(plain.contains { text($0).contains("let a = 1") && $0.fill?.style.background == theme.codeBlockBackground })
        let colored = rows(source, codeTokens: [0: [[HighlightedToken(text: "let", colorHex: "#569cd6"), HighlightedToken(text: " a = 1", colorHex: "#cccccc")]]])
        let codeRow = colored.first { text($0).contains("let a = 1") }
        #expect(codeRow?.spans.contains { $0.text == "let" && $0.style.foreground == .rgb(0x56, 0x9C, 0xD6) } == true)
        #expect(MarkdownLayout.codeBlocks(in: source) == [MarkdownCodeBlock(index: 0, code: "let a = 1", language: "swift")])
    }

    @Test("代码块长行在空格处软折行，续行以 ↪ 开头并对齐原缩进；复制仍是原文")
    func codeBlockSoftWrap() {
        let laidOut = rows("```\n  alpha beta gamma delta\n```", width: 20)
        let code = laidOut.filter { $0.fill?.style.background == theme.codeBlockBackground }
        // 左边距 2 列 + 代码块内边距 1 列；续行先补原行的 2 格缩进再画 ↪
        let trimmed = code.map { text($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        #expect(trimmed == ["     alpha beta", "     ↪ gamma", "     ↪ delta"])
        let selection = TextSelection(anchor: TextPoint(line: 0, column: 0), head: TextPoint(line: laidOut.count - 1, column: .max))
        #expect(SelectionText.markdownText(selection, rows: laidOut) == "  alpha beta gamma delta")
    }

    @Test("表格画框线，中英混排竖线对齐")
    func table() {
        let laid = rows("| 名称 | 说明 |\n|---|---|\n| peek | 终端查看器 |").map(text)
        let tableLines = laid.filter { line in line.contains { "│┌├└".contains($0) } }
        #expect(tableLines.count == 5)
        #expect(Set(tableLines.map { TextWidth.width(of: $0) }).count == 1)
    }

    @Test("链接带地址；每一行记着来源行号")
    func linksAndSourceLines() {
        let laid = rows("first\n\nsee [docs](https://example.com) here")
        #expect(laid[0].sourceLine == 0)
        let linkRow = laid[2]
        #expect(linkRow.sourceLine == 2)
        #expect(linkRow.spans.contains { $0.text == "docs" && $0.style.link == "https://example.com" && $0.style.underline })
        #expect(linkRow.links == ["https://example.com"])
    }
}
