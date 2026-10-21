import AppKit
import PeekyCore

/// `PeekyPalette` 的 AppKit 适配：把语义 token 的 hex 转成 NSColor，
/// 并把 NSAppearance 映射到 light / dark。配色常量在 `PeekyPalette`。
enum PeekyTheme {
    typealias Appearance = PeekyPalette.Appearance
    typealias ThemeColor = PeekyPalette.ThemeColor

    static func color(_ token: ThemeColor, appearance: Appearance) -> NSColor {
        guard let hex = PeekyPalette.hex(token, appearance: appearance), let resolved = hexColor(hex) else {
            return .clear
        }
        return resolved
    }

    static func hexColor(_ hex: String) -> NSColor? {
        guard let components = PeekyPalette.rgba(fromHex: hex) else { return nil }
        return NSColor(
            srgbRed: CGFloat(components.red) / 255.0,
            green: CGFloat(components.green) / 255.0,
            blue: CGFloat(components.blue) / 255.0,
            alpha: CGFloat(components.alpha) / 255.0
        )
    }

    static func resolveAppearance(_ appearance: NSAppearance?) -> Appearance {
        guard let appearance else { return .light }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
