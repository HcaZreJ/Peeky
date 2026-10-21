import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 放大标题可见样例
//
// 终端支持 kitty 文字尺寸协议（OSC 66）时，H1 用 2 倍字、H2 用 2 倍格子里 3/4 的字号；
// 每个折行占两行，按一半宽度折行。标题块的上沿滚出视口、或下沿被视口截断时，这一帧改画普通样式。
// 编码时含放大块的行有变化就整行清掉重画，不在放大格上写普通字（kitty 会擦掉整个大字）。
// 启动探测：打一个 2 倍空格后问光标位置，光标前进 2 格说明支持。

private let source = "# Title\n\nbody text\n\n## Sub\n\nmore"

private func markdownState(scaled: Bool, rows: Int = 10) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: 40, rows: rows), document: .loading(path: "a.md"))
    state.supportsTextSizing = scaled
    _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
        header: DocumentHeader(displayPath: "a.md", details: ""),
        store: LineStore(source),
        presentation: .markdown,
        markdown: MarkdownLayout.render(source, width: 40, theme: .dark, scaledHeadings: scaled)
    ), generation: state.generation))
    return state
}

@Suite("Visible_headingStyle")
struct Visible_headingStyle {
    @Test("放大排版：每个折行占两行，按一半宽度折行；大纲指向上半行")
    func scaledLayout() {
        let rendering = MarkdownLayout.render(source, width: 40, theme: .dark, scaledHeadings: true)
        #expect(rendering.rows[0].scaledHeading?.part == 0)
        #expect(rendering.rows[0].scaledHeading?.text == "Title")
        #expect(rendering.rows[0].scaledHeading?.scale == ScaleSpec.h1)
        #expect(rendering.rows[1].scaledHeading?.part == 1)
        #expect(rendering.outline.first?.row == 0)
        let sub = rendering.rows.firstIndex { $0.scaledHeading?.text == "Sub" }
        #expect(sub.map { rendering.rows[$0].scaledHeading?.scale } == ScaleSpec.h2)

        let long = MarkdownLayout.render("# " + String(repeating: "word ", count: 10), width: 40, theme: .dark, scaledHeadings: true)
        // 正文宽 36，H1 左侧留 1 列：一行最多 17 个单宽字
        let parts = long.rows.compactMap { $0.scaledHeading }.filter { $0.part == 0 }
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { TextWidth.width(of: $0.text) <= 17 })
    }

    @Test("画面：标题完整在视口里时画成放大块，块覆盖的格子不写字")
    func scaledBlockInFrame() {
        let frame = FrameRenderer.render(markdownState(scaled: true))
        let head = frame[1, 3]
        #expect(head.scaled?.text == "Title")
        #expect(frame[1, 4].isCovered)
        #expect(frame[2, 3].isCovered)
        #expect(frame.rowText(1).contains("Title"))
    }

    @Test("上沿滚出视口或下沿被截断时改画普通样式")
    func fallbackWhenPartiallyVisible() {
        var top = markdownState(scaled: true)
        top.viewport.top = ScrollPosition(line: 1, row: 0)
        let frame = FrameRenderer.render(top)
        #expect(frame[1, 3].scaled == nil)
        #expect(frame.rowText(1).contains("Title"))

        // 正文区只有 1 行高：下半行放不进去
        let short = markdownState(scaled: true, rows: 3)
        let shortFrame = FrameRenderer.render(short)
        #expect(shortFrame[1, 3].scaled == nil)
        #expect(shortFrame.rowText(1).contains("Title"))
    }

    @Test("编码：放大块输出 OSC 66；同一行有变化时先清行再整块重画；探测回复决定是否放大")
    func encoderAndProbe() {
        let first = FrameRenderer.render(markdownState(scaled: true))
        let full = ScreenEncoder.encode(previous: nil, next: first)
        #expect(full.contains("\u{1B}]66;s=2;Title\u{07}"))

        var changed = markdownState(scaled: true)
        changed.toast = "x"
        var second = FrameRenderer.render(changed)
        second.write("!", row: 1, column: 30, style: .plain)
        let update = ScreenEncoder.encode(previous: first, next: second)
        #expect(update.contains("\u{1B}[2;1H\u{1B}[0m\u{1B}[2K"))
        #expect(update.contains("\u{1B}]66;s=2;Title\u{07}"))

        var probing = markdownState(scaled: false)
        let effects = TUIReducer.reduce(&probing, .input(.cursorPosition(row: 1, column: 3)))
        #expect(probing.supportsTextSizing)
        #expect(effects.contains { effect in
            if case let .layoutMarkdown(_, _, _, _, _, scaledHeadings) = effect { return scaledHeadings }
            return false
        })
    }
}
