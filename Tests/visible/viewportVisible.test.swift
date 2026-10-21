import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - Viewport / TUIReducer 可见样例
//
// 正文区有一个「光标行」（状态栏里的 Ln 指它），视口总是跟着光标：光标移出视口时
// 视口滚到刚好把它露出来。视口位置记为「第几行的第几个折行」，长行折成多行时按可视行滚动。
// 滚轮只滚视口，光标被夹回视口内。翻页、跳到头尾都夹在文档范围里。

/// 12 行终端 = 1 行标题 + 10 行正文 + 1 行状态栏
private func loadedState(lines: [String], rows: Int = 12, columns: Int = 40) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: columns, rows: rows), document: .loading(path: "x.txt"))
    let document = OpenedDocument(
        header: DocumentHeader(displayPath: "x.txt", details: ""),
        store: LineStore(lines.joined(separator: "\n")),
        presentation: .plain
    )
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

private func loadedState(lineCount: Int) -> TUIState {
    loadedState(lines: (1...lineCount).map { "line \($0)" })
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

@Suite("Visible_viewport")
struct Visible_viewport {
    @Test("j 下移光标；光标越过视口底部时视口跟着下滚一行")
    func cursorDownScrollsWhenLeavingViewport() {
        var state = loadedState(lineCount: 100)
        for _ in 0..<10 { _ = press(&state, .character("j")) }
        #expect(state.viewport.cursor == 10)
        #expect(state.viewport.top == ScrollPosition(line: 1, row: 0))
        _ = press(&state, .character("k"))
        #expect(state.viewport.cursor == 9)
        #expect(state.viewport.top.line == 1)
    }

    @Test("翻页与跳到结尾都夹在文档范围内")
    func pagingClampsToDocument() {
        var state = loadedState(lineCount: 25)
        _ = press(&state, .character(" "))
        _ = press(&state, .character(" "))
        _ = press(&state, .character(" "))
        #expect(state.viewport.cursor == 24)
        #expect(state.viewport.top.line == 15)
        _ = press(&state, .character("g"))
        #expect(state.viewport.cursor == 0)
        #expect(state.viewport.top.line == 0)
        _ = press(&state, .character("G"))
        #expect(state.viewport.cursor == 24)
        #expect(state.viewport.top.line == 15)
    }

    @Test("长行折成多行时按可视行计算：光标露出所需的滚动、逐行滚动停在折行中间")
    func wrappedLinesCountAsSeveralRows() {
        // 100 行 → 行号栏 5 列，正文宽 35；第 2 行 80 个字符折成 3 行
        var lines = (1...100).map { "line \($0)" }
        lines[1] = String(repeating: "x", count: 80)
        var state = loadedState(lines: lines)
        for _ in 0..<8 { _ = press(&state, .character("j")) }
        #expect(state.viewport.cursor == 8)
        #expect(state.viewport.top == ScrollPosition(line: 1, row: 0))
        _ = press(&state, .character("y"), .control)
        #expect(state.viewport.top == ScrollPosition(line: 0, row: 0))
        _ = press(&state, .character("e"), .control)
        _ = press(&state, .character("e"), .control)
        #expect(state.viewport.top == ScrollPosition(line: 1, row: 1))
    }

    @Test("滚轮只滚视口，光标被夹回视口内")
    func wheelScrollsViewportAndClampsCursor() {
        var state = loadedState(lineCount: 100)
        _ = TUIReducer.reduce(&state, .input(.mouse(MouseEvent(kind: .scrollDown, row: 3, column: 3, modifiers: []))))
        #expect(state.viewport.top.line == 3)
        #expect(state.viewport.cursor == 3)
    }

    @Test("w 关掉换行后长行只占一行，h / l 水平滚动")
    func wrapToggleAndHorizontalScroll() {
        var lines = (1...20).map { "line \($0)" }
        lines[0] = String(repeating: "y", count: 80)
        var state = loadedState(lines: lines)
        #expect(state.wrapsLines)
        _ = press(&state, .character("w"))
        #expect(!state.wrapsLines)
        _ = press(&state, .character("l"))
        #expect(state.viewport.horizontalOffset > 0)
        _ = press(&state, .character("h"))
        #expect(state.viewport.horizontalOffset == 0)
    }

    @Test("q 与 Ctrl-C 发出退出、Ctrl-Z 发出挂起；打开时带的行号把光标放到该行")
    func quitAndTargetLine() {
        var state = loadedState(lineCount: 5)
        #expect(press(&state, .character("q")) == [.quit])
        #expect(press(&state, .character("c"), .control) == [.quit])
        #expect(press(&state, .character("z"), .control) == [.suspend])

        var targeted = TUIState(size: TerminalSize(columns: 40, rows: 12), document: .loading(path: "x.txt"), targetLine: 50)
        let document = OpenedDocument(
            header: DocumentHeader(displayPath: "x.txt", details: ""),
            store: LineStore((1...100).map { "\($0)" }.joined(separator: "\n")),
            presentation: .plain
        )
        _ = TUIReducer.reduce(&targeted, .loaded(document, generation: targeted.generation))
        #expect(targeted.viewport.cursor == 49)
        #expect(targeted.viewport.top.line <= 49 && 49 < targeted.viewport.top.line + 10)
    }

    @Test("源码文档读入时发出高亮请求；迟到的旧代际高亮结果被丢弃")
    func highlightRequestAndGeneration() {
        var state = TUIState(size: TerminalSize(columns: 40, rows: 12), document: .loading(path: "a.swift"))
        let document = OpenedDocument(
            header: DocumentHeader(displayPath: "a.swift", details: ""),
            store: LineStore("let a = 1"),
            presentation: .source(language: "swift")
        )
        let generation = state.generation
        let effects = TUIReducer.reduce(&state, .loaded(document, generation: generation))
        #expect(effects == [.startHighlight(generation: generation, text: "let a = 1", language: "swift")])
        let chunk = HighlightChunk(firstLine: 0, lines: [[HighlightedToken(text: "let a = 1", colorHex: "#569cd6")]])
        _ = TUIReducer.reduce(&state, .highlighted(chunk, generation: generation + 1))
        guard case let .loaded(stale) = state.document else { Issue.record("document not loaded"); return }
        #expect(stale.highlights.isEmpty)
        _ = TUIReducer.reduce(&state, .highlighted(chunk, generation: generation))
        guard case let .loaded(current) = state.document else { Issue.record("document not loaded"); return }
        #expect(current.highlights[0]?.first?.colorHex == "#569cd6")
    }
}
