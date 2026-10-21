import Testing
@testable import PeekyCore

// MARK: - PeekyPalette 可见样例
//
// PeekyPalette 是 app 与终端版共用的纯配色源（不依赖 AppKit）。覆盖两条契约：
// rgba(fromHex:) 对 6 位 / 8 位 hex 的固定解析结果与非法输入返回 nil；
// hex(_:appearance:) 的结构关系——每个 token 在两种外观下都有值、
// 同一 token 在 light / dark 下不同。配色值本身是可调常量，不锁死具体 hex。

@Suite("Visible_peekyPalette")
struct PeekyPaletteVisibleTests {
    @Test("6 位 hex 解析为对应 RGB，alpha 为 255")
    func sixDigitHex() {
        #expect(PeekyPalette.rgba(fromHex: "#1F2328") == PeekyPalette.RGBA(red: 0x1F, green: 0x23, blue: 0x28, alpha: 0xFF))
    }

    @Test("8 位 hex 的末两位解析为 alpha")
    func eightDigitHex() {
        #expect(PeekyPalette.rgba(fromHex: "#F8514922") == PeekyPalette.RGBA(red: 0xF8, green: 0x51, blue: 0x49, alpha: 0x22))
    }

    @Test("缺 # 前缀、位数不对、含非 hex 字符时返回 nil", arguments: ["1F2328", "#1F232", "#1F2328FF00", "#GGGGGG"] as [String])
    func invalidHex(_ hex: String) {
        #expect(PeekyPalette.rgba(fromHex: hex) == nil)
    }

    @Test("同一 token 两种外观都有可解析的值，且 light 与 dark 不同")
    func everyTokenResolvesInBothAppearances() throws {
        for token in [PeekyPalette.ThemeColor.editorBackground, .jsonKey, .gutterText, .treeIndentGuide] {
            let light = try #require(PeekyPalette.hex(token, appearance: .light))
            let dark = try #require(PeekyPalette.hex(token, appearance: .dark))
            #expect(PeekyPalette.rgba(fromHex: light) != nil)
            #expect(PeekyPalette.rgba(fromHex: dark) != nil)
            #expect(light != dark)
        }
    }
}
