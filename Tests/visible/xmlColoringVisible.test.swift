import Testing
@testable import PeekTUI

// MARK: - XMLColoring 可见样例
//
// XML / plist 逐行着色：标签（含尖括号与斜杠）一种颜色、属性名一种、属性值字符串一种、
// 注释一种，标签之间的文字保持默认前景。拼回去的文字与原行一致。

@Suite("Visible_xmlColoring")
struct Visible_xmlColoring {
    @Test("标签、属性名、属性值、文字各自着色，文字内容不变")
    func tagAttributeValue() {
        let line = "<key name=\"a\">text</key>"
        let spans = XMLColoring.spans(for: line, baseStyle: .plain)
        #expect(spans.map(\.text).joined() == line)
        let colorOf: (String) -> TerminalColor? = { text in spans.first { $0.text.contains(text) }?.style.foreground }
        #expect(colorOf("<key") == XMLColoring.tag)
        #expect(colorOf("name") == XMLColoring.attribute)
        #expect(colorOf("\"a\"") == XMLColoring.string)
        #expect(colorOf("text") == .default)
    }

    @Test("注释整段一种颜色")
    func comment() {
        let spans = XMLColoring.spans(for: "<!-- note --><a/>", baseStyle: .plain)
        #expect(spans.first?.text == "<!-- note -->")
        #expect(spans.first?.style.foreground == XMLColoring.comment)
    }
}
