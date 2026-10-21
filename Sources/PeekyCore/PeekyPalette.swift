import Foundation

/// 集中式配色源：light / dark 两套语义化 palette，只存 hex 字符串。
///
/// 换配色 = 改本文件的 palette 常量表即可。app 经 `PeekyTheme` 转成 NSColor，
/// 终端版按 RGBA 输出真彩转义；两边按语义 token（`jsonString`/`jsonKey`…）取色，
/// 不写死颜色。dark 沿用 VSC Dark Modern，light 沿用 GitHub Light。
public enum PeekyPalette {
    public enum Appearance: Sendable {
        case light
        case dark
    }

    /// 语义颜色 token：编辑器底/字、JSON 各词法元素、gutter、坏行、折叠/导轨/状态栏。
    public enum ThemeColor: Sendable {
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
        /// 侧栏文件树的缩进导轨：非活动列。活动列复用 `.gutterDisclosure`。
        case treeIndentGuide
    }

    /// sRGB 分量，0–255。
    public struct RGBA: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8
        public let alpha: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
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
        .indentGuide: "#404040",
        .foldChipBackground: "#3A3D41",
        .foldChipBorder: "#525252",
        .foldChipGlyph: "#D4D4D4",
        .statusBarBackground: "#181818",
        .statusBarText: "#CCCCCC",
        .gutterDisclosure: "#A0A0A0",
        .treeIndentGuide: "#585858",
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
        .indentGuide: "#E1E4E8",
        .foldChipBackground: "#EAEEF2",
        .foldChipBorder: "#D0D7DE",
        .foldChipGlyph: "#57606A",
        .statusBarBackground: "#F6F8FA",
        .statusBarText: "#424A53",
        .gutterDisclosure: "#656D76",
        .treeIndentGuide: "#A9A9A9",
    ]

    // MARK: - API

    /// token 在该外观下的 hex 字符串（`#RRGGBB` 或 `#RRGGBBAA`）；表里没有时为 nil。
    public static func hex(_ token: ThemeColor, appearance: Appearance) -> String? {
        switch appearance {
        case .light:
            return lightPalette[token]
        case .dark:
            return darkPalette[token]
        }
    }

    /// 解析 `#RRGGBB` / `#RRGGBBAA`；格式不对返回 nil。
    public static func rgba(fromHex hex: String) -> RGBA? {
        guard hex.hasPrefix("#") else { return nil }
        let digits = String(hex.dropFirst())
        guard digits.count == 6 || digits.count == 8 else { return nil }
        guard let value = UInt64(digits, radix: 16) else { return nil }

        if digits.count == 8 {
            return RGBA(
                red: UInt8((value >> 24) & 0xFF),
                green: UInt8((value >> 16) & 0xFF),
                blue: UInt8((value >> 8) & 0xFF),
                alpha: UInt8(value & 0xFF)
            )
        }
        return RGBA(
            red: UInt8((value >> 16) & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8(value & 0xFF),
            alpha: 0xFF
        )
    }
}
