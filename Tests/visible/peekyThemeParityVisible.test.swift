import AppKit
import Testing

@testable import PeekyKit

// MARK: - 颜色比较辅助（sRGB 相对亮度：0.2126R + 0.7152G + 0.0722B，忽略 alpha）

private func rgbTriple(_ color: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
    let srgb = color.usingColorSpace(.sRGB) ?? color
    return (
        Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent),
        Double(srgb.alphaComponent)
    )
}

private func relativeLuminance(_ color: NSColor) -> Double {
    let c = rgbTriple(color)
    return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
}

private func isClearColor(_ color: NSColor) -> Bool {
    rgbTriple(color).a <= 0.0001
}

private func colorsApproximatelyEqual(_ a: NSColor, _ b: NSColor, tolerance: Double = 1.0 / 512.0)
    -> Bool
{
    let ca = rgbTriple(a)
    let cb = rgbTriple(b)
    return abs(ca.r - cb.r) < tolerance && abs(ca.g - cb.g) < tolerance
        && abs(ca.b - cb.b) < tolerance
}

/// 明暗自适应断言用：RGBA 四分量近似相等（spec 要求 light/dark 的 RGBA 不全等，
/// 仅 alpha 不同也算不同）。
private func colorsApproximatelyEqualIncludingAlpha(
    _ a: NSColor, _ b: NSColor, tolerance: Double = 1.0 / 512.0
) -> Bool {
    let ca = rgbTriple(a)
    let cb = rgbTriple(b)
    return colorsApproximatelyEqual(a, b, tolerance: tolerance) && abs(ca.a - cb.a) < tolerance
}

private let newThemeTokens: [PeekyTheme.ThemeColor] = [
    .indentGuide,
    .foldChipBackground,
    .foldChipBorder,
    .foldChipGlyph,
    .statusBarBackground,
    .statusBarText,
    .gutterDisclosure,
]

@Suite("Visible_peekyThemeParity")
struct Visible_peekyThemeParity {

    @Test("新增 7 个语义 token 在 light/dark 两种外观下都能解析出非透明颜色")
    func test_peekyThemeParity_newTokensResolveNonClearInBothAppearances() {
        for token in newThemeTokens {
            let light = PeekyTheme.color(token, appearance: .light)
            let dark = PeekyTheme.color(token, appearance: .dark)
            #expect(!isClearColor(light), "\(token) 在 light 外观下不应解析为 .clear")
            #expect(!isClearColor(dark), "\(token) 在 dark 外观下不应解析为 .clear")
        }
    }

    @Test("新增 7 个语义 token 的 light 取值应与 dark 取值不同（明暗自适应）")
    func test_peekyThemeParity_newTokensDifferBetweenLightAndDarkAppearance() {
        for token in newThemeTokens {
            let light = PeekyTheme.color(token, appearance: .light)
            let dark = PeekyTheme.color(token, appearance: .dark)
            #expect(
                !colorsApproximatelyEqualIncludingAlpha(light, dark),
                "\(token) 的 light 取值不应与 dark 取值相同"
            )
        }
    }

    @Test("状态栏文字/底色的亮度对比方向应随外观反转：light 下深字浅底，dark 下浅字深底")
    func test_peekyThemeParity_statusBarContrastDirectionFlipsWithAppearance() {
        let lightText = relativeLuminance(PeekyTheme.color(.statusBarText, appearance: .light))
        let lightBackground = relativeLuminance(
            PeekyTheme.color(.statusBarBackground, appearance: .light))
        #expect(lightText < lightBackground, "light 下 statusBarText 应比 statusBarBackground 暗")

        let darkText = relativeLuminance(PeekyTheme.color(.statusBarText, appearance: .dark))
        let darkBackground = relativeLuminance(
            PeekyTheme.color(.statusBarBackground, appearance: .dark))
        #expect(darkText > darkBackground, "dark 下 statusBarText 应比 statusBarBackground 亮")
    }
}
