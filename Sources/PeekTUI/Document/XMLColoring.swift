import PeekyCore

/// XML / plist 的逐行着色：标签名、属性名、属性值字符串、注释。深色取 VS Code Dark Modern，浅色取 Light+。
package enum XMLColoring {
    struct Colors {
        let tag: TerminalColor
        let attribute: TerminalColor
        let string: TerminalColor
        let comment: TerminalColor
    }

    static let dark = Colors(
        tag: .rgb(0x56, 0x9C, 0xD6),
        attribute: .rgb(0x9C, 0xDC, 0xFE),
        string: .rgb(0xCE, 0x91, 0x78),
        comment: .rgb(0x6A, 0x99, 0x55)
    )
    static let light = Colors(
        tag: .rgb(0x80, 0x00, 0x00),
        attribute: .rgb(0xE5, 0x00, 0x00),
        string: .rgb(0x00, 0x00, 0xFF),
        comment: .rgb(0x00, 0x80, 0x00)
    )
    static var tag: TerminalColor { dark.tag }
    static var attribute: TerminalColor { dark.attribute }
    static var string: TerminalColor { dark.string }
    static var comment: TerminalColor { dark.comment }

    package static func spans(for line: String, baseStyle: CellStyle, appearance: PeekyPalette.Appearance = .dark) -> [StyledSpan] {
        let colors = appearance == .light ? light : dark
        let tag = colors.tag
        let attribute = colors.attribute
        let string = colors.string
        let comment = colors.comment
        var spans: [StyledSpan] = []
        var buffer = ""
        var bufferColor: TerminalColor? = nil
        func flush() {
            guard !buffer.isEmpty else { return }
            var style = baseStyle
            if let bufferColor { style.foreground = bufferColor }
            spans.append(StyledSpan(text: buffer, style: style))
            buffer = ""
        }
        func emit(_ character: Character, _ color: TerminalColor?) {
            if color != bufferColor {
                flush()
                bufferColor = color
            }
            buffer.append(character)
        }

        enum Mode { case text, tagName, insideTag, attributeValue(Character), comment }
        var mode = Mode.text
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch mode {
            case .text:
                if character == "<" {
                    if characters[index...].starts(with: Array("<!--")) {
                        mode = .comment
                        emit(character, comment)
                    } else {
                        mode = .tagName
                        emit(character, tag)
                    }
                } else {
                    emit(character, nil)
                }
            case .tagName:
                if character == " " || character == "\t" {
                    mode = .insideTag
                    emit(character, nil)
                } else {
                    emit(character, tag)
                    if character == ">" { mode = .text }
                }
            case .insideTag:
                if character == "\"" || character == "'" {
                    mode = .attributeValue(character)
                    emit(character, string)
                } else if character == ">" || character == "/" || character == "?" {
                    emit(character, tag)
                    if character == ">" { mode = .text }
                } else if character == "=" || character == " " || character == "\t" {
                    emit(character, nil)
                } else {
                    emit(character, attribute)
                }
            case let .attributeValue(quote):
                emit(character, string)
                if character == quote { mode = .insideTag }
            case .comment:
                emit(character, comment)
                if character == ">", index >= 2, characters[index - 1] == "-", characters[index - 2] == "-" {
                    mode = .text
                }
            }
            index += 1
        }
        flush()
        return spans.isEmpty ? [StyledSpan(text: "", style: baseStyle)] : spans
    }
}
