/// 修饰键，位值与 xterm / kitty 协议的「修饰参数 − 1」一致。
package struct KeyModifiers: OptionSet, Equatable, Sendable {
    package let rawValue: Int
    package init(rawValue: Int) { self.rawValue = rawValue }

    package static let shift = KeyModifiers(rawValue: 1)
    package static let alt = KeyModifiers(rawValue: 2)
    package static let control = KeyModifiers(rawValue: 4)
    package static let `super` = KeyModifiers(rawValue: 8)
}

package enum Key: Equatable, Sendable {
    case character(Character)
    case enter
    case tab
    case backspace
    case escape
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case insert
    case delete
}

package struct KeyPress: Equatable, Sendable {
    package var key: Key
    package var modifiers: KeyModifiers

    package init(key: Key, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

package enum MouseButton: Equatable, Sendable {
    case left
    case middle
    case right
}

/// 鼠标事件，`row` / `column` 为 0 起算的格子坐标。
package struct MouseEvent: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case press(MouseButton)
        case release(MouseButton)
        case drag(MouseButton)
        case move
        case scrollUp
        case scrollDown
    }

    package var kind: Kind
    package var row: Int
    package var column: Int
    package var modifiers: KeyModifiers
    /// 连击次数：终端不报告，由运行时按两次按下的间隔与位置算出（双击 2、三击 3）
    package var clickCount: Int

    package init(kind: Kind, row: Int, column: Int, modifiers: KeyModifiers, clickCount: Int = 1) {
        self.kind = kind
        self.row = row
        self.column = column
        self.modifiers = modifiers
        self.clickCount = clickCount
    }
}

/// 终端送来的一个输入事件：用户按键 / 鼠标 / 粘贴，或终端对查询的回复。
package enum InputEvent: Equatable, Sendable {
    case key(KeyPress)
    case mouse(MouseEvent)
    case paste(String)
    case focus(Bool)
    /// mode 2031 推送或 DSR 996 回复：`CSI ? 997 ; 1 n` 深色、`; 2 n` 浅色
    case colorScheme(isDark: Bool)
    /// CPR 回复，1 起算
    case cursorPosition(row: Int, column: Int)
    /// XTVERSION 回复：`DCS > | name ST`
    case terminalName(String)
    /// DA1 回复：探测阶段的结束哨兵
    case primaryDeviceAttributes
    /// kitty 键盘协议查询回复：`CSI ? flags u`
    case keyboardProtocolFlags(Int)
    /// OSC 11 背景色回复，分量 0–255
    case backgroundColor(red: Int, green: Int, blue: Int)
}
