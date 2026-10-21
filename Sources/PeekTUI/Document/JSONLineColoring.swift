import Foundation
import PeekyCore

/// JSON 单行着色：`JSONHighlighter` 的 token → PeekyPalette 的 JSON 语义色；
/// 行首缩进每 2 列画一条导轨（`│`，导轨色）；折叠占位 U+FFFC 画成 ` ⟷ ` 圆角块（与 app 的占位字形一致）。
package enum JSONLineColoring {
    static let foldChip = "\u{FFFC}"
    static let indentUnit = 2

    package static func spans(for line: String, appearance: PeekyPalette.Appearance, baseStyle: CellStyle) -> [StyledSpan] {
        var spans: [StyledSpan] = []
        let leading = line.prefix { $0 == " " }.count
        if leading > 0 {
            var guide = baseStyle
            guide.foreground = TerminalPalette.color(.indentGuide, appearance: appearance)
            var guides = ""
            for column in 0..<leading {
                guides += column % indentUnit == 0 ? "│" : " "
            }
            spans.append(StyledSpan(text: guides, style: guide))
        }
        let body = String(line.dropFirst(leading))
        let text = body as NSString
        var cursor = 0
        func plain(upTo end: Int) {
            guard end > cursor else { return }
            spans.append(contentsOf: segment(text.substring(with: NSRange(location: cursor, length: end - cursor)), style: baseStyle, appearance: appearance))
            cursor = end
        }
        for token in JSONHighlighter.tokenize(body) {
            plain(upTo: token.range.location)
            var style = baseStyle
            style.foreground = TerminalPalette.color(color(for: token.kind), appearance: appearance)
            spans.append(contentsOf: segment(text.substring(with: token.range), style: style, appearance: appearance))
            cursor = token.range.location + token.range.length
        }
        plain(upTo: text.length)
        return spans
    }

    /// 普通文字里出现的折叠占位换成占位块。
    private static func segment(_ text: String, style: CellStyle, appearance: PeekyPalette.Appearance) -> [StyledSpan] {
        guard text.contains(foldChip) else { return [StyledSpan(text: text, style: style)] }
        var chip = style
        chip.foreground = TerminalPalette.color(.foldChipGlyph, appearance: appearance)
        chip.background = TerminalPalette.color(.foldChipBackground, appearance: appearance)
        var result: [StyledSpan] = []
        for (index, part) in text.components(separatedBy: foldChip).enumerated() {
            if index > 0 { result.append(StyledSpan(text: " ⟷ ", style: chip)) }
            if !part.isEmpty { result.append(StyledSpan(text: part, style: style)) }
        }
        return result
    }

    private static func color(for kind: JSONHighlighter.JSONTokenKind) -> PeekyPalette.ThemeColor {
        switch kind {
        case .key: return .jsonKey
        case .string: return .jsonString
        case .number: return .jsonNumber
        case .boolLiteral: return .jsonBool
        case .nullLiteral: return .jsonNull
        case .punctuation: return .jsonPunctuation
        }
    }
}
