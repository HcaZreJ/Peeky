import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - FrameRenderer 可见样例
//
// 把 TUIState 画成一帧 CellBuffer：第一行是标题（路径 + 详情），最后一行是状态栏
// （Ln 当前行/总行数），中间是正文。正文左侧是行号栏，软换行的续行不编号；光标行带背景色；
// 源码视图整栏铺 Dark Modern 背景，高亮 token 用 shiki 给的颜色。读取中与读取失败各有提示。

private func state(lines: [String], rows: Int = 5, columns: Int = 30, presentation: Presentation = .plain) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: columns, rows: rows), document: .loading(path: "notes.txt"))
    let document = OpenedDocument(
        header: DocumentHeader(displayPath: "notes.txt", details: "Text · 1 KB"),
        store: LineStore(lines.joined(separator: "\n")),
        presentation: presentation
    )
    _ = TUIReducer.reduce(&state, .loaded(document, generation: state.generation))
    return state
}

@Suite("Visible_frameRenderer")
struct Visible_frameRenderer {
    @Test("首行是标题，正文带行号从视口顶端开始画")
    func titleAndNumberedContent() {
        var current = state(lines: ["first", "second", "third", "fourth"])
        current.viewport = Viewport(top: ScrollPosition(line: 1, row: 0), cursor: 1)
        let frame = FrameRenderer.render(current)
        #expect(frame.rowText(0).contains("notes.txt"))
        #expect(frame.rowText(0).contains("Text · 1 KB"))
        #expect(frame.rowText(1).hasPrefix(" 2 second"))
        #expect(frame.rowText(3).hasPrefix(" 4 fourth"))
    }

    @Test("软换行的续行不编号")
    func continuationRowsHaveNoNumber() {
        let frame = FrameRenderer.render(state(lines: [String(repeating: "x", count: 40), "tail"], rows: 6))
        #expect(frame.rowText(1).hasPrefix(" 1 xxxx"))
        #expect(frame.rowText(2).hasPrefix("   xxxx"))
        #expect(frame.rowText(3).hasPrefix(" 2 tail"))
    }

    @Test("光标行带背景色，其它行没有")
    func cursorLineHasBackground() {
        let frame = FrameRenderer.render(state(lines: ["one", "two", "three"]))
        #expect(frame[1, 5].style.background != .default)
        #expect(frame[1, 25].style.background != .default)
        #expect(frame[2, 5].style.background == .default)
    }

    @Test("最后一行是状态栏：Ln 当前行/总行数")
    func statusBarShowsLine() {
        let frame = FrameRenderer.render(state(lines: ["one", "two", "three"]))
        #expect(frame.rowText(4).contains("Ln 1/3"))
    }

    @Test("源码视图铺 Dark Modern 背景，高亮 token 用 shiki 的颜色")
    func sourceViewUsesHighlightColors() {
        var current = state(lines: ["let a = 1", ""], presentation: .source(language: "swift"))
        _ = TUIReducer.reduce(&current, .highlighted(
            HighlightChunk(firstLine: 0, lines: [[HighlightedToken(text: "let", colorHex: "#569cd6"), HighlightedToken(text: " a = 1", colorHex: "#cccccc")]]),
            generation: current.generation
        ))
        let frame = FrameRenderer.render(current)
        #expect(frame[1, 3].style.foreground == .rgb(0x56, 0x9C, 0xD6))
        #expect(frame[2, 10].style.background == .rgb(0x1F, 0x1F, 0x1F))
    }

    @Test("读取中与读取失败各显示提示")
    func loadingAndFailureMessages() {
        let loading = FrameRenderer.render(TUIState(size: TerminalSize(columns: 30, rows: 5), document: .loading(path: "big.json")))
        #expect(loading.rowText(1).contains("正在读取"))
        let failed = FrameRenderer.render(TUIState(size: TerminalSize(columns: 30, rows: 5), document: .failed(message: "没有这个文件")))
        #expect(failed.rowText(1).contains("没有这个文件"))
    }
}
