/// 字形簇（Swift `Character`）在终端里占几格，规则与 Ghostty、kitty 的默认行为对齐：
/// - 含 U+FE0F（emoji 呈现选择符），或首个码位默认按 emoji 呈现 → 2
/// - 首个码位的东亚宽度为 W / F（`EastAsianWidthTable`）→ 2
/// - 首个码位是控制字符、零宽格式字符或单独出现的组合附加符 → 0
/// - 其余（含 Ambiguous、方框线、私用区图标）→ 1
/// 组合附加符、ZWJ 与变体选择符是同一字形簇的一部分，不另外占格。
package enum TextWidth {
    package static func width(of character: Character) -> Int {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return 0 }
        if scalars.contains("\u{FE0F}") { return 2 }
        if scalars.contains("\u{FE0E}") { return isWide(first.value) ? 2 : 1 }
        if isZeroWidth(first) { return 0 }
        if first.properties.isEmojiPresentation { return 2 }
        return isWide(first.value) ? 2 : 1
    }

    package static func width(of text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .nonspacingMark, .enclosingMark, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }

    /// 二分查找东亚宽度 W / F 区间表。
    private static func isWide(_ value: UInt32) -> Bool {
        let ranges = EastAsianWidthTable.wideRanges
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = ranges[middle]
            if value < range.start {
                high = middle - 1
            } else if value > range.end {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}
