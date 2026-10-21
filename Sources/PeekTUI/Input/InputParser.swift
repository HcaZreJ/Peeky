/// 把终端输入字节流解析成 `InputEvent`。
///
/// - 不完整的序列（被拆在两次读取里的 UTF-8、CSI、DCS、OSC）留在缓冲里，下一次 `feed` 接着解析。
/// - 孤立的 ESC 不能马上判定（可能是序列开头），留到读取超时后 `flushPendingEscape` 才算 Esc 键。
/// - 括号粘贴（`CSI 200~ … CSI 201~`）之间的字节原样收集为一个 `.paste`，结束标记可跨读取。
package struct InputParser {
    private var buffer: [UInt8] = []
    private var pasteBytes: [UInt8]?

    private static let escape: UInt8 = 0x1B
    private static let pasteEnd: [UInt8] = Array("\u{1B}[201~".utf8)
    /// 超过这个长度还没遇到结束字节的转义序列视为损坏，丢弃开头的 ESC。
    private static let maxSequenceLength = 256

    package init() {}

    package mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
        buffer.append(contentsOf: bytes)
        var events: [InputEvent] = []
        var index = 0
        parsing: while index < buffer.count {
            if pasteBytes != nil {
                guard let end = Self.find(Self.pasteEnd, in: buffer, from: index) else {
                    let keep = Self.partialSuffixLength(of: Self.pasteEnd, in: buffer, from: index)
                    pasteBytes?.append(contentsOf: buffer[index..<(buffer.count - keep)])
                    index = buffer.count - keep
                    break parsing
                }
                pasteBytes?.append(contentsOf: buffer[index..<end])
                events.append(.paste(String(decoding: pasteBytes ?? [], as: UTF8.self)))
                pasteBytes = nil
                index = end + Self.pasteEnd.count
                continue
            }
            switch parse(at: index) {
            case let .parsed(parsedEvents, length):
                events.append(contentsOf: parsedEvents)
                index += length
            case let .pasteStart(length):
                pasteBytes = []
                index += length
            case .incomplete:
                break parsing
            }
        }
        buffer.removeFirst(index)
        return events
    }

    /// 读取超时后调用：缓冲停在一个 ESC 开头的不完整序列上时，把 ESC 当作 Esc 键，丢弃其余。
    package mutating func flushPendingEscape() -> [InputEvent] {
        guard pasteBytes == nil, buffer.first == Self.escape else { return [] }
        buffer.removeAll()
        return [.key(KeyPress(key: .escape))]
    }

    // MARK: - 单个事件

    private enum Parsed {
        case parsed([InputEvent], length: Int)
        case pasteStart(length: Int)
        case incomplete
    }

    private func parse(at index: Int) -> Parsed {
        let byte = buffer[index]
        if byte == Self.escape {
            return parseEscape(at: index)
        }
        if byte < 0x20 || byte == 0x7F {
            return .parsed(Self.controlKey(byte).map { [.key($0)] } ?? [], length: 1)
        }
        return parseCharacter(at: index)
    }

    private func parseCharacter(at index: Int) -> Parsed {
        let lead = buffer[index]
        let length: Int
        switch lead {
        case 0x00..<0x80: length = 1
        case 0xC0..<0xE0: length = 2
        case 0xE0..<0xF0: length = 3
        case 0xF0..<0xF8: length = 4
        default: return .parsed([], length: 1)
        }
        guard index + length <= buffer.count else { return .incomplete }
        let text = String(decoding: buffer[index..<(index + length)], as: UTF8.self)
        guard let character = text.first else { return .parsed([], length: length) }
        return .parsed([.key(KeyPress(key: .character(character)))], length: length)
    }

    private func parseEscape(at index: Int) -> Parsed {
        guard index + 1 < buffer.count else { return .incomplete }
        switch buffer[index + 1] {
        case UInt8(ascii: "["):
            return parseCSI(at: index)
        case UInt8(ascii: "O"):
            guard index + 2 < buffer.count else { return .incomplete }
            let key = Self.cursorKey(final: buffer[index + 2])
            return .parsed(key.map { [.key(KeyPress(key: $0))] } ?? [], length: 3)
        case UInt8(ascii: "P"):
            return parseStringSequence(at: index) { content in
                content.hasPrefix(">|") ? .terminalName(String(content.dropFirst(2))) : nil
            }
        case UInt8(ascii: "]"):
            return parseStringSequence(at: index) { content in Self.backgroundColorReport(content) }
        case Self.escape:
            return .parsed([.key(KeyPress(key: .escape))], length: 1)
        default:
            switch parse(at: index + 1) {
            case let .parsed(events, length):
                let withAlt = events.map { event -> InputEvent in
                    guard case var .key(press) = event else { return event }
                    press.modifiers.insert(.alt)
                    return .key(press)
                }
                return .parsed(withAlt, length: length + 1)
            case .pasteStart, .incomplete:
                return .incomplete
            }
        }
    }

    /// DCS / OSC：内容以 BEL 或 ST（ESC \）结束。
    private func parseStringSequence(at index: Int, interpret: (String) -> InputEvent?) -> Parsed {
        var cursor = index + 2
        while cursor < buffer.count {
            if buffer[cursor] == 0x07 {
                let content = String(decoding: buffer[(index + 2)..<cursor], as: UTF8.self)
                return .parsed(interpret(content).map { [$0] } ?? [], length: cursor + 1 - index)
            }
            if buffer[cursor] == Self.escape {
                guard cursor + 1 < buffer.count else { return .incomplete }
                if buffer[cursor + 1] == UInt8(ascii: "\\") {
                    let content = String(decoding: buffer[(index + 2)..<cursor], as: UTF8.self)
                    return .parsed(interpret(content).map { [$0] } ?? [], length: cursor + 2 - index)
                }
            }
            cursor += 1
            if cursor - index > Self.maxSequenceLength {
                return .parsed([.key(KeyPress(key: .escape))], length: 1)
            }
        }
        return .incomplete
    }

    private func parseCSI(at index: Int) -> Parsed {
        var cursor = index + 2
        while cursor < buffer.count {
            let byte = buffer[cursor]
            if (0x40...0x7E).contains(byte) {
                let parameters = String(decoding: buffer[(index + 2)..<cursor], as: UTF8.self)
                let length = cursor + 1 - index
                if byte == UInt8(ascii: "~"), parameters == "200" {
                    return .pasteStart(length: length)
                }
                let event = Self.csiEvent(parameters: parameters, final: Character(Unicode.Scalar(byte)))
                return .parsed(event.map { [$0] } ?? [], length: length)
            }
            cursor += 1
            if cursor - index > Self.maxSequenceLength {
                return .parsed([.key(KeyPress(key: .escape))], length: 1)
            }
        }
        return .incomplete
    }

    // MARK: - 解释

    private static func controlKey(_ byte: UInt8) -> KeyPress? {
        switch byte {
        case 0x0D, 0x0A: return KeyPress(key: .enter)
        case 0x09: return KeyPress(key: .tab)
        case 0x7F, 0x08: return KeyPress(key: .backspace)
        case 0x00: return KeyPress(key: .character(" "), modifiers: .control)
        case 0x01...0x1A:
            return KeyPress(key: .character(Character(Unicode.Scalar(byte + 0x60))), modifiers: .control)
        default: return nil
        }
    }

    private static func cursorKey(final: UInt8) -> Key? {
        switch final {
        case UInt8(ascii: "A"): return .up
        case UInt8(ascii: "B"): return .down
        case UInt8(ascii: "C"): return .right
        case UInt8(ascii: "D"): return .left
        case UInt8(ascii: "H"): return .home
        case UInt8(ascii: "F"): return .end
        default: return nil
        }
    }

    /// xterm 修饰参数：值 − 1 即修饰位；缺省为无修饰。
    private static func modifiers(_ parameter: Substring?) -> KeyModifiers {
        guard let parameter, let value = Int(parameter.split(separator: ":").first ?? ""), value > 1 else { return [] }
        return KeyModifiers(rawValue: (value - 1) & 0b1111)
    }

    private static func csiEvent(parameters: String, final: Character) -> InputEvent? {
        if parameters.hasPrefix("<"), final == "M" || final == "m" {
            return mouseEvent(parameters: parameters.dropFirst(), isRelease: final == "m")
        }
        if parameters.hasPrefix("?") {
            return privateReport(parameters: parameters.dropFirst(), final: final)
        }
        let fields = parameters.split(separator: ";", omittingEmptySubsequences: false)
        switch final {
        case "A", "B", "C", "D", "H", "F":
            guard let key = cursorKey(final: final.asciiValue ?? 0) else { return nil }
            return .key(KeyPress(key: key, modifiers: modifiers(fields.count > 1 ? fields[1] : nil)))
        case "~":
            let key: Key?
            switch Int(fields.first ?? "") {
            case 1, 7: key = .home
            case 4, 8: key = .end
            case 5: key = .pageUp
            case 6: key = .pageDown
            case 2: key = .insert
            case 3: key = .delete
            default: key = nil
            }
            return key.map { .key(KeyPress(key: $0, modifiers: modifiers(fields.count > 1 ? fields[1] : nil))) }
        case "u":
            return kittyKey(fields: fields)
        case "R":
            guard fields.count == 2, let row = Int(fields[0]), let column = Int(fields[1]) else { return nil }
            return .cursorPosition(row: row, column: column)
        case "I":
            return .focus(true)
        case "O":
            return .focus(false)
        case "Z":
            return .key(KeyPress(key: .tab, modifiers: .shift))
        default:
            return nil
        }
    }

    /// kitty 键盘协议：`CSI code[:…] ; mods[:event] u`。只取按下与重复，忽略松开。
    private static func kittyKey(fields: [Substring]) -> InputEvent? {
        guard let codeField = fields.first, let code = UInt32(codeField.split(separator: ":").first ?? "") else { return nil }
        if fields.count > 1 {
            let eventParts = fields[1].split(separator: ":")
            if eventParts.count > 1, eventParts[1] == "3" { return nil }
        }
        let mods = modifiers(fields.count > 1 ? fields[1] : nil)
        let key: Key
        switch code {
        case 13: key = .enter
        case 9: key = .tab
        case 127, 8: key = .backspace
        case 27: key = .escape
        default:
            guard let scalar = Unicode.Scalar(code), !(0xE000...0xF8FF).contains(code) else { return nil }
            key = .character(Character(scalar))
        }
        return .key(KeyPress(key: key, modifiers: mods))
    }

    private static func privateReport(parameters: Substring, final: Character) -> InputEvent? {
        let fields = parameters.split(separator: ";")
        switch final {
        case "n":
            guard fields.count == 2, fields[0] == "997", let value = Int(fields[1]) else { return nil }
            return .colorScheme(isDark: value == 1)
        case "c":
            return .primaryDeviceAttributes
        case "u":
            return Int(fields.first ?? "").map { .keyboardProtocolFlags($0) }
        default:
            return nil
        }
    }

    /// SGR 鼠标：`CSI < b ; x ; y M|m`，坐标 1 起算。
    private static func mouseEvent(parameters: Substring, isRelease: Bool) -> InputEvent? {
        let fields = parameters.split(separator: ";").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        let code = fields[0]
        var mods: KeyModifiers = []
        if code & 4 != 0 { mods.insert(.shift) }
        if code & 8 != 0 { mods.insert(.alt) }
        if code & 16 != 0 { mods.insert(.control) }
        let button: MouseButton?
        switch code & 0b11 {
        case 0: button = .left
        case 1: button = .middle
        case 2: button = .right
        default: button = nil
        }
        let kind: MouseEvent.Kind
        if code & 64 != 0 {
            guard code & 2 == 0 else { return nil }
            kind = code & 1 == 0 ? .scrollUp : .scrollDown
        } else if code & 32 != 0 {
            kind = button.map { .drag($0) } ?? .move
        } else if let button {
            kind = isRelease ? .release(button) : .press(button)
        } else {
            return nil
        }
        return .mouse(MouseEvent(kind: kind, row: fields[2] - 1, column: fields[1] - 1, modifiers: mods))
    }

    /// OSC 11 回复：`11;rgb:RRRR/GGGG/BBBB`（每分量 1–4 位十六进制）。
    private static func backgroundColorReport(_ content: String) -> InputEvent? {
        guard content.hasPrefix("11;rgb:") else { return nil }
        let components = content.dropFirst("11;rgb:".count).split(separator: "/")
        guard components.count == 3 else { return nil }
        let values = components.compactMap { component -> Int? in
            guard let value = Int(component, radix: 16), !component.isEmpty else { return nil }
            let maxValue = (1 << (4 * component.count)) - 1
            return value * 255 / maxValue
        }
        guard values.count == 3 else { return nil }
        return .backgroundColor(red: values[0], green: values[1], blue: values[2])
    }

    // MARK: - 字节查找

    private static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard needle.count <= haystack.count - start else { return nil }
        var index = start
        while index + needle.count <= haystack.count {
            if haystack[index] == needle[0], Array(haystack[index..<(index + needle.count)]) == needle {
                return index
            }
            index += 1
        }
        return nil
    }

    /// 缓冲末尾有多少字节可能是 `needle` 的前缀（结束标记被拆在两次读取里）。
    private static func partialSuffixLength(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int {
        let available = haystack.count - start
        for length in stride(from: min(needle.count - 1, available), to: 0, by: -1) {
            if Array(haystack[(haystack.count - length)...]) == Array(needle[..<length]) {
                return length
            }
        }
        return 0
    }
}
