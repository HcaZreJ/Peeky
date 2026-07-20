import Testing
import AppKit
@testable import PeekyKit

// MARK: - PeekyTheme 全面用例
//
// 覆盖三个函数的全部契约与 error_case：
//   - hexColor: 6 位/8 位(含 alpha) hex 解析、大小写不敏感、非法输入（缺 `#`、
//     长度错、含非 hex 字符、空串、仅 `#`）一律返回 nil。
//   - color(token, appearance): light/dark 两套 palette 对全部 ThemeColor 均
//     有定义（非 `.clear`）、同一 token 在 light/dark 间不同、同一 appearance 下
//     editorBackground 与 editorForeground 不同。
//   - resolveAppearance: darkAqua/vibrantDark 系 -> .dark；aqua/vibrantLight/
//     nil -> .light。
//
// `PeekyTheme.Appearance`/`ThemeColor` 未声明 `Equatable`，比较一律走下面的
// `isDark` 穷举 switch，不用 `==`（避免依赖未声明的协议一致性，编译期即可发现
// 若签名有变）。NSColor 分量比较先转换到 sRGB 色彩空间，容差 0.005；转换失败
// 经 `try #require`/`throws` 干净失败，不 crash 中止共享测试进程。
//
// 关键：stub 阶段 `color` 恒返回 `.clear`、`hexColor` 恒返回 nil、
// `resolveAppearance` 恒返回 `.light`。对于期望值恰好等于该 stub 退化值的场景
// （invalid hex -> nil、light/nil appearance -> .light），本文件在同一个
// @Test 内额外加入一个"锚点"断言（一个已知合法 hex 必须能解析 / darkAqua 必须
// 解出 `.dark`），确保这些 Test 在 stub 阶段也会呈红，而不是因为退化值巧合吻合
// 期望值而误判通过。

private func sRGBComponents(_ color: NSColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let converted = try #require(color.usingColorSpace(.sRGB), "color must be convertible to the sRGB color space")
    return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
}

private func approxEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.005) -> Bool {
    abs(lhs - rhs) < tolerance
}

/// True if two colors have any RGBA component (in sRGB space) that differs
/// beyond floating-point tolerance.
private func differ(_ a: NSColor, _ b: NSColor) throws -> Bool {
    let ca = try sRGBComponents(a)
    let cb = try sRGBComponents(b)
    return !(approxEqual(ca.red, cb.red) && approxEqual(ca.green, cb.green)
        && approxEqual(ca.blue, cb.blue) && approxEqual(ca.alpha, cb.alpha))
}

/// True if `color` is (approximately) fully transparent black — the stub's
/// degenerate `.clear` return value — used to assert a palette entry has
/// actually been defined with a real color.
private func isClear(_ color: NSColor) throws -> Bool {
    let comps = try sRGBComponents(color)
    return approxEqual(comps.red, 0) && approxEqual(comps.green, 0)
        && approxEqual(comps.blue, 0) && approxEqual(comps.alpha, 0)
}

/// `PeekyTheme.Appearance` does not declare `Equatable` in its definition, so
/// comparisons go through this exhaustive switch instead of `==`.
private func isDark(_ appearance: PeekyTheme.Appearance) -> Bool {
    switch appearance {
    case .dark: return true
    case .light: return false
    }
}

private let allThemeColors: [PeekyTheme.ThemeColor] = [
    .editorBackground, .editorForeground,
    .jsonKey, .jsonString, .jsonNumber, .jsonBool, .jsonNull, .jsonPunctuation,
    .gutterBackground, .gutterText,
    .invalidLineBackground, .invalidLineForeground,
]

private let allAppearances: [PeekyTheme.Appearance] = [.light, .dark]

@Suite("Hidden_peekyTheme")
struct Hidden_peekyTheme {

    // MARK: - hexColor: 合法输入

    @Test(
        "hexColor 解析 6 位 hex 为对应 RGB 分量，alpha 恒为 1.0",
        arguments: [
            (hex: "#000000", red: 0.0, green: 0.0, blue: 0.0),
            (hex: "#FFFFFF", red: 1.0, green: 1.0, blue: 1.0),
            (hex: "#1F1F1F", red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0),
            (hex: "#0A5FD3", red: 10.0 / 255.0, green: 95.0 / 255.0, blue: 211.0 / 255.0),
        ]
    )
    func hexColorParsesSixDigitHexVariousColors(_ testCase: (hex: String, red: Double, green: Double, blue: Double)) throws {
        let color = try #require(PeekyTheme.hexColor(testCase.hex))
        let comps = try sRGBComponents(color)

        let redMatches = approxEqual(comps.red, CGFloat(testCase.red))
        let greenMatches = approxEqual(comps.green, CGFloat(testCase.green))
        let blueMatches = approxEqual(comps.blue, CGFloat(testCase.blue))
        let alphaMatches = approxEqual(comps.alpha, 1.0)

        #expect(redMatches, "red component mismatch for \(testCase.hex)")
        #expect(greenMatches, "green component mismatch for \(testCase.hex)")
        #expect(blueMatches, "blue component mismatch for \(testCase.hex)")
        #expect(alphaMatches, "alpha should default to 1.0 for a 6-digit hex")
    }

    @Test(
        "hexColor 解析 8 位 hex，末两位作为 alpha 分量（含全 0 / 全 1 边界）",
        arguments: [
            (hex: "#1F1F1FCC", red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0, alpha: 204.0 / 255.0),
            (hex: "#000000FF", red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            (hex: "#FFFFFF00", red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
            (hex: "#1F1F1F80", red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0, alpha: 128.0 / 255.0),
        ]
    )
    func hexColorParsesEightDigitHexWithVariousAlpha(_ testCase: (hex: String, red: Double, green: Double, blue: Double, alpha: Double)) throws {
        let color = try #require(PeekyTheme.hexColor(testCase.hex))
        let comps = try sRGBComponents(color)

        let redMatches = approxEqual(comps.red, CGFloat(testCase.red))
        let greenMatches = approxEqual(comps.green, CGFloat(testCase.green))
        let blueMatches = approxEqual(comps.blue, CGFloat(testCase.blue))
        let alphaMatches = approxEqual(comps.alpha, CGFloat(testCase.alpha))

        #expect(redMatches, "red component mismatch for \(testCase.hex)")
        #expect(greenMatches, "green component mismatch for \(testCase.hex)")
        #expect(blueMatches, "blue component mismatch for \(testCase.hex)")
        #expect(alphaMatches, "alpha component mismatch for \(testCase.hex)")
    }

    @Test("hexColor 大小写不敏感：大写/小写/混合大小写输入解析出相同的 RGBA 分量")
    func hexColorIsCaseInsensitive() throws {
        let upper = try #require(PeekyTheme.hexColor("#1F1F1FCC"))
        let lower = try #require(PeekyTheme.hexColor("#1f1f1fcc"))
        let mixed = try #require(PeekyTheme.hexColor("#1F1f1Fcc"))

        let upperComps = try sRGBComponents(upper)
        let lowerComps = try sRGBComponents(lower)
        let mixedComps = try sRGBComponents(mixed)

        let upperLowerRedMatch = approxEqual(upperComps.red, lowerComps.red)
        let upperLowerGreenMatch = approxEqual(upperComps.green, lowerComps.green)
        let upperLowerBlueMatch = approxEqual(upperComps.blue, lowerComps.blue)
        let upperLowerAlphaMatch = approxEqual(upperComps.alpha, lowerComps.alpha)

        #expect(upperLowerRedMatch, "uppercase and lowercase hex should decode to the same red component")
        #expect(upperLowerGreenMatch, "uppercase and lowercase hex should decode to the same green component")
        #expect(upperLowerBlueMatch, "uppercase and lowercase hex should decode to the same blue component")
        #expect(upperLowerAlphaMatch, "uppercase and lowercase hex should decode to the same alpha component")

        let upperMixedRedMatch = approxEqual(upperComps.red, mixedComps.red)
        let upperMixedGreenMatch = approxEqual(upperComps.green, mixedComps.green)
        let upperMixedBlueMatch = approxEqual(upperComps.blue, mixedComps.blue)
        let upperMixedAlphaMatch = approxEqual(upperComps.alpha, mixedComps.alpha)

        #expect(upperMixedRedMatch, "uppercase and mixed-case hex should decode to the same red component")
        #expect(upperMixedGreenMatch, "uppercase and mixed-case hex should decode to the same green component")
        #expect(upperMixedBlueMatch, "uppercase and mixed-case hex should decode to the same blue component")
        #expect(upperMixedAlphaMatch, "uppercase and mixed-case hex should decode to the same alpha component")
    }

    // MARK: - hexColor: 非法输入

    @Test(
        "hexColor 对非法字符串一律返回 nil：缺 #、长度错、含非 hex 字符、空串、仅 #",
        arguments: [
            "1F1F1F",      // missing leading #
            "#1F1F1",      // 5 hex digits: too short
            "#1F1F1FF",    // 7 hex digits: invalid length
            "#1F1F1FFFF",  // 9 hex digits: invalid length
            "#GGGGGG",     // non-hex letters
            "#1F1F1Z",     // trailing non-hex character
            "",            // empty string
            "#",           // just a hash, no digits
        ]
    )
    func hexColorRejectsInvalidStrings(_ invalidHex: String) throws {
        // 锚点：没有这行，退化 stub（对任何输入恒返回 nil）会让下面的
        // "非法输入 -> nil" 断言在 stub 阶段巧合通过，无法呈红。
        _ = try #require(PeekyTheme.hexColor("#000000"), "sanity anchor: a known-valid hex string must still parse")

        #expect(PeekyTheme.hexColor(invalidHex) == nil, "expected nil for invalid hex string: '\(invalidHex)'")
    }

    // MARK: - color(token, appearance): palette 结构

    @Test("light 与 dark 两套 palette 对全部 ThemeColor token 均有定义（非 .clear）")
    func paletteDefinesEveryTokenForBothAppearances() throws {
        for token in allThemeColors {
            for appearance in allAppearances {
                let color = PeekyTheme.color(token, appearance: appearance)
                let clear = try isClear(color)
                #expect(!clear, "\(token) should not be `.clear` for \(appearance) — palette entry missing")
            }
        }
    }

    @Test("每个 ThemeColor token 在 light 与 dark 两个 appearance 下颜色不同")
    func paletteTokenDiffersBetweenLightAndDark() throws {
        for token in allThemeColors {
            let lightColor = PeekyTheme.color(token, appearance: .light)
            let darkColor = PeekyTheme.color(token, appearance: .dark)
            let differs = try differ(lightColor, darkColor)
            #expect(differs, "\(token) should differ between the light and dark palettes")
        }
    }

    @Test("同一 appearance 下 editorBackground 与 editorForeground 颜色不同（light 与 dark 分别验证）")
    func editorBackgroundDiffersFromForegroundBothAppearances() throws {
        for appearance in allAppearances {
            let background = PeekyTheme.color(.editorBackground, appearance: appearance)
            let foreground = PeekyTheme.color(.editorForeground, appearance: appearance)
            let differs = try differ(background, foreground)
            #expect(differs, "editorBackground and editorForeground must be distinct under \(appearance)")
        }
    }

    // MARK: - resolveAppearance

    @Test(
        "dark 系 appearance（darkAqua、vibrantDark）解析为 .dark",
        arguments: ["darkAqua", "vibrantDark"]
    )
    func resolveAppearanceMapsDarkFamilyToDark(_ name: String) throws {
        let appearanceName: NSAppearance.Name = name == "darkAqua" ? .darkAqua : .vibrantDark
        let appearance = try #require(NSAppearance(named: appearanceName))

        let resolvedIsDark = isDark(PeekyTheme.resolveAppearance(appearance))
        #expect(resolvedIsDark, "\(name) should resolve to .dark")
    }

    @Test("resolveAppearance(nil) 解析为 .light")
    func resolveAppearanceNilReturnsLight() throws {
        let nilResolvedIsDark = isDark(PeekyTheme.resolveAppearance(nil))
        #expect(!nilResolvedIsDark, "resolveAppearance(nil) should resolve to .light")

        // 锚点：没有这行，退化 stub（恒返回 .light）会让上面的断言在 stub 阶段
        // 巧合通过，无法呈红。真正的 darkAqua appearance 必须解析为 .dark。
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let darkAquaResolvedIsDark = isDark(PeekyTheme.resolveAppearance(darkAqua))
        #expect(darkAquaResolvedIsDark, "a real darkAqua appearance should resolve to .dark")
    }

    @Test(
        "light 系 appearance（aqua、vibrantLight）解析为 .light",
        arguments: ["aqua", "vibrantLight"]
    )
    func resolveAppearanceLightFamilyReturnsLight(_ name: String) throws {
        let appearanceName: NSAppearance.Name = name == "aqua" ? .aqua : .vibrantLight
        let appearance = try #require(NSAppearance(named: appearanceName))

        let resolvedIsDark = isDark(PeekyTheme.resolveAppearance(appearance))
        #expect(!resolvedIsDark, "\(name) should resolve to .light")

        // 锚点：同上——没有这行，退化 stub 会让上面的断言在 stub 阶段巧合通过。
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let darkAquaResolvedIsDark = isDark(PeekyTheme.resolveAppearance(darkAqua))
        #expect(darkAquaResolvedIsDark, "a real darkAqua appearance should resolve to .dark")
    }
}
