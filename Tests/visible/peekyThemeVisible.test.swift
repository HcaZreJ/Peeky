import Testing
import AppKit
@testable import PeekyKit

// MARK: - PeekyTheme 可见样例
//
// 覆盖三条主干契约：hexColor 对 6 位 hex 解析出对应 sRGB 分量（alpha 默认 1.0）、
// hexColor 对 8 位 hex 把末两位解析为 alpha 分量、以及 color(token, appearance)
// 的 palette 结构关系——同一 appearance 下 editorBackground 与 editorForeground
// 不同、同一 token 在 light/dark 两个 appearance 下也不同。
//
// hexColor 的断言可以锁死具体 RGBA 数值（它是固定的解析契约）；color(...) 的
// 断言只判结构关系，绝不锁死具体配色 hex（配色是可调常量）。
//
// 所有 NSColor 分量比较都先转换到 sRGB 色彩空间再取值，容差 0.005 避免浮点抖动；
// 转换失败经 `try #require` 干净失败，不会 crash 中止整个共享测试进程。

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

@Suite("Visible_peekyTheme")
struct Visible_peekyTheme {
    @Test("hexColor 解析 6 位 hex 为对应 sRGB 分量，alpha 默认 1.0")
    func hexColorParsesSixDigitHex() throws {
        let color = try #require(PeekyTheme.hexColor("#1F1F1F"))
        let comps = try sRGBComponents(color)

        let redMatches = approxEqual(comps.red, 31.0 / 255.0)
        let greenMatches = approxEqual(comps.green, 31.0 / 255.0)
        let blueMatches = approxEqual(comps.blue, 31.0 / 255.0)
        let alphaMatches = approxEqual(comps.alpha, 1.0)

        #expect(redMatches, "red component should be ~31/255")
        #expect(greenMatches, "green component should be ~31/255")
        #expect(blueMatches, "blue component should be ~31/255")
        #expect(alphaMatches, "alpha should default to 1.0 for a 6-digit hex")
    }

    @Test("hexColor 解析 8 位 hex，末两位作为 alpha 分量")
    func hexColorParsesEightDigitHexWithAlpha() throws {
        let color = try #require(PeekyTheme.hexColor("#1F1F1FCC"))
        let comps = try sRGBComponents(color)

        let redMatches = approxEqual(comps.red, 31.0 / 255.0)
        let greenMatches = approxEqual(comps.green, 31.0 / 255.0)
        let blueMatches = approxEqual(comps.blue, 31.0 / 255.0)
        let alphaMatches = approxEqual(comps.alpha, 204.0 / 255.0)

        #expect(redMatches, "red component should be ~31/255")
        #expect(greenMatches, "green component should be ~31/255")
        #expect(blueMatches, "blue component should be ~31/255")
        #expect(alphaMatches, "alpha should be ~204/255, decoded from the trailing 8-digit hex byte")
    }

    @Test("同一 appearance 下 editorBackground 与 editorForeground 不同色，且 editorBackground 在 light/dark 间也不同色")
    func colorPaletteHasDistinctRolesAndDiffersAcrossAppearance() throws {
        let lightBackground = PeekyTheme.color(.editorBackground, appearance: .light)
        let lightForeground = PeekyTheme.color(.editorForeground, appearance: .light)
        let backgroundVsForegroundDiffer = try differ(lightBackground, lightForeground)
        #expect(backgroundVsForegroundDiffer, "editorBackground and editorForeground must be distinct colors under the same appearance")

        let darkBackground = PeekyTheme.color(.editorBackground, appearance: .dark)
        let lightVsDarkDiffer = try differ(lightBackground, darkBackground)
        #expect(lightVsDarkDiffer, "editorBackground must differ between the light and dark palettes")
    }
}
