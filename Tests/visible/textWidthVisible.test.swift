import Testing
@testable import PeekTUI

// MARK: - TextWidth 可见样例
//
// 终端按「格」排字：每个字形簇（Swift Character）占 0 / 1 / 2 格。规则与 Ghostty、
// kitty 的默认行为对齐：东亚宽度 W/F 与 emoji 呈现占 2 格，组合附加符随基字不占格，
// 零宽字符与控制字符占 0 格，其余（含 Ambiguous、方框线、Nerd Font 私用区）占 1 格。

@Suite("Visible_textWidth")
struct Visible_textWidth {
    @Test("单个字形簇的显示宽度", arguments: [
        ("a", 1),
        ("中", 2),
        ("，", 2),          // U+FF0C 全角逗号
        ("。", 2),          // U+3002 句号
        ("😀", 2),
        ("👨‍👩‍👧", 2),     // ZWJ 序列整体一个字形簇
        ("🇨🇳", 2),         // 区域旗帜对
        ("e\u{301}", 1),    // e + 组合重音
        ("\u{263A}\u{FE0E}", 1), // ☺ + VS15 文本呈现
        ("\u{263A}\u{FE0F}", 2), // ☺ + VS16 emoji 呈现
        ("\u{200B}", 0),    // 零宽空格
        ("\u{1B}", 0),      // ESC 控制字符
        ("─", 1),           // 方框线
        ("✓", 1),
        ("\u{F07B}", 1),    // Nerd Font 私用区图标
    ] as [(String, Int)])
    func characterWidth(text: String, expected: Int) throws {
        let character = try #require(text.first)
        #expect(text.count == 1)
        #expect(TextWidth.width(of: character) == expected)
    }

    @Test("字符串宽度是各字形簇宽度之和")
    func stringWidthSumsClusters() {
        #expect(TextWidth.width(of: "peek 查看器 ✓") == 13)
        #expect(TextWidth.width(of: "") == 0)
    }
}
