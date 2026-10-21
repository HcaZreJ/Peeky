import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - JSON 视图可见样例
//
// JSON / JSONL 视图复用 app 的 JSONFormatter / JSONHighlighter / JSONFoldMap / JSONFoldComposer /
// JSONPathMap：只给屏幕上的行着色；回车或点行号栏的三角折叠 / 展开（折起来的内容显示为 ⟷ 占位），
// 行号是源文件行号；状态栏常驻光标行的 jq 路径，J / D 复制 jq 表达式 / 点分路径；
// M / R 全部折叠 / 展开（根容器不折）；JSONL 坏行整行标红、行号栏显示「!」；缩进处画导轨。

private let pretty = """
{
  "users" : [
    {
      "name" : "peek"
    }
  ]
}
"""

private func jsonState(_ text: String = pretty, invalidLines: Set<Int> = [], presentation: Presentation = .json(structureIsValid: true)) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: 50, rows: 12), document: .loading(path: "x.json"))
    let document = OpenedDocument(
        header: DocumentHeader(displayPath: "x.json", details: ""),
        store: LineStore(text),
        presentation: presentation,
        json: JSONView(prettyText: text, structureIsValid: true, invalidSourceLines: invalidLines)
    )
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

@Suite("Visible_jsonView")
struct Visible_jsonView {
    @Test("键名与字符串各自着色")
    func tokenColoring() {
        let spans = JSONLineColoring.spans(for: "      \"name\" : \"peek\"", appearance: .dark, baseStyle: .plain)
        #expect(spans.first { $0.text == "\"name\"" }?.style.foreground == TerminalPalette.color(.jsonKey))
        #expect(spans.first { $0.text == "\"peek\"" }?.style.foreground == TerminalPalette.color(.jsonString))
    }

    @Test("回车折叠 / 展开当前行的容器，行号栏三角跟着变，折起来的内容显示为 ⟷")
    func enterTogglesFold() {
        var state = jsonState()
        _ = press(&state, .character("j"))
        _ = press(&state, .enter)
        var frame = FrameRenderer.render(state)
        #expect(frame.rowText(2).contains("▸"))
        #expect(frame.rowText(2).contains("⟷"))
        #expect(frame.rowText(3).contains("}"))
        #expect(frame.rowText(3).hasPrefix(" 7"))
        _ = press(&state, .enter)
        frame = FrameRenderer.render(state)
        #expect(frame.rowText(2).contains("▾"))
        #expect(frame.rowText(3).contains("{"))
    }

    @Test("折叠包含光标的容器时，光标回到该容器的开头行")
    func cursorMovesToCollapsedRegion() {
        var state = jsonState()
        for _ in 0..<3 { _ = press(&state, .character("j")) }
        _ = press(&state, .character("M"))
        guard case let .loaded(document) = state.document else { Issue.record("not loaded"); return }
        #expect(document.json?.sourceLine(forDisplayLine: state.viewport.cursor) == 1)
    }

    @Test("状态栏常驻光标行的 jq 路径")
    func statusShowsJQPath() {
        var state = jsonState()
        for _ in 0..<3 { _ = press(&state, .character("j")) }
        #expect(FrameRenderer.render(state).rowText(11).contains(".users[0].name"))
    }

    @Test("J 复制 jq 表达式，D 复制点分路径")
    func copyPaths() {
        var state = jsonState()
        for _ in 0..<3 { _ = press(&state, .character("j")) }
        #expect(press(&state, .character("J")).contains(.copy(text: ".users[0].name", description: "jq 路径")))
        #expect(state.toast == "已复制 jq 路径")
        #expect(press(&state, .character("D")).contains(.copy(text: "users.0.name", description: "点分路径")))
        #expect(state.toast == "已复制点分路径")
    }

    @Test("M 折叠根以外的所有容器，R 全部展开")
    func collapseAndExpandAll() {
        var state = jsonState()
        _ = press(&state, .character("M"))
        guard case let .loaded(collapsed) = state.document else { Issue.record("not loaded"); return }
        #expect(DocumentLayout(document: collapsed, columns: 50, wrapsLines: true).lineCount == 3)
        _ = press(&state, .character("R"))
        guard case let .loaded(expanded) = state.document else { Issue.record("not loaded"); return }
        #expect(DocumentLayout(document: expanded, columns: 50, wrapsLines: true).lineCount == 7)
    }

    @Test("JSONL 坏行整行标红，行号栏显示 !")
    func invalidLinesMarked() {
        let text = "{\n  \"a\" : 1\n}\n\nnot json"
        let state = jsonState(text, invalidLines: [4], presentation: .jsonLines)
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(5).contains("!"))
        #expect(frame[5, 20].style.background == TerminalPalette.color(.invalidLineBackground))
        // 带透明度的底色叠在编辑器底色上，不会是不透明的纯红
        #expect(TerminalPalette.color(.invalidLineBackground) != .rgb(0xF8, 0x51, 0x49))
    }

    @Test("索引晚到：先显示着色文本，索引到达后补上折叠与路径，视口不动")
    func lateIndexAttachesWithoutMovingViewport() {
        var state = TUIState(size: TerminalSize(columns: 50, rows: 12), document: .loading(path: "x.json"))
        let document = OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore(pretty),
            presentation: .json(structureIsValid: true)
        )
        _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
        for _ in 0..<3 { _ = press(&state, .character("j")) }
        #expect(!FrameRenderer.render(state).rowText(11).contains(".users"))
        #expect(FrameRenderer.render(state).rowText(11).hasPrefix(" 正在建立折叠索引…"))
        _ = TUIReducer.reduce(&state, .jsonIndexed(JSONView(prettyText: pretty, structureIsValid: true), generation: state.generation))
        #expect(state.viewport.cursor == 3)
        #expect(FrameRenderer.render(state).rowText(11).contains(".users[0].name"))
        #expect(!FrameRenderer.render(state).rowText(11).contains("正在"))
    }

    @Test("大文件先显示原文时，状态栏左侧提示正在格式化")
    func interimRawTextShowsFormattingNote() {
        var state = TUIState(size: TerminalSize(columns: 50, rows: 12), document: .loading(path: "x.json"))
        let interim = OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore("{\"users\":[{\"name\":\"peek\"}]}"),
            presentation: .plain,
            prefersWrapping: false,
            formattingPending: true
        )
        _ = TUIReducer.reduce(&state, .loaded(interim, generation: state.generation))
        #expect(FrameRenderer.render(state).rowText(11).hasPrefix(" 正在格式化…"))
    }

    @Test("带行号打开大文件：原文阶段不跳，格式化后的文档到达后跳到目标行")
    func targetLineWaitsForFormattedDocument() {
        var state = TUIState(size: TerminalSize(columns: 50, rows: 12), document: .loading(path: "x.json"), targetLine: 4)
        let interim = OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore("{\"users\":[{\"name\":\"peek\"}]}"),
            presentation: .plain,
            prefersWrapping: false,
            formattingPending: true
        )
        _ = TUIReducer.reduce(&state, .loaded(interim, generation: state.generation))
        #expect(state.viewport.cursor == 0)
        let formatted = OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore(pretty),
            presentation: .json(structureIsValid: true)
        )
        _ = TUIReducer.reduce(&state, .loaded(formatted, generation: state.generation))
        #expect(state.viewport.cursor == 3)
    }

    @Test("缩进处画导轨，字符本身不变")
    func indentGuides() {
        let spans = JSONLineColoring.spans(for: "      \"name\" : \"peek\"", appearance: .dark, baseStyle: .plain)
        let text = spans.map(\.text).joined()
        #expect(text.hasPrefix("│ │ │ "))
        #expect(text.hasSuffix("\"name\" : \"peek\""))
    }
}
