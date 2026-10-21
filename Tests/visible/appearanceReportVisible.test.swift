import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 明暗跟随可见样例
//
// 明暗以终端实际背景为准：OSC 11 回了背景色就按亮度判断；只回 DSR 996（`CSI ? 997 ; 1 n` 深色、
// `; 2 n` 浅色）时按它。运行中 mode 2031 推送明暗变化时再问一次背景色。明暗变了整屏换色，
// Markdown 按新主题重排；浅色下 Markdown 代码块不上 token 色（与 app 一致），源码视图固定深色。

private func state(_ document: OpenedDocument? = nil) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: 40, rows: 8), document: .loading(path: "a.txt"))
    let opened = document ?? OpenedDocument(
        header: DocumentHeader(displayPath: "a.txt", details: ""),
        store: LineStore("hello"),
        presentation: .plain
    )
    _ = TUIReducer.reduce(&state, .loaded(opened, generation: state.generation))
    return state
}

private func report(_ state: inout TUIState, _ event: InputEvent) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(event))
}

@Suite("Visible_appearanceReport")
struct Visible_appearanceReport {
    @Test("没有背景色回复时：997;2 切浅色、997;1 切深色，状态栏随之换成对应的配色")
    func colorSchemeReport() {
        var current = state()
        _ = report(&current, .colorScheme(isDark: false))
        #expect(current.appearance == .light)
        #expect(FrameRenderer.render(current)[7, 0].style.background == TerminalPalette.color(.statusBarBackground, appearance: .light))
        _ = report(&current, .colorScheme(isDark: true))
        #expect(current.appearance == .dark)
        #expect(FrameRenderer.render(current)[7, 0].style.background == TerminalPalette.color(.statusBarBackground, appearance: .dark))
    }

    @Test("只有 OSC 11 背景色时按亮度判断：浅底为浅色、深底为深色")
    func backgroundLuminance() {
        var light = state()
        _ = report(&light, .backgroundColor(red: 0xEF, green: 0xF1, blue: 0xF5))
        #expect(light.appearance == .light)
        var dark = state()
        _ = report(&dark, .backgroundColor(red: 0x22, green: 0x1F, blue: 0x22))
        #expect(dark.appearance == .dark)
    }

    @Test("背景色优先于 996（终端的 996 可能跟着系统而不是跟着自己的配色）；之后的 2031 推送会再问一次背景色")
    func backgroundWinsOverScheme() {
        var schemeFirst = state()
        _ = report(&schemeFirst, .colorScheme(isDark: false))
        _ = report(&schemeFirst, .backgroundColor(red: 0, green: 0, blue: 0))
        #expect(schemeFirst.appearance == .dark)
        var backgroundFirst = state()
        _ = report(&backgroundFirst, .backgroundColor(red: 0, green: 0, blue: 0))
        let effects = report(&backgroundFirst, .colorScheme(isDark: false))
        #expect(backgroundFirst.appearance == .dark)
        #expect(effects.contains(.queryBackground))
        _ = report(&backgroundFirst, .backgroundColor(red: 0xFF, green: 0xFF, blue: 0xFF))
        #expect(backgroundFirst.appearance == .light)
    }

    @Test("切浅色时 Markdown 按浅色主题重排，代码块不上 token 色；源码视图仍是深色底")
    func markdownRelayoutAndSourceStaysDark() {
        let source = "# Title\n\n```swift\nlet a = 1\n```"
        let tokens: [Int: [[HighlightedToken]]] = [0: [[HighlightedToken(text: "let a = 1", colorHex: "#569cd6")]]]
        var markdown = state(OpenedDocument(
            header: DocumentHeader(displayPath: "a.md", details: ""),
            store: LineStore(source),
            presentation: .markdown,
            markdown: MarkdownLayout.render(source, width: 40, theme: .dark, codeTokens: tokens)
        ))
        _ = TUIReducer.reduce(&markdown, .markdownCodeHighlighted(tokens, generation: markdown.generation))
        let effects = report(&markdown, .colorScheme(isDark: false))
        #expect(effects.contains(.layoutMarkdown(generation: markdown.generation, source: source, width: 40, codeTokens: tokens, appearance: .light)))
        let light = MarkdownLayout.render(source, width: 40, theme: .light, codeTokens: tokens)
        let codeRow = light.rows.first { $0.spans.contains { $0.text.contains("let a") } }
        #expect(codeRow?.spans.first { $0.text.contains("let a") }?.style.foreground == .default)

        var code = state(OpenedDocument(
            header: DocumentHeader(displayPath: "a.swift", details: ""),
            store: LineStore("let a = 1"),
            presentation: .source(language: "swift")
        ))
        _ = report(&code, .colorScheme(isDark: false))
        // 第 1 行是光标行；第 2 行在文末之后，铺的是编辑器底色
        #expect(FrameRenderer.render(code)[2, 10].style.background == TerminalPalette.color(.editorBackground, appearance: .dark))
        #expect(FrameRenderer.render(code)[1, 10].style.background == ChromeColors.dark.cursorLine)
    }
}
