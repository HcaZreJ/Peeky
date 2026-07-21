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

/// 新增 7 个语义 token（折叠/导轨/状态栏）。
private let newThemeTokens: [PeekyTheme.ThemeColor] = [
    .indentGuide,
    .foldChipBackground,
    .foldChipBorder,
    .foldChipGlyph,
    .statusBarBackground,
    .statusBarText,
    .gutterDisclosure,
]

/// 既有 12 个 token（editorBackground…invalidLineForeground），本单元不应造成回归。
private let existingThemeTokens: [PeekyTheme.ThemeColor] = [
    .editorBackground,
    .editorForeground,
    .jsonKey,
    .jsonString,
    .jsonNumber,
    .jsonBool,
    .jsonNull,
    .jsonPunctuation,
    .gutterBackground,
    .gutterText,
    .invalidLineBackground,
    .invalidLineForeground,
]

@Suite("Hidden_peekyThemeParity")
struct Hidden_peekyThemeParity {

    // MARK: 可解析性（behavioral contract 第 1 点）

    @Test("新增 7 个 token 在 light 外观下均解析出非 .clear 颜色")
    func test_peekyThemeParity_allNewTokensResolveNonClearInLightAppearance() {
        for token in newThemeTokens {
            let color = PeekyTheme.color(token, appearance: .light)
            #expect(!isClearColor(color), "\(token) 在 light 外观下不应解析为 .clear")
        }
    }

    @Test("新增 7 个 token 在 dark 外观下均解析出非 .clear 颜色")
    func test_peekyThemeParity_allNewTokensResolveNonClearInDarkAppearance() {
        for token in newThemeTokens {
            let color = PeekyTheme.color(token, appearance: .dark)
            #expect(!isClearColor(color), "\(token) 在 dark 外观下不应解析为 .clear")
        }
    }

    @Test("新增 7 个 token 的 RGB 分量均落在合法的 [0, 1] 单位区间内（hex 解析健壮性）")
    func test_peekyThemeParity_newTokenColorComponentsStayWithinUnitRange() {
        for token in newThemeTokens {
            for appearance: PeekyTheme.Appearance in [.light, .dark] {
                let c = rgbTriple(PeekyTheme.color(token, appearance: appearance))
                #expect((0.0...1.0).contains(c.r), "\(token)/\(appearance) 的红分量越界: \(c.r)")
                #expect((0.0...1.0).contains(c.g), "\(token)/\(appearance) 的绿分量越界: \(c.g)")
                #expect((0.0...1.0).contains(c.b), "\(token)/\(appearance) 的蓝分量越界: \(c.b)")
            }
        }
    }

    // MARK: 明暗自适应（behavioral contract 第 2 点）

    @Test("新增 7 个 token 的 light 取值应与 dark 取值不同（RGBA 分量不全等）")
    func test_peekyThemeParity_allNewTokensDifferBetweenLightAndDarkAppearance() {
        for token in newThemeTokens {
            let light = PeekyTheme.color(token, appearance: .light)
            let dark = PeekyTheme.color(token, appearance: .dark)
            #expect(
                !colorsApproximatelyEqualIncludingAlpha(light, dark),
                "\(token) 的 light 取值不应与 dark 取值相同"
            )
        }
    }

    // MARK: 状态栏对比方向（behavioral contract 第 3 点）

    @Test("light 外观下 statusBarText 应比 statusBarBackground 暗")
    func test_peekyThemeParity_statusBarTextDarkerThanBackgroundInLight() {
        let text = relativeLuminance(PeekyTheme.color(.statusBarText, appearance: .light))
        let background = relativeLuminance(
            PeekyTheme.color(.statusBarBackground, appearance: .light))
        #expect(text < background)
    }

    @Test("dark 外观下 statusBarText 应比 statusBarBackground 亮")
    func test_peekyThemeParity_statusBarTextLighterThanBackgroundInDark() {
        let text = relativeLuminance(PeekyTheme.color(.statusBarText, appearance: .dark))
        let background = relativeLuminance(
            PeekyTheme.color(.statusBarBackground, appearance: .dark))
        #expect(text > background)
    }

    // MARK: chip 对比方向（behavioral contract 第 4 点）

    @Test("light 外观下 foldChipGlyph 应比 foldChipBackground 暗")
    func test_peekyThemeParity_foldChipGlyphDarkerThanBackgroundInLight() {
        let glyph = relativeLuminance(PeekyTheme.color(.foldChipGlyph, appearance: .light))
        let background = relativeLuminance(
            PeekyTheme.color(.foldChipBackground, appearance: .light))
        #expect(glyph < background)
    }

    @Test("dark 外观下 foldChipGlyph 应比 foldChipBackground 亮")
    func test_peekyThemeParity_foldChipGlyphLighterThanBackgroundInDark() {
        let glyph = relativeLuminance(PeekyTheme.color(.foldChipGlyph, appearance: .dark))
        let background = relativeLuminance(
            PeekyTheme.color(.foldChipBackground, appearance: .dark))
        #expect(glyph > background)
    }

    // MARK: 导轨可见且克制（behavioral contract 第 5 点）

    @Test("两外观下 indentGuide 均不应等于 editorBackground")
    func test_peekyThemeParity_indentGuideDiffersFromEditorBackgroundInBothAppearances() {
        for appearance: PeekyTheme.Appearance in [.light, .dark] {
            let guideColor = PeekyTheme.color(.indentGuide, appearance: appearance)
            let background = PeekyTheme.color(.editorBackground, appearance: appearance)
            #expect(
                !colorsApproximatelyEqual(guideColor, background),
                "\(appearance) 下 indentGuide 不应与 editorBackground 相同"
            )
        }
    }

    @Test("light 外观下 indentGuide 与 editorBackground 的亮度差应小于 editorForeground 与 editorBackground 的亮度差")
    func test_peekyThemeParity_indentGuideStaysCloserToBackgroundThanForegroundInLight() {
        let backgroundLuminance = relativeLuminance(
            PeekyTheme.color(.editorBackground, appearance: .light))
        let guideLuminance = relativeLuminance(PeekyTheme.color(.indentGuide, appearance: .light))
        let foregroundLuminance = relativeLuminance(
            PeekyTheme.color(.editorForeground, appearance: .light))

        let guideDiff = abs(guideLuminance - backgroundLuminance)
        let foregroundDiff = abs(foregroundLuminance - backgroundLuminance)
        #expect(
            guideDiff < foregroundDiff,
            "indentGuide 应比 editorForeground 更贴近 editorBackground（导轨应比正文字克制）"
        )
    }

    @Test("dark 外观下 indentGuide 与 editorBackground 的亮度差应小于 editorForeground 与 editorBackground 的亮度差")
    func test_peekyThemeParity_indentGuideStaysCloserToBackgroundThanForegroundInDark() {
        let backgroundLuminance = relativeLuminance(
            PeekyTheme.color(.editorBackground, appearance: .dark))
        let guideLuminance = relativeLuminance(PeekyTheme.color(.indentGuide, appearance: .dark))
        let foregroundLuminance = relativeLuminance(
            PeekyTheme.color(.editorForeground, appearance: .dark))

        let guideDiff = abs(guideLuminance - backgroundLuminance)
        let foregroundDiff = abs(foregroundLuminance - backgroundLuminance)
        #expect(
            guideDiff < foregroundDiff,
            "indentGuide 应比 editorForeground 更贴近 editorBackground（导轨应比正文字克制）"
        )
    }

    // MARK: 三角与描边可见（behavioral contract 第 6 点）

    @Test("两外观下 gutterDisclosure 均不应等于 gutterBackground")
    func test_peekyThemeParity_gutterDisclosureDiffersFromGutterBackgroundInBothAppearances() {
        for appearance: PeekyTheme.Appearance in [.light, .dark] {
            let disclosure = PeekyTheme.color(.gutterDisclosure, appearance: appearance)
            let background = PeekyTheme.color(.gutterBackground, appearance: appearance)
            #expect(
                !colorsApproximatelyEqual(disclosure, background),
                "\(appearance) 下 gutterDisclosure 不应与 gutterBackground 相同"
            )
        }
    }

    @Test("两外观下 foldChipBorder 均不应等于 editorBackground")
    func test_peekyThemeParity_foldChipBorderDiffersFromEditorBackgroundInBothAppearances() {
        for appearance: PeekyTheme.Appearance in [.light, .dark] {
            let border = PeekyTheme.color(.foldChipBorder, appearance: appearance)
            let background = PeekyTheme.color(.editorBackground, appearance: appearance)
            #expect(
                !colorsApproximatelyEqual(border, background),
                "\(appearance) 下 foldChipBorder 不应与 editorBackground 相同"
            )
        }
    }

    // MARK: 既有 token 零回归（behavioral contract 第 7 点）

    @Test("既有 12 个 token 在两外观下仍能解析出非 .clear 颜色（无回归）")
    func test_peekyThemeParity_existingTwelveTokensStillResolveNonClearInBothAppearances() {
        for token in existingThemeTokens {
            for appearance: PeekyTheme.Appearance in [.light, .dark] {
                let color = PeekyTheme.color(token, appearance: appearance)
                #expect(
                    !isClearColor(color),
                    "既有 token \(token) 在 \(appearance) 下不应解析为 .clear（回归）"
                )
            }
        }
    }

    @Test("既有 12 个 token 在 light 与 dark 下的取值仍保持互不相同（沿用既有的明暗差异设计）")
    func test_peekyThemeParity_existingTwelveTokensStillDifferBetweenAppearances() {
        for token in existingThemeTokens {
            let light = PeekyTheme.color(token, appearance: .light)
            let dark = PeekyTheme.color(token, appearance: .dark)
            #expect(
                !colorsApproximatelyEqualIncludingAlpha(light, dark),
                "既有 token \(token) 的 light/dark 取值不应相同（回归）"
            )
        }
    }
}
