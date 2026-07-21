import AppKit

/// 集中式主题源：light / dark 两套语义化 palette。
///
/// 换配色 = 改本文件顶部 palette 常量表里的 hex 值即可，渲染逻辑按语义 token
/// （`jsonString`/`jsonKey`…）取色，不写死颜色。dark 初始沿用 VSC Dark Modern，
/// light 初始沿用 GitHub Light。
enum PeekyTheme {
    enum Appearance {
        case light
        case dark
    }

    /// 语义颜色 token：编辑器底/字、JSON 各词法元素、gutter、坏行、折叠/导轨/状态栏。
    enum ThemeColor {
        case editorBackground
        case editorForeground
        case jsonKey
        case jsonString
        case jsonNumber
        case jsonBool
        case jsonNull
        case jsonPunctuation
        case gutterBackground
        case gutterText
        case invalidLineBackground
        case invalidLineForeground
        /// 缩进导轨虚线
        case indentGuide
        /// 折叠 chip 占位（圆角底 / 描边 / 双向箭头字形）
        case foldChipBackground
        case foldChipBorder
        case foldChipGlyph
        /// 底部状态栏（Ln/Col/size）
        case statusBarBackground
        case statusBarText
        /// gutter 折叠三角
        case gutterDisclosure
    }

    // MARK: - Palette（配色常量表，换配色只改这里）

    /// dark：VSC Dark Modern
    private static let darkPalette: [ThemeColor: String] = [
        .editorBackground: "#1F1F1F",
        .editorForeground: "#CCCCCC",
        .jsonKey: "#9CDCFE",
        .jsonString: "#CE9178",
        .jsonNumber: "#B5CEA8",
        .jsonBool: "#569CD6",
        .jsonNull: "#569CD6",
        .jsonPunctuation: "#CCCCCC",
        .gutterBackground: "#1F1F1F",
        .gutterText: "#6E7681",
        .invalidLineForeground: "#F85149",
        .invalidLineBackground: "#F8514922",
        .indentGuide: "#000000",
        .foldChipBackground: "#000000",
        .foldChipBorder: "#000000",
        .foldChipGlyph: "#000000",
        .statusBarBackground: "#000000",
        .statusBarText: "#000000",
        .gutterDisclosure: "#000000",
    ]

    /// light：GitHub Light
    private static let lightPalette: [ThemeColor: String] = [
        .editorBackground: "#FFFFFF",
        .editorForeground: "#1F2328",
        .jsonKey: "#0550AE",
        .jsonString: "#0A3069",
        .jsonNumber: "#098658",
        .jsonBool: "#CF222E",
        .jsonNull: "#CF222E",
        .jsonPunctuation: "#6E7781",
        .gutterBackground: "#FFFFFF",
        .gutterText: "#8C959F",
        .invalidLineForeground: "#CF222E",
        .invalidLineBackground: "#CF222E1F",
        .indentGuide: "#000000",
        .foldChipBackground: "#000000",
        .foldChipBorder: "#000000",
        .foldChipGlyph: "#000000",
        .statusBarBackground: "#000000",
        .statusBarText: "#000000",
        .gutterDisclosure: "#000000",
    ]

    // MARK: - API

    static func color(_ token: ThemeColor, appearance: Appearance) -> NSColor {
        let palette: [ThemeColor: String]
        switch appearance {
        case .light:
            palette = lightPalette
        case .dark:
            palette = darkPalette
        }
        guard let hex = palette[token], let resolved = hexColor(hex) else {
            return .clear
        }
        return resolved
    }

    static func hexColor(_ hex: String) -> NSColor? {
        guard hex.hasPrefix("#") else { return nil }
        let digits = String(hex.dropFirst())
        guard digits.count == 6 || digits.count == 8 else { return nil }
        guard let value = UInt64(digits, radix: 16) else { return nil }

        let hasAlpha = digits.count == 8
        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        if hasAlpha {
            red = (value >> 24) & 0xFF
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        } else {
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        return NSColor(
            srgbRed: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }

    static func resolveAppearance(_ appearance: NSAppearance?) -> Appearance {
        guard let appearance else { return .light }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
