import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 按键动作可见样例
//
// F / p / P 复制文件名 / 绝对路径 / 仓库内相对路径（不在仓库里时只提示）；o 在 Finder 中显示，
// e 用默认编辑器打开；⌘C（kitty 键盘协议上报 super+c）同 y；`:行号` 回车跳行；? 打开帮助浮层，
// 再按任意键关闭。

private let file = URL(fileURLWithPath: "/repo/docs/notes.txt")

private func state(repoRoot: URL?) -> TUIState {
    var state = TUIState.launching(
        size: TerminalSize(columns: 80, rows: 24),
        target: file,
        isDirectory: false,
        displayPath: "repo/docs/notes.txt",
        treeRoot: URL(fileURLWithPath: "/repo"),
        targetLine: nil,
        repoRoot: repoRoot
    )
    _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
        header: DocumentHeader(displayPath: "repo/docs/notes.txt", details: ""),
        store: LineStore((1...30).map { "line \($0)" }.joined(separator: "\n")),
        presentation: .plain
    ), generation: state.generation))
    return state
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

private func copied(_ effects: [TUIEffect]) -> String? {
    for effect in effects {
        if case let .copy(text, _) = effect { return text }
    }
    return nil
}

@Suite("Visible_keymap")
struct Visible_keymap {
    @Test("F / p / P 复制文件名、绝对路径、仓库内相对路径；不在仓库里时 P 只提示")
    func copyNameAndPaths() {
        var current = state(repoRoot: URL(fileURLWithPath: "/repo"))
        #expect(copied(press(&current, .character("F"), .shift)) == "notes.txt")
        #expect(copied(press(&current, .character("p"))) == "/repo/docs/notes.txt")
        #expect(copied(press(&current, .character("P"), .shift)) == "docs/notes.txt")
        #expect(current.toast == "已复制相对路径")

        var outside = state(repoRoot: nil)
        #expect(copied(press(&outside, .character("P"))) == nil)
        #expect(outside.toast == "不在代码仓库里，没有相对路径")
    }

    @Test("o 在 Finder 中显示，e 用默认编辑器打开")
    func revealAndEdit() {
        var current = state(repoRoot: nil)
        #expect(press(&current, .character("o")).contains(.reveal(file)))
        #expect(press(&current, .character("e")).contains(.openInEditor(file)))
    }

    @Test("⌘C 同 y；:行号 回车跳到该行，输入时状态栏显示")
    func commandCopyAndGotoLine() {
        var current = state(repoRoot: nil)
        #expect(copied(press(&current, .character("c"), .super)) == "line 1")
        _ = press(&current, .character(":"))
        _ = press(&current, .character("1"))
        _ = press(&current, .character("2"))
        #expect(FrameRenderer.render(current).rowText(23).hasPrefix(" :12"))
        _ = press(&current, .enter)
        #expect(current.viewport.cursor == 11)
        #expect(current.lineInput == nil)
    }

    @Test("? 打开帮助浮层，列出按键；再按任意键关闭")
    func helpOverlay() {
        var current = state(repoRoot: nil)
        _ = press(&current, .character("?"))
        let text = (0..<24).map { FrameRenderer.render(current).rowText($0) }.joined(separator: "\n")
        #expect(text.contains("复制选中内容"))
        #expect(text.contains("仓库内相对路径"))
        _ = press(&current, .character("x"))
        #expect(!current.isHelpVisible)
        #expect(current.viewport.cursor == 0)
    }
}
