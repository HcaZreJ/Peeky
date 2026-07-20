import Testing
import Foundation
import AppKit
@testable import PeekyKit

// MARK: - Attribute helpers
//
// 小工具：从 NSAttributedString 的属性字典里取出 R2 spec 明确给出的断言目标
// （字号/行高/段距/加粗/颜色），不涉及渲染器内部实现细节。

private func attributes(of text: NSAttributedString, at location: Int) -> [NSAttributedString.Key: Any] {
    guard text.length > location, location >= 0 else { return [:] }
    return text.attributes(at: location, effectiveRange: nil)
}

private func font(_ attrs: [NSAttributedString.Key: Any]) -> NSFont? {
    attrs[.font] as? NSFont
}

private func paragraphStyle(_ attrs: [NSAttributedString.Key: Any]) -> NSParagraphStyle? {
    attrs[.paragraphStyle] as? NSParagraphStyle
}

private func foregroundColor(_ attrs: [NSAttributedString.Key: Any]) -> NSColor? {
    attrs[.foregroundColor] as? NSColor
}

private func underlineColor(_ attrs: [NSAttributedString.Key: Any]) -> NSColor? {
    attrs[.underlineColor] as? NSColor
}

private func underlineStyleValue(_ attrs: [NSAttributedString.Key: Any]) -> Int {
    if let intValue = attrs[.underlineStyle] as? Int { return intValue }
    if let number = attrs[.underlineStyle] as? NSNumber { return number.intValue }
    return 0
}

private func isBold(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.bold)
}

private func location(of substring: String, in text: NSAttributedString) -> Int? {
    let ns = text.string as NSString
    let range = ns.range(of: substring)
    return range.location == NSNotFound ? nil : range.location
}

// MARK: - Color matching helpers (github-markdown-css targets, resolved per-appearance)
//
// 颜色目标为动态 NSColor（浅/深两套），必须在指定外观下 resolve 后逐通道比对，
// 见 spec 提供的 `performAsCurrent` 取色模式。

/// `"light"` -> `.aqua`，`"dark"` -> `.darkAqua`。用字符串标签而非直接把
/// NSAppearance 塞进 `@Test(arguments:)`，规避 Swift 6 严格并发对非 Sendable
/// 类型出现在参数化测试 arguments 里的顾虑。
private func appearanceFor(_ name: String) -> NSAppearance {
    NSAppearance(named: name == "dark" ? .darkAqua : .aqua)!
}

private func rgba(_ color: NSColor, in appearance: NSAppearance) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    var result: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    appearance.performAsCurrentDrawingAppearance {
        let converted = color.usingColorSpace(.sRGB) ?? color
        result = (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }
    return result
}

/// 解析 `RRGGBB` 或 `RRGGBBAA`（末两位=alpha）十六进制颜色目标为 0...1 分量。
private func targetRGBA(hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    let hasAlpha = hex.count == 8
    let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
    let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
    let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
    let a = hasAlpha ? CGFloat(value & 0xFF) / 255.0 : 1.0
    return (r, g, b, a)
}

private func expectColorMatches(
    _ color: NSColor?,
    hex: String,
    appearanceName: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let resolved = try #require(color, "expected a non-nil color to compare against #\(hex)", sourceLocation: sourceLocation)
    let actual = rgba(resolved, in: appearanceFor(appearanceName))
    let target = targetRGBA(hex: hex)
    #expect(abs(actual.0 - target.0) < 0.01, "red channel mismatch for #\(hex) (\(appearanceName))", sourceLocation: sourceLocation)
    #expect(abs(actual.1 - target.1) < 0.01, "green channel mismatch for #\(hex) (\(appearanceName))", sourceLocation: sourceLocation)
    #expect(abs(actual.2 - target.2) < 0.01, "blue channel mismatch for #\(hex) (\(appearanceName))", sourceLocation: sourceLocation)
    #expect(abs(actual.3 - target.3) < 0.01, "alpha channel mismatch for #\(hex) (\(appearanceName))", sourceLocation: sourceLocation)
}

@Suite("Visible_markdownRenderer")
struct Visible_markdownRenderer {

    @Test("plain body paragraph gets GitHub Primer body typography: 16pt, 1.5x line height, 16pt paragraph spacing")
    func bodyParagraphTypography() throws {
        let text = MarkdownRenderer.render("A plain paragraph of body text.")
        let attrs = attributes(of: text, at: 0)

        let bodyFont = try #require(font(attrs))
        #expect(abs(bodyFont.pointSize - 16) < 0.01)

        let style = try #require(paragraphStyle(attrs))
        #expect(abs(style.lineHeightMultiple - 1.5) < 0.01)
        #expect(abs(style.paragraphSpacing - 16) < 0.01)
    }

    @Test("heading levels 1-4 render at the Primer-derived sizes (32/24/20/16) and carry the bold trait")
    func headingSizesAndBoldTrait() throws {
        let cases: [(markdown: String, expectedSize: CGFloat)] = [
            ("# Heading One", 32),
            ("## Heading Two", 24),
            ("### Heading Three", 20),
            ("#### Heading Four", 16),
        ]

        for testCase in cases {
            let text = MarkdownRenderer.render(testCase.markdown)
            let attrs = attributes(of: text, at: 0)
            let headingFont = try #require(font(attrs), "no font attribute for \(testCase.markdown)")
            #expect(
                abs(headingFont.pointSize - testCase.expectedSize) < 0.01,
                "\(testCase.markdown) expected \(testCase.expectedSize)pt, got \(headingFont.pointSize)"
            )
            #expect(isBold(headingFont), "\(testCase.markdown) should carry the bold trait")
        }
    }

    @Test("renderWithOutline extracts heading structure with correct level/title/sourceLine and a renderedLocation pointing at the heading text")
    func outlineExtraction() throws {
        let lines = [
            "# Getting Started",     // line 1
            "",                       // line 2
            "Welcome to the docs.",  // line 3
            "",                       // line 4
            "## Installation",       // line 5
            "",                       // line 6
            "Run the installer.",    // line 7
        ]
        let markdown = lines.joined(separator: "\n")

        let result = MarkdownRenderer.renderWithOutline(markdown)

        #expect(result.outline.count == 2)

        #expect(result.outline[0].level == 1)
        #expect(result.outline[0].title == "Getting Started")
        #expect(result.outline[0].sourceLine == 1)

        #expect(result.outline[1].level == 2)
        #expect(result.outline[1].title == "Installation")
        #expect(result.outline[1].sourceLine == 5)

        // renderedLocation 应指向 attributedText 中该标题文本本身的位置。
        let firstLoc = try #require(result.outline[0].renderedLocation)
        let expectedFirstLoc = try #require(location(of: "Getting Started", in: result.attributedText))
        #expect(firstLoc == expectedFirstLoc)

        let secondLoc = try #require(result.outline[1].renderedLocation)
        let expectedSecondLoc = try #require(location(of: "Installation", in: result.attributedText))
        #expect(secondLoc == expectedSecondLoc)
    }

    // MARK: - U1 间距整改 + 代码块标记属性

    @Test("consecutive body paragraphs have a combined visible gap of 16pt (previous paragraphSpacing + next paragraphSpacingBefore), not 32pt")
    func test_markdownRenderer_paragraphSpacingNotDoubled() throws {
        let text = MarkdownRenderer.render("Para A.\n\nPara B.")

        let locA = try #require(location(of: "Para A.", in: text))
        let locB = try #require(location(of: "Para B.", in: text))

        let styleA = try #require(paragraphStyle(attributes(of: text, at: locA)))
        let styleB = try #require(paragraphStyle(attributes(of: text, at: locB)))

        #expect(abs(styleA.paragraphSpacingBefore - 0) < 0.01)
        #expect(abs(styleB.paragraphSpacingBefore - 0) < 0.01)
        #expect(abs((styleA.paragraphSpacing + styleB.paragraphSpacingBefore) - 16) < 0.01)
    }

    @Test("a multi-line fenced code block zeroes paragraphSpacing on interior lines, gives its last line 16pt of trailing spacing, and marks every code line with codeBlockBackgroundAttributeKey (absent from surrounding body text)")
    func test_markdownRenderer_codeBlockSpacingAndBackgroundAttribute() throws {
        let markdown = "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```\n\nTrailing paragraph."
        let text = MarkdownRenderer.render(markdown)

        let firstLoc = try #require(location(of: "let a = 1", in: text))
        let lastLoc = try #require(location(of: "let c = 3", in: text))
        let bodyLoc = try #require(location(of: "Trailing paragraph.", in: text))

        let firstStyle = try #require(paragraphStyle(attributes(of: text, at: firstLoc)))
        let lastStyle = try #require(paragraphStyle(attributes(of: text, at: lastLoc)))

        #expect(abs(firstStyle.paragraphSpacing - 0) < 0.01)
        #expect(abs(lastStyle.paragraphSpacing - 16) < 0.01)

        #expect(attributes(of: text, at: firstLoc)[MarkdownRenderer.codeBlockBackgroundAttributeKey] != nil)
        #expect(attributes(of: text, at: lastLoc)[MarkdownRenderer.codeBlockBackgroundAttributeKey] != nil)
        #expect(attributes(of: text, at: bodyLoc)[MarkdownRenderer.codeBlockBackgroundAttributeKey] == nil)
    }

    // MARK: - V1 行内代码标记属性

    @Test("inline code text carries inlineCodeBackgroundAttributeKey, while surrounding body text does not")
    func test_markdownRenderer_inlineCodeCarriesInlineBackgroundMarker() throws {
        let text = MarkdownRenderer.render("Some `inlineCode` text.")

        let inlineLoc = try #require(location(of: "inlineCode", in: text))
        let bodyLoc = try #require(location(of: "Some", in: text))

        #expect(attributes(of: text, at: inlineLoc)[MarkdownRenderer.inlineCodeBackgroundAttributeKey] != nil)
        #expect(attributes(of: text, at: bodyLoc)[MarkdownRenderer.inlineCodeBackgroundAttributeKey] == nil)
    }

    // MARK: - R2 颜色对齐 github-markdown-css

    @Test(
        "plain body text foreground color matches the GitHub Primer target in both light and dark appearance",
        arguments: [
            (appearanceName: "light", hex: "1f2328"),
            (appearanceName: "dark", hex: "f0f6fc"),
        ]
    )
    func test_markdownRenderer_bodyForegroundColorMatchesGithubTarget(_ testCase: (appearanceName: String, hex: String)) throws {
        let text = MarkdownRenderer.render("A plain paragraph of body text.")
        let attrs = attributes(of: text, at: 0)
        try expectColorMatches(foregroundColor(attrs), hex: testCase.hex, appearanceName: testCase.appearanceName)
    }

    @Test(
        "explicit markdown link text foreground color matches the GitHub Primer link target in both light and dark appearance",
        arguments: [
            (appearanceName: "light", hex: "0969da"),
            (appearanceName: "dark", hex: "4493f8"),
        ]
    )
    func test_markdownRenderer_linkForegroundColorMatchesGithubTarget(_ testCase: (appearanceName: String, hex: String)) throws {
        let text = MarkdownRenderer.render("[OpenAI](https://openai.com)")
        let loc = try #require(location(of: "OpenAI", in: text))
        let attrs = attributes(of: text, at: loc)
        try expectColorMatches(foregroundColor(attrs), hex: testCase.hex, appearanceName: testCase.appearanceName)
    }

    @Test(
        "h1 and h2 headings carry an underline whose color matches the GitHub Primer border target in both light and dark appearance",
        arguments: [
            (markdown: "# Heading One", appearanceName: "light", hex: "d1d9e0b3"),
            (markdown: "# Heading One", appearanceName: "dark", hex: "3d444db3"),
            (markdown: "## Heading Two", appearanceName: "light", hex: "d1d9e0b3"),
            (markdown: "## Heading Two", appearanceName: "dark", hex: "3d444db3"),
        ]
    )
    func test_markdownRenderer_h1h2UnderlineColorMatchesGithubTarget(_ testCase: (markdown: String, appearanceName: String, hex: String)) throws {
        let text = MarkdownRenderer.render(testCase.markdown)
        let attrs = attributes(of: text, at: 0)
        #expect(underlineStyleValue(attrs) != 0, "\(testCase.markdown) should carry a non-zero underlineStyle")
        try expectColorMatches(underlineColor(attrs), hex: testCase.hex, appearanceName: testCase.appearanceName)
    }
}
