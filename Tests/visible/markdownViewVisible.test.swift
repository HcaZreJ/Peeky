import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - Markdown 视图可见样例
//
// 打开 Markdown 时按当前宽度排好版，并发出代码块高亮请求；高亮结果回来后按当前宽度重排。
// 回车打开光标行上的第一个链接：文档内锚点跳到对应标题，其余交给系统打开（相对路径带上文档目录）。
// 重排后光标停在同一个源文件行；状态栏的 Ln 是源文件行号。

private let source = """
# Guide

See [install](#install-steps) or [site](https://example.com).

## Install steps

```py
print(1)
```
"""

private func markdownState(width: Int = 40, rows: Int = 30) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: width, rows: rows), document: .loading(path: "guide.md"))
    let document = OpenedDocument(
        header: DocumentHeader(displayPath: "guide.md", details: ""),
        store: LineStore(source),
        presentation: .markdown,
        markdown: MarkdownLayout.render(source, width: width, theme: .dark),
        baseDirectory: URL(fileURLWithPath: "/docs")
    )
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

private func rowIndex(_ state: TUIState, containing text: String) -> Int? {
    guard case let .loaded(document) = state.document else { return nil }
    return document.markdown?.rows.firstIndex { $0.spans.map(\.text).joined().contains(text) }
}

@Suite("Visible_markdownView")
struct Visible_markdownView {
    @Test("打开 Markdown 发出代码块高亮请求")
    func loadingRequestsCodeHighlighting() {
        var state = TUIState(size: TerminalSize(columns: 40, rows: 30), document: .loading(path: "guide.md"))
        let document = OpenedDocument(
            header: DocumentHeader(displayPath: "guide.md", details: ""),
            store: LineStore(source),
            presentation: .markdown,
            markdown: MarkdownLayout.render(source, width: 40, theme: .dark)
        )
        #expect(TUIReducer.reduce(&state, .loaded(document, generation: state.generation)) == [.highlightMarkdownCode(generation: state.generation, source: source)])
    }

    @Test("回车：文档内锚点跳到对应标题；外部链接交给系统打开")
    func enterActivatesLinks() throws {
        var state = markdownState()
        let linkRow = try #require(rowIndex(state, containing: "See install"))
        state.viewport.cursor = linkRow
        let effects = TUIReducer.reduce(&state, .input(.key(KeyPress(key: .enter))))
        #expect(effects.isEmpty)
        #expect(state.viewport.cursor == rowIndex(state, containing: "Install steps"))

        guard case var .loaded(document) = state.document else { Issue.record("not loaded"); return }
        var rows = try #require(document.markdown?.rows)
        rows[linkRow].links = ["https://example.com"]
        document.markdown?.rows = rows
        state.document = .loaded(document)
        state.viewport.cursor = linkRow
        #expect(TUIReducer.reduce(&state, .input(.key(KeyPress(key: .enter)))) == [.open(target: "https://example.com", baseDirectory: URL(fileURLWithPath: "/docs"))])
    }

    @Test("按新宽度重排后，光标停在同一个源文件行")
    func relayoutKeepsSourceLine() throws {
        var state = markdownState(width: 40)
        let codeRow = try #require(rowIndex(state, containing: "print(1)"))
        state.viewport.cursor = codeRow
        guard case let .loaded(before) = state.document else { Issue.record("not loaded"); return }
        let sourceLine = before.sourceLine(forLine: codeRow)
        _ = TUIReducer.reduce(&state, .resized(TerminalSize(columns: 20, rows: 30)))
        _ = TUIReducer.reduce(&state, .markdownLaidOut(MarkdownLayout.render(source, width: 20, theme: .dark), generation: state.generation))
        guard case let .loaded(after) = state.document else { Issue.record("not loaded"); return }
        #expect(after.markdown?.width == 20)
        #expect(after.sourceLine(forLine: state.viewport.cursor) == sourceLine)
    }

    @Test("代码块高亮回来后按当前宽度发出重排")
    func codeTokensTriggerRelayout() {
        var state = markdownState(width: 40)
        let tokens: [Int: [[HighlightedToken]]] = [0: [[HighlightedToken(text: "print(1)", colorHex: "#dcdcaa")]]]
        let effects = TUIReducer.reduce(&state, .markdownCodeHighlighted(tokens, generation: state.generation))
        #expect(effects == [.layoutMarkdown(generation: state.generation, source: source, width: 40, codeTokens: tokens, appearance: .dark)])
    }

    @Test("围栏语言名换算成 shiki 语言", arguments: [
        ("py", "python"), ("python", "python"), ("Shell", "bash"), ("ts", "typescript"), ("rust", nil), (nil, nil),
    ] as [(String?, String?)])
    func fenceLanguage(fence: String?, expected: String?) {
        #expect(CodeFenceLanguage.shikiLanguage(for: fence) == expected)
    }

    @Test("状态栏的 Ln 是源文件行号")
    func statusShowsSourceLine() throws {
        var state = markdownState()
        state.viewport.cursor = try #require(rowIndex(state, containing: "print(1)"))
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(29).contains("Ln 8/9"))
    }
}
