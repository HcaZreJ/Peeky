import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 选区与复制可见样例
//
// 选区按「显示行 + 视觉列」记录（视觉列 = 展开制表符、不折行时的列），滚动和换行开关都不影响它。
// 复制时：不同行之间用换行，同一行的软换行直接拼接；制表符原样复制；行号栏、项目符号、引用竖线、
// 左边距等装饰不复制，Markdown 段落的软换行接回成一行；JSON 折叠态复制展开后的完整内容。
// 鼠标拖动选中，双击选词、三击选整行，Esc 取消；状态栏显示「选中 N 字符」，y 复制后提示「已复制 N 字符」。

private func lineState(_ text: String, columns: Int = 40, rows: Int = 8) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: columns, rows: rows), document: .loading(path: "notes.txt"))
    let document = OpenedDocument(
        header: DocumentHeader(displayPath: "notes.txt", details: ""),
        store: LineStore(text),
        presentation: .plain
    )
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

private func mouse(_ state: inout TUIState, _ kind: MouseEvent.Kind, row: Int, column: Int, clicks: Int = 1) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.mouse(MouseEvent(kind: kind, row: row, column: column, modifiers: [], clickCount: clicks))))
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

private func copiedText(_ effects: [TUIEffect]) -> String? {
    for effect in effects {
        if case let .copy(text, _) = effect { return text }
    }
    return nil
}

private func selectionText(_ state: TUIState) -> String? {
    guard case let .loaded(document) = state.document, let selection = state.selection else { return nil }
    let layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines)
    return SelectionText.text(selection, layout: layout)
}

@Suite("Visible_selectionText")
struct Visible_selectionText {
    @Test("拖动选中一段文字：状态栏显示选中字数，y 复制并提示，Esc 取消")
    func dragSelectCopyAndCancel() {
        var state = lineState("alpha beta\nsecond line")
        // 行号栏 3 列：屏幕第 3 列是正文第 0 列
        _ = mouse(&state, .press(.left), row: 1, column: 3)
        _ = mouse(&state, .drag(.left), row: 1, column: 8)
        _ = mouse(&state, .release(.left), row: 1, column: 8)
        #expect(selectionText(state) == "alpha")
        #expect(FrameRenderer.render(state).rowText(7).contains("选中 5 字符"))
        #expect(FrameRenderer.render(state)[1, 3].style.background == ChromeColors.dark.selection)
        let effects = press(&state, .character("y"))
        #expect(copiedText(effects) == "alpha")
        #expect(state.toast == "已复制 5 字符")
        _ = press(&state, .escape)
        #expect(state.selection == nil)
    }

    @Test("跨行选区：行与行之间是换行；软换行处直接拼接")
    func multiLineAndSoftWrap() {
        var state = lineState("first line\nsecond line\nthird line")
        _ = mouse(&state, .press(.left), row: 1, column: 3 + 6)
        _ = mouse(&state, .drag(.left), row: 3, column: 3 + 5)
        #expect(selectionText(state) == "line\nsecond line\nthird")

        let long = String(repeating: "abcdefghij", count: 4)
        state = lineState(long, columns: 23)
        // 正文宽 20：第 2 个可视行从第 20 列开始
        _ = mouse(&state, .press(.left), row: 1, column: 3 + 15)
        _ = mouse(&state, .drag(.left), row: 2, column: 3 + 5)
        #expect(selectionText(state) == "fghijabcde")
    }

    @Test("制表符按显示列换回原文，原样复制")
    func tabsCopiedVerbatim() {
        var state = lineState("a\tb")
        _ = mouse(&state, .press(.left), row: 1, column: 3)
        _ = mouse(&state, .drag(.left), row: 1, column: 3 + 5)
        #expect(selectionText(state) == "a\tb")
    }

    @Test("Markdown：项目符号、引用竖线、左边距不复制，段落的软换行接回成一行")
    func markdownSkipsDecorations() {
        let text = "- first item\n- second\n\n> quoted text\n\nalpha beta gamma delta"
        var state = TUIState(size: TerminalSize(columns: 20, rows: 14), document: .loading(path: "a.md"))
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "a.md", details: ""),
            store: LineStore(text),
            presentation: .markdown,
            markdown: MarkdownLayout.render(text, width: 20, theme: .dark)
        ), generation: state.generation))
        guard case let .loaded(document) = state.document, let rows = document.markdown?.rows else {
            Issue.record("not loaded"); return
        }
        state.selection = TextSelection(anchor: TextPoint(line: 0, column: 0), head: TextPoint(line: rows.count - 1, column: .max))
        #expect(selectionText(state) == "first item\nsecond\n\nquoted text\n\nalpha beta gamma delta")
    }

    @Test("JSON 折叠态：选中折叠行，复制展开后的完整内容")
    func foldedJSONCopiesExpandedSource() {
        let pretty = "{\n  \"users\" : [\n    {\n      \"name\" : \"peek\"\n    }\n  ]\n}"
        var state = TUIState(size: TerminalSize(columns: 50, rows: 12), document: .loading(path: "x.json"))
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore(pretty),
            presentation: .json(structureIsValid: true),
            json: JSONView(prettyText: pretty, structureIsValid: true)
        ), generation: state.generation))
        _ = press(&state, .character("j"))
        _ = press(&state, .enter)
        let effects = press(&state, .character("y"))
        #expect(copiedText(effects) == "  \"users\" : [\n    {\n      \"name\" : \"peek\"\n    }\n  ]")
    }

    @Test("双击选中一个词，三击选中整行")
    func doubleAndTripleClick() {
        var state = lineState("alpha beta\nsecond")
        _ = mouse(&state, .press(.left), row: 1, column: 3 + 7, clicks: 2)
        #expect(selectionText(state) == "beta")
        _ = mouse(&state, .press(.left), row: 1, column: 3 + 7, clicks: 3)
        #expect(selectionText(state) == "alpha beta")
    }

    @Test("没有选中时 y 复制光标所在行；Y 从磁盘读原文复制全文")
    func copyLineAndWholeFile() {
        var state = TUIState.launching(
            size: TerminalSize(columns: 60, rows: 10),
            target: URL(fileURLWithPath: "/repo/notes.txt"),
            isDirectory: false,
            displayPath: "notes.txt",
            treeRoot: URL(fileURLWithPath: "/repo"),
            targetLine: nil
        )
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "notes.txt", details: ""),
            store: LineStore("one\ntwo"),
            presentation: .plain
        ), generation: state.generation))
        _ = press(&state, .character("j"))
        #expect(copiedText(press(&state, .character("y"))) == "two")
        #expect(press(&state, .character("Y")).contains(.copyFileText(URL(fileURLWithPath: "/repo/notes.txt"))))
        #expect(state.toast == "已复制全文")
    }

    @Test("提示 2 秒后消失；更晚的提示不被前一个计时清掉")
    func toastExpires() {
        var state = lineState("alpha")
        let first = press(&state, .character("y"))
        let token = first.compactMap { effect -> Int? in
            if case let .expireToast(token) = effect { return token }
            return nil
        }.first
        #expect(token != nil)
        _ = TUIReducer.reduce(&state, .toastExpired(token ?? -1))
        #expect(state.toast == nil)
        _ = press(&state, .character("y"))
        _ = TUIReducer.reduce(&state, .toastExpired(token ?? -1))
        #expect(state.toast != nil)
    }
}
