import Testing
@testable import PeekTUI

// MARK: - InputParser 可见样例
//
// InputParser 把终端送来的字节流解析成事件：按键（含修饰键、kitty 键盘协议）、
// SGR 鼠标、括号粘贴，以及终端对探测查询的回复。字节可能被拆在两次读取里，
// 不完整的序列留到下一次 feed 再解析；孤立的 ESC 留到 flushPendingEscape 才算 Esc 键。

private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
private func key(_ key: Key, _ modifiers: KeyModifiers = []) -> InputEvent { .key(KeyPress(key: key, modifiers: modifiers)) }

@Suite("Visible_inputParser")
struct Visible_inputParser {
    @Test("可打印字符与被拆在两次读取里的 UTF-8 汉字")
    func printableAndSplitUTF8() {
        var parser = InputParser()
        let han = Array("中".utf8)
        let first = parser.feed(bytes("j") + [han[0]])
        let second = parser.feed(Array(han[1...]))
        #expect(first == [key(.character("j"))])
        #expect(second == [key(.character("中"))])
    }

    @Test("控制键：Ctrl-C、回车、退格、Tab")
    func controlKeys() {
        var parser = InputParser()
        #expect(parser.feed([0x03, 0x0D, 0x7F, 0x09]) == [
            key(.character("c"), .control), key(.enter), key(.backspace), key(.tab),
        ])
    }

    @Test("方向键、带修饰的方向键、翻页键")
    func navigationKeys() {
        var parser = InputParser()
        #expect(parser.feed(bytes("\u{1B}[A\u{1B}[1;5C\u{1B}[6~\u{1B}[H")) == [
            key(.up), key(.right, .control), key(.pageDown), key(.home),
        ])
    }

    @Test("孤立 ESC 等到 flush 才算 Esc 键；ESC 后跟字母是 Alt 组合")
    func escapeAndAlt() {
        var parser = InputParser()
        #expect(parser.feed([0x1B]) == [])
        #expect(parser.flushPendingEscape() == [key(.escape)])
        #expect(parser.feed(bytes("\u{1B}x")) == [key(.character("x"), .alt)])
    }

    @Test("kitty 键盘协议：⌘C 与回车")
    func kittyKeyboardProtocol() {
        var parser = InputParser()
        #expect(parser.feed(bytes("\u{1B}[99;9u\u{1B}[13u")) == [key(.character("c"), .super), key(.enter)])
    }

    @Test("SGR 鼠标：按下、拖动、松开、滚轮（坐标转成 0 起算）")
    func sgrMouse() {
        var parser = InputParser()
        let events = parser.feed(bytes("\u{1B}[<0;10;5M\u{1B}[<32;11;5M\u{1B}[<0;11;5m\u{1B}[<64;3;3M\u{1B}[<65;3;3M"))
        #expect(events == [
            .mouse(MouseEvent(kind: .press(.left), row: 4, column: 9, modifiers: [])),
            .mouse(MouseEvent(kind: .drag(.left), row: 4, column: 10, modifiers: [])),
            .mouse(MouseEvent(kind: .release(.left), row: 4, column: 10, modifiers: [])),
            .mouse(MouseEvent(kind: .scrollUp, row: 2, column: 2, modifiers: [])),
            .mouse(MouseEvent(kind: .scrollDown, row: 2, column: 2, modifiers: [])),
        ])
    }

    @Test("括号粘贴跨两次读取，内容原样保留（含换行）")
    func bracketedPasteAcrossFeeds() {
        var parser = InputParser()
        #expect(parser.feed(bytes("\u{1B}[200~hello\nwor")) == [])
        #expect(parser.feed(bytes("ld\u{1B}[201~q")) == [.paste("hello\nworld"), key(.character("q"))])
    }

    @Test("终端回复：明暗、光标位置、终端名、DA1、kitty 键盘协议标志、焦点")
    func terminalReports() {
        var parser = InputParser()
        let events = parser.feed(bytes(
            "\u{1B}[?997;1n\u{1B}[?997;2n\u{1B}[12;40R\u{1B}P>|kitty(0.49.2)\u{1B}\\\u{1B}[?62;22c\u{1B}[?1u\u{1B}[I\u{1B}[O"
        ))
        #expect(events == [
            .colorScheme(isDark: true),
            .colorScheme(isDark: false),
            .cursorPosition(row: 12, column: 40),
            .terminalName("kitty(0.49.2)"),
            .primaryDeviceAttributes,
            .keyboardProtocolFlags(1),
            .focus(true),
            .focus(false),
        ])
    }

    @Test("图片能力回复：格子像素尺寸 CSI 6;高;宽 t、kitty 图片协议应答（可跨两次读取）")
    func imageCapabilityReports() {
        var parser = InputParser()
        let first = parser.feed(bytes("\u{1B}[6;25;14t\u{1B}_Gi=31;O"))
        let second = parser.feed(bytes("K\u{1B}\\\u{1B}_Gi=7;ENOENT:no such file\u{1B}\\"))
        #expect(first == [.cellPixelSize(width: 14, height: 25)])
        #expect(second == [.graphicsReply(id: 31, message: "OK"), .graphicsReply(id: 7, message: "ENOENT:no such file")])
    }
}
