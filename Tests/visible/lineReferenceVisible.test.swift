import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 「路径:行号」可见样例
//
// L 复制「绝对路径:行号」（与 app 的 path:line chip 一致）：行号取选区起点所在的源行，没有选区时
// 取光标行，1 起算。Markdown 取排版行的来源行，JSON 折叠后取源行。有选区时状态栏左侧显示
// 「L 复制 路径:行号」，路径太长时从左边截断、保留行号。

private let file = URL(fileURLWithPath: "/repo/docs/notes.txt")

private func state(_ document: OpenedDocument, columns: Int = 80) -> TUIState {
    var state = TUIState.launching(
        size: TerminalSize(columns: columns, rows: 12),
        target: file,
        isDirectory: false,
        displayPath: "repo/docs/notes.txt",
        treeRoot: URL(fileURLWithPath: "/repo"),
        targetLine: nil
    )
    state.sidebar = nil
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

private func plainDocument() -> OpenedDocument {
    OpenedDocument(
        header: DocumentHeader(displayPath: "repo/docs/notes.txt", details: ""),
        store: LineStore((1...30).map { "line \($0)" }.joined(separator: "\n")),
        presentation: .plain
    )
}

private func pressL(_ state: inout TUIState) -> String? {
    for effect in TUIReducer.reduce(&state, .input(.key(KeyPress(key: .character("L"), modifiers: .shift)))) {
        if case let .copy(text, _) = effect { return text }
    }
    return nil
}

private func select(_ state: inout TUIState, line: Int, through endLine: Int) {
    state.selection = TextSelection(anchor: TextPoint(line: line, column: 0), head: TextPoint(line: endLine, column: 3))
}

@Suite("Visible_lineReference")
struct Visible_lineReference {
    @Test("没有选区时 L 复制光标行；有选区时取选区起点所在行（倒着拖也是）")
    func copiesCursorOrSelectionStart() {
        var current = state(plainDocument())
        current.viewport.cursor = 6
        #expect(pressL(&current) == "/repo/docs/notes.txt:7")
        select(&current, line: 12, through: 9)
        #expect(pressL(&current) == "/repo/docs/notes.txt:10")
        #expect(current.toast == "已复制路径:行号")
    }

    @Test("Markdown 取排版行的来源行")
    func markdownUsesSourceLine() {
        let text = "# Title\n\nalpha\n\nbeta gamma"
        var current = state(OpenedDocument(
            header: DocumentHeader(displayPath: "notes.md", details: ""),
            store: LineStore(text),
            presentation: .markdown,
            markdown: MarkdownLayout.render(text, width: 80, theme: .dark)
        ))
        let rows = try! #require({ if case let .loaded(document) = current.document { return document.markdown?.rows }; return nil }())
        let betaRow = try! #require(rows.firstIndex { $0.spans.map(\.text).joined().contains("beta") })
        select(&current, line: betaRow, through: betaRow)
        #expect(pressL(&current) == "/repo/docs/notes.txt:5")
    }

    @Test("JSON 折叠后取源行")
    func foldedJSONUsesSourceLine() {
        let pretty = "{\n  \"a\": {\n    \"x\": 1\n  },\n  \"b\": 2\n}"
        var current = state(OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore(pretty),
            presentation: .json(structureIsValid: true),
            json: JSONView(prettyText: pretty, structureIsValid: true)
        ))
        current.viewport.cursor = 1
        _ = TUIReducer.reduce(&current, .input(.key(KeyPress(key: .enter))))
        current.viewport.cursor = 2
        #expect(pressL(&current) == "/repo/docs/notes.txt:5")
    }

    @Test("有选区时状态栏显示「L 复制 路径:行号」，路径太长时左边截断、保留行号；没有选区时不显示")
    func statusBarShowsReferenceForSelection() {
        var current = state(plainDocument())
        #expect(!FrameRenderer.render(current).rowText(11).contains("L 复制"))
        select(&current, line: 3, through: 4)
        #expect(FrameRenderer.render(current).rowText(11).hasPrefix(" L 复制 /repo/docs/notes.txt:4 "))

        var narrow = state(plainDocument(), columns: 64)
        select(&narrow, line: 3, through: 4)
        let status = FrameRenderer.render(narrow).rowText(11)
        #expect(status.hasPrefix(" L 复制 …"))
        #expect(status.contains("notes.txt:4 "))
    }
}
