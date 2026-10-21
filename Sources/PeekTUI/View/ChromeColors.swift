import PeekyCore

/// 调色板之外的界面颜色：光标行、选区、侧栏列表选中、强调色（深色取 VS Code Dark Modern，浅色取 Light+）。
package struct ChromeColors: Equatable, Sendable {
    package let cursorLine: TerminalColor
    package let selection: TerminalColor
    package let listFocusedSelection: TerminalColor
    package let listUnfocusedSelection: TerminalColor
    /// 当前文件名、帮助里的按键、侧栏聚焦时的页签
    package let accent: TerminalColor

    package static let dark = ChromeColors(
        cursorLine: .rgb(0x2A, 0x2D, 0x2E),
        selection: .rgb(0x26, 0x4F, 0x78),
        listFocusedSelection: .rgb(0x04, 0x39, 0x5E),
        listUnfocusedSelection: .rgb(0x37, 0x37, 0x3D),
        accent: .rgb(0x44, 0x93, 0xF8)
    )

    package static let light = ChromeColors(
        cursorLine: .rgb(0xEE, 0xF0, 0xF2),
        selection: .rgb(0xAD, 0xD6, 0xFF),
        listFocusedSelection: .rgb(0xCC, 0xE4, 0xF7),
        listUnfocusedSelection: .rgb(0xE4, 0xE6, 0xF1),
        accent: .rgb(0x09, 0x69, 0xDA)
    )

    package static func forAppearance(_ appearance: PeekyPalette.Appearance) -> ChromeColors {
        appearance == .light ? .light : .dark
    }
}
