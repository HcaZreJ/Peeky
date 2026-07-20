import Testing
import Foundation
import AppKit
@testable import PeekyKit

// MARK: - Attribute helpers
//
// 这些 helper 只是把 R2 spec 给定的验收判据（结构/数值断言；颜色只判存在/
// 与正文不同，绝不判具体 RGB——主题自适应）从 NSAttributedString 的原始
// 属性字典里取出来，不涉及渲染器内部实现细节。

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

private func backgroundColor(_ attrs: [NSAttributedString.Key: Any]) -> NSColor? {
    attrs[.backgroundColor] as? NSColor
}

private func isBold(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.bold)
}

private func isItalic(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.italic)
}

/// 等宽判定：spec 明确给出两条可接受路径——fontDescriptor 含 monospace
/// symbolic trait，或字体本身就是 `NSFont.monospacedSystemFont` 的产物。
private func isMonospace(_ font: NSFont) -> Bool {
    if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return true }
    let monospacedName = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular).fontName
    return font.fontName == monospacedName
}

private func strikethroughValue(_ attrs: [NSAttributedString.Key: Any]) -> Int {
    if let intValue = attrs[.strikethroughStyle] as? Int { return intValue }
    if let number = attrs[.strikethroughStyle] as? NSNumber { return number.intValue }
    return 0
}

private func location(of substring: String, in text: NSAttributedString) -> Int? {
    let ns = text.string as NSString
    let range = ns.range(of: substring)
    return range.location == NSNotFound ? nil : range.location
}

private func linkValue(_ attrs: [NSAttributedString.Key: Any]) -> String? {
    if let url = attrs[.link] as? URL { return url.absoluteString }
    if let str = attrs[.link] as? String { return str }
    return nil
}

@Suite("Hidden_markdownRenderer")
struct Hidden_markdownRenderer {

    // MARK: - 正文排版

    @Test(
        "plain paragraphs always use 16pt body font, 1.5x line height, and 16pt paragraph spacing",
        arguments: [
            "A single plain paragraph.",
            "Another paragraph with *no* headings or code in it.",
        ]
    )
    func bodyParagraphTypography(markdown: String) throws {
        let text = MarkdownRenderer.render(markdown)
        let attrs = attributes(of: text, at: 0)

        let bodyFont = try #require(font(attrs))
        #expect(abs(bodyFont.pointSize - 16) < 0.01)

        let style = try #require(paragraphStyle(attrs))
        #expect(abs(style.lineHeightMultiple - 1.5) < 0.01)
        #expect(abs(style.paragraphSpacing - 16) < 0.01)
        // U1: 块间距单侧化——正文段自身的 paragraphSpacingBefore 恒为 0，
        // 间距全部由尾侧 paragraphSpacing 表达，避免与下一段的 spacingBefore 双计。
        #expect(abs(style.paragraphSpacingBefore - 0) < 0.01)
    }

    // MARK: - 标题

    @Test(
        "headings h1-h4 render at the Primer-derived sizes and carry the bold trait",
        arguments: [
            (markdown: "# H1", expectedSize: CGFloat(32)),
            (markdown: "## H2", expectedSize: CGFloat(24)),
            (markdown: "### H3", expectedSize: CGFloat(20)),
            (markdown: "#### H4", expectedSize: CGFloat(16)),
        ]
    )
    func headingSizesAndBold(_ testCase: (markdown: String, expectedSize: CGFloat)) throws {
        let text = MarkdownRenderer.render(testCase.markdown)
        let attrs = attributes(of: text, at: 0)
        let headingFont = try #require(font(attrs))
        #expect(abs(headingFont.pointSize - testCase.expectedSize) < 0.01)
        #expect(isBold(headingFont))
    }

    @Test("heading's visible spacing above (previous paragraph's paragraphSpacing + heading's paragraphSpacingBefore) exceeds its visible spacing below (heading's paragraphSpacing + next paragraph's paragraphSpacingBefore), under the single-sided no-double-count spacing model")
    func test_markdownRenderer_headingVisibleSpacingExceedsAfter() throws {
        let markdown = "Intro paragraph.\n\n# A Heading\n\nBody paragraph."
        let text = MarkdownRenderer.render(markdown)

        guard let introLoc = location(of: "Intro paragraph.", in: text),
              let headingLoc = location(of: "A Heading", in: text),
              let bodyLoc = location(of: "Body paragraph.", in: text) else {
            Issue.record("expected paragraphs/heading not found in rendered output")
            return
        }

        let introStyle = try #require(paragraphStyle(attributes(of: text, at: introLoc)))
        let headingStyle = try #require(paragraphStyle(attributes(of: text, at: headingLoc)))
        let bodyStyle = try #require(paragraphStyle(attributes(of: text, at: bodyLoc)))

        #expect(headingStyle.paragraphSpacingBefore > 0)

        let visibleAbove = introStyle.paragraphSpacing + headingStyle.paragraphSpacingBefore
        let visibleBelow = headingStyle.paragraphSpacing + bodyStyle.paragraphSpacingBefore
        #expect(visibleAbove > visibleBelow)
    }

    // MARK: - 代码

    @Test("fenced code blocks use monospace type at 85% body size, a background color, and tight line height")
    func fencedCodeBlockTypography() throws {
        let markdown = "```swift\nlet x = 1\n```"
        let text = MarkdownRenderer.render(markdown)
        guard let loc = location(of: "let x = 1", in: text) else {
            Issue.record("fenced code content not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)

        let codeFont = try #require(font(attrs))
        #expect(isMonospace(codeFont))
        #expect(abs(codeFont.pointSize - 13.6) < 0.05)

        #expect(backgroundColor(attrs) != nil)

        let style = try #require(paragraphStyle(attrs))
        #expect(style.lineHeightMultiple <= 1.45 + 0.001)
    }

    @Test("inline code spans use monospace type with a background capsule")
    func inlineCodeTypography() throws {
        let text = MarkdownRenderer.render("Some `inlineCode` text.")
        guard let loc = location(of: "inlineCode", in: text) else {
            Issue.record("inline code text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)

        let codeFont = try #require(font(attrs))
        #expect(isMonospace(codeFont))
        #expect(backgroundColor(attrs) != nil)
    }

    @Test("inline code spans are set off from surrounding body text by thin-space separators outside the capsule")
    func inlineCodeThinSpaceSeparators() throws {
        let text = MarkdownRenderer.render("Some `inlineCode` text.")
        let rendered = text.string as NSString

        let codeRange = rendered.range(of: "inlineCode")
        guard codeRange.location != NSNotFound else {
            Issue.record("inline code text not found in rendered output")
            return
        }

        let beforeLoc = codeRange.location - 1
        let afterLoc = NSMaxRange(codeRange)
        #expect(beforeLoc >= 0)
        #expect(rendered.substring(with: NSRange(location: beforeLoc, length: 1)) == "\u{2009}")
        #expect(afterLoc < rendered.length)
        #expect(rendered.substring(with: NSRange(location: afterLoc, length: 1)) == "\u{2009}")

        // 分隔符位于胶囊外：不携带 inline 底色标记，胶囊只包住 code 字符本身。
        #expect(attributes(of: text, at: beforeLoc)[MarkdownRenderer.inlineCodeBackgroundAttributeKey] == nil)
        #expect(attributes(of: text, at: afterLoc)[MarkdownRenderer.inlineCodeBackgroundAttributeKey] == nil)
    }

    // MARK: - GFM 内联特性

    @Test("strikethrough text carries a non-zero strikethroughStyle attribute")
    func strikethroughAttribute() throws {
        let text = MarkdownRenderer.render("This is ~~deleted~~ text.")
        guard let loc = location(of: "deleted", in: text) else {
            Issue.record("strikethrough text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(strikethroughValue(attrs) != 0)
    }

    @Test("explicit markdown links carry a .link attribute matching the URL")
    func explicitLinkAttribute() throws {
        let text = MarkdownRenderer.render("[OpenAI](https://openai.com)")
        guard let loc = location(of: "OpenAI", in: text) else {
            Issue.record("link text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(linkValue(attrs) == "https://openai.com")
    }

    @Test("bare autolink URLs carry a .link attribute matching the URL")
    func autolinkAttribute() throws {
        let text = MarkdownRenderer.render("Visit https://example.com/page for more.")
        guard let loc = location(of: "https://example.com/page", in: text) else {
            Issue.record("autolink text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(linkValue(attrs) == "https://example.com/page")
    }

    @Test("task list items render checkbox glyphs before their label text")
    func taskListCheckboxGlyphs() throws {
        let text = MarkdownRenderer.render("- [x] Done task\n- [ ] Todo task")
        let rendered = text.string

        #expect(rendered.contains("☑"))
        #expect(rendered.contains("☐"))

        let checkedGlyph = try #require(rendered.range(of: "☑"))
        let checkedLabel = try #require(rendered.range(of: "Done task"))
        #expect(checkedGlyph.lowerBound < checkedLabel.lowerBound)

        let uncheckedGlyph = try #require(rendered.range(of: "☐"))
        let uncheckedLabel = try #require(rendered.range(of: "Todo task"))
        #expect(uncheckedGlyph.lowerBound < uncheckedLabel.lowerBound)
    }

    // MARK: - 表格

    @Test("GFM tables render via NSTextTable cells (non-empty paragraphStyle.textBlocks) with a bold header row")
    func tableTextBlocksAndHeaderBold() throws {
        let markdown = """
        | Name | Age |
        | --- | --- |
        | Alice | 30 |
        | Bob | 25 |
        """
        let text = MarkdownRenderer.render(markdown)

        var foundTextBlockRun = false
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty {
                foundTextBlockRun = true
            }
        }
        #expect(foundTextBlockRun, "expected at least one run with a non-empty NSTextTable textBlocks list")

        guard let headerLoc = location(of: "Name", in: text) else {
            Issue.record("table header text not found in rendered output")
            return
        }
        let headerFont = try #require(font(attributes(of: text, at: headerLoc)))
        #expect(isBold(headerFont))
    }

    // MARK: - 引用块

    @Test("blockquotes indent from the leading margin and use a foreground color distinct from body text")
    func blockquoteIndentAndColor() throws {
        let bodyText = MarkdownRenderer.render("Plain body paragraph.")
        let bodyColor = foregroundColor(attributes(of: bodyText, at: 0))

        let quoteText = MarkdownRenderer.render("> A quoted remark.")
        guard let loc = location(of: "quoted remark", in: quoteText) else {
            Issue.record("blockquote text not found in rendered output")
            return
        }
        let quoteAttrs = attributes(of: quoteText, at: loc)

        let quoteStyle = try #require(paragraphStyle(quoteAttrs))
        #expect(quoteStyle.headIndent > 0)

        let quoteColor = foregroundColor(quoteAttrs)
        switch (bodyColor, quoteColor) {
        case let (body?, quote?):
            #expect(!body.isEqual(quote), "blockquote foreground color should differ from body text color")
        case (nil, .some):
            break // 正文未显式设色（用默认色），引用块显式设了次级色——视为不同。
        default:
            Issue.record("blockquote should set a foreground color distinct from body text")
        }
    }

    // MARK: - 列表缩进

    @Test(
        "nested list items indent further than their top-level parent, for both unordered and ordered markers",
        arguments: [
            (markdown: "- Item one\n  - Nested item", marker: "unordered"),
            (markdown: "1. Item one\n   1. Nested item", marker: "ordered"),
        ]
    )
    func listIndentIncreasesWithNesting(_ testCase: (markdown: String, marker: String)) throws {
        let text = MarkdownRenderer.render(testCase.markdown)

        guard let topLoc = location(of: "Item one", in: text),
              let nestedLoc = location(of: "Nested item", in: text) else {
            Issue.record("list item text not found for \(testCase.marker) list")
            return
        }

        let topStyle = try #require(paragraphStyle(attributes(of: text, at: topLoc)))
        let nestedStyle = try #require(paragraphStyle(attributes(of: text, at: nestedLoc)))

        #expect(topStyle.headIndent > 0)
        #expect(nestedStyle.headIndent > topStyle.headIndent)
    }

    @Test(
        "top-level list text starts 2em in, with the marker hanging on a right-aligned tab stop left of the text column",
        arguments: ["- Item one", "1. Item one"]
    )
    func topLevelListLeadingIndent(_ markdown: String) throws {
        let text = MarkdownRenderer.render(markdown)

        guard let loc = location(of: "Item one", in: text) else {
            Issue.record("list item text not found in rendered output")
            return
        }

        let style = try #require(paragraphStyle(attributes(of: text, at: loc)))
        #expect(style.headIndent >= 32)

        // marker 行结构 \t<marker>\t：右对齐 tab 悬挂 marker、左对齐 tab
        // 把首行文本推到 headIndent，与续行同列。
        #expect(text.string.hasPrefix("\t"))
        #expect(style.tabStops.count >= 2)
        let markerStop = try #require(style.tabStops.first)
        #expect(markerStop.alignment == .right)
        #expect(markerStop.location > 0)
        #expect(markerStop.location < style.headIndent)
        #expect(style.tabStops[1].location == style.headIndent)
    }

    // MARK: - 大纲

    @Test("outline collects level, title, and 1-indexed source line for every heading in document order")
    func outlineLevelsTitlesAndSourceLines() throws {
        // sourceLine 假设为 1-indexed —— 与本 repo 既有 `path:line` CLI 约定
        // （PROJECT.md：CLI 参数 path:line[:column] 直开）保持一致；行号计数
        // 包含空行。
        let lines = [
            "# Title One",             // line 1
            "",                          // line 2
            "Some intro text.",        // line 3
            "",                          // line 4
            "## Section Two",          // line 5
            "",                          // line 6
            "More text.",              // line 7
            "",                          // line 8
            "### Subsection Three",    // line 9
            "",                          // line 10
            "Even more.",              // line 11
            "",                          // line 12
            "#### Detail Four",        // line 13
            "",                          // line 14
            "End.",                     // line 15
        ]
        let markdown = lines.joined(separator: "\n")

        let result = MarkdownRenderer.renderWithOutline(markdown)

        #expect(result.outline.count == 4)

        let expected: [(level: Int, title: String, sourceLine: Int)] = [
            (1, "Title One", 1),
            (2, "Section Two", 5),
            (3, "Subsection Three", 9),
            (4, "Detail Four", 13),
        ]

        for (item, exp) in zip(result.outline, expected) {
            #expect(item.level == exp.level)
            #expect(item.title == exp.title)
            #expect(item.sourceLine == exp.sourceLine)
        }
    }

    @Test("outline preserves document order even when heading levels are non-monotonic")
    func outlineHandlesNonMonotonicLevelsInDocumentOrder() throws {
        let lines = [
            "# One",       // line 1
            "",             // line 2
            "### Two",     // line 3
            "",             // line 4
            "## Three",    // line 5
        ]
        let markdown = lines.joined(separator: "\n")

        let result = MarkdownRenderer.renderWithOutline(markdown)

        #expect(result.outline.count == 3)
        let expected: [(level: Int, title: String, sourceLine: Int)] = [
            (1, "One", 1),
            (3, "Two", 3),
            (2, "Three", 5),
        ]
        for (item, exp) in zip(result.outline, expected) {
            #expect(item.level == exp.level)
            #expect(item.title == exp.title)
            #expect(item.sourceLine == exp.sourceLine)
        }
    }

    @Test("outline renderedLocation points at the heading's own text inside attributedText")
    func outlineRenderedLocationPointsToHeadingText() throws {
        let markdown = "# Alpha Heading\n\nBody text.\n\n## Beta Heading\n\nMore body text."
        let result = MarkdownRenderer.renderWithOutline(markdown)
        #expect(result.outline.count == 2)

        for item in result.outline {
            let renderedLoc = try #require(item.renderedLocation)
            let expectedLoc = try #require(location(of: item.title, in: result.attributedText))
            #expect(renderedLoc == expectedLoc)
        }
    }

    // MARK: - 鲁棒性

    @Test(
        "degenerate inputs do not crash and still yield a usable render + outline",
        arguments: [
            "",
            "\n\n   \n\t\n",
            "```swift\nlet x = 1\n",
            "\\*not-em\\*",
        ]
    )
    func robustnessAgainstDegenerateInput(markdown: String) throws {
        let text = MarkdownRenderer.render(markdown)
        #expect(text.length >= 0)

        let result = MarkdownRenderer.renderWithOutline(markdown)
        #expect(result.outline.count >= 0)
    }

    @Test("escaped emphasis markers render as literal asterisks, not italic emphasis")
    func escapedEmphasisRendersAsLiteralText() throws {
        let text = MarkdownRenderer.render("\\*not-em\\*")
        #expect(text.string.contains("*not-em*"))

        if let loc = location(of: "not-em", in: text) {
            let attrs = attributes(of: text, at: loc)
            if let runFont = font(attrs) {
                #expect(!isItalic(runFont))
            }
        }
    }

    @Test("empty input produces an empty outline")
    func emptyInputProducesEmptyOutline() throws {
        let result = MarkdownRenderer.renderWithOutline("")
        #expect(result.outline.isEmpty)
    }

    @Test("whitespace-only input produces an empty outline")
    func whitespaceOnlyInputProducesEmptyOutline() throws {
        let result = MarkdownRenderer.renderWithOutline("\n\n   \n\t\n")
        #expect(result.outline.isEmpty)
    }

    // MARK: - U1 间距整改（块间距单侧化，消除双计）

    @Test("consecutive body paragraphs have zero paragraphSpacingBefore and a combined visible gap of 16pt, not 32pt")
    func test_markdownRenderer_paragraphSpacingNotDoubled() throws {
        let text = MarkdownRenderer.render("Para A.\n\nPara B.")

        guard let locA = location(of: "Para A.", in: text),
              let locB = location(of: "Para B.", in: text) else {
            Issue.record("paragraph text not found in rendered output")
            return
        }

        let styleA = try #require(paragraphStyle(attributes(of: text, at: locA)))
        let styleB = try #require(paragraphStyle(attributes(of: text, at: locB)))

        #expect(abs(styleA.paragraphSpacingBefore - 0) < 0.01)
        #expect(abs(styleB.paragraphSpacingBefore - 0) < 0.01)
        #expect(abs((styleA.paragraphSpacing + styleB.paragraphSpacingBefore) - 16) < 0.01)
    }

    @Test("three consecutive body paragraphs all keep paragraphSpacingBefore at zero (no double-counted margins anywhere in a run)")
    func test_markdownRenderer_multipleConsecutiveParagraphsEachHaveZeroSpacingBefore() throws {
        let text = MarkdownRenderer.render("Para A.\n\nPara B.\n\nPara C.")

        for label in ["Para A.", "Para B.", "Para C."] {
            guard let loc = location(of: label, in: text) else {
                Issue.record("\(label) not found in rendered output")
                continue
            }
            let style = try #require(paragraphStyle(attributes(of: text, at: loc)))
            #expect(abs(style.paragraphSpacingBefore - 0) < 0.01, "\(label) should have paragraphSpacingBefore == 0")
        }
    }

    // MARK: - U1 代码块内部间距 + 标记属性

    @Test("multi-line fenced code block keeps zero paragraphSpacing on interior lines and applies 16pt paragraphSpacing only to the final line")
    func test_markdownRenderer_codeBlockInternalLinesZeroSpacingLastLineSixteen() throws {
        let markdown = "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```\n\nTrailing paragraph."
        let text = MarkdownRenderer.render(markdown)

        guard let firstLoc = location(of: "let a = 1", in: text),
              let middleLoc = location(of: "let b = 2", in: text),
              let lastLoc = location(of: "let c = 3", in: text) else {
            Issue.record("fenced code content not found in rendered output")
            return
        }

        let firstStyle = try #require(paragraphStyle(attributes(of: text, at: firstLoc)))
        let middleStyle = try #require(paragraphStyle(attributes(of: text, at: middleLoc)))
        let lastStyle = try #require(paragraphStyle(attributes(of: text, at: lastLoc)))

        #expect(abs(firstStyle.paragraphSpacing - 0) < 0.01)
        #expect(abs(middleStyle.paragraphSpacing - 0) < 0.01)
        #expect(abs(lastStyle.paragraphSpacing - 16) < 0.01)
    }

    @Test("a single-line fenced code block is both the first and last line of its block, so it carries the 16pt trailing paragraphSpacing")
    func test_markdownRenderer_codeBlockSingleLineGetsSixteen() throws {
        let markdown = "```swift\nlet only = 1\n```"
        let text = MarkdownRenderer.render(markdown)

        guard let loc = location(of: "let only = 1", in: text) else {
            Issue.record("fenced code content not found in rendered output")
            return
        }

        let style = try #require(paragraphStyle(attributes(of: text, at: loc)))
        #expect(abs(style.paragraphSpacing - 16) < 0.01)
    }

    @Test("a fenced code block that opens the document renders without crashing, has no upper margin of its own, and still gives its final line the 16pt trailing spacing")
    func test_markdownRenderer_codeBlockAsFirstDocumentBlockRendersWithoutCrash() throws {
        let markdown = "```swift\nlet first = 1\n```"
        let text = MarkdownRenderer.render(markdown)
        #expect(text.length > 0)

        guard let loc = location(of: "let first = 1", in: text) else {
            Issue.record("fenced code content not found in rendered output")
            return
        }
        let style = try #require(paragraphStyle(attributes(of: text, at: loc)))
        #expect(abs(style.paragraphSpacingBefore - 0) < 0.01)
        #expect(abs(style.paragraphSpacing - 16) < 0.01)
    }

    @Test("every line of a fenced code block carries the codeBlockBackgroundAttributeKey marker, including interior lines")
    func test_markdownRenderer_codeBlockBackgroundAttributePresentOnEveryCodeLine() throws {
        let markdown = "```swift\nlet a = 1\nlet b = 2\nlet c = 3\n```"
        let text = MarkdownRenderer.render(markdown)

        for content in ["let a = 1", "let b = 2", "let c = 3"] {
            guard let loc = location(of: content, in: text) else {
                Issue.record("\(content) not found in rendered output")
                continue
            }
            let attrs = attributes(of: text, at: loc)
            #expect(attrs[MarkdownRenderer.codeBlockBackgroundAttributeKey] != nil, "\(content) should carry codeBlockBackgroundAttributeKey")
        }
    }

    @Test("plain body text does not carry the codeBlockBackgroundAttributeKey marker")
    func test_markdownRenderer_codeBlockBackgroundAttributeAbsentOnBodyText() throws {
        let text = MarkdownRenderer.render("A plain paragraph of body text.")
        let attrs = attributes(of: text, at: 0)
        #expect(attrs[MarkdownRenderer.codeBlockBackgroundAttributeKey] == nil)
    }

    @Test("inline code spans do not carry the codeBlockBackgroundAttributeKey marker (only fenced/indented/HTML code blocks do)")
    func test_markdownRenderer_codeBlockBackgroundAttributeAbsentOnInlineCode() throws {
        let text = MarkdownRenderer.render("Some `inlineCode` text.")
        guard let loc = location(of: "inlineCode", in: text) else {
            Issue.record("inline code text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(attrs[MarkdownRenderer.codeBlockBackgroundAttributeKey] == nil)
    }

    // MARK: - U1 鲁棒性

    @Test(
        "empty or whitespace-only input renders an empty attributed string without crashing",
        arguments: [
            "",
            "\n\n   \n\t\n",
        ]
    )
    func test_markdownRenderer_emptyOrWhitespaceInputProducesEmptyOutput(markdown: String) throws {
        let text = MarkdownRenderer.render(markdown)
        #expect(text.length == 0)
    }

    // MARK: - V1 行内代码标记属性

    @Test("inline code text carries inlineCodeBackgroundAttributeKey, distinct from the pre-existing codeBlockBackgroundAttributeKey")
    func test_markdownRenderer_inlineCodeCarriesInlineBackgroundMarker() throws {
        let text = MarkdownRenderer.render("Some `inlineCode` text.")
        guard let loc = location(of: "inlineCode", in: text) else {
            Issue.record("inline code text not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(attrs[MarkdownRenderer.inlineCodeBackgroundAttributeKey] != nil)
        // 行内代码原有的 .backgroundColor（非 nil）保持不变。
        #expect(backgroundColor(attrs) != nil)
    }

    @Test("plain body text does not carry inlineCodeBackgroundAttributeKey")
    func test_markdownRenderer_inlineMarkerAbsentOnBodyText() throws {
        let text = MarkdownRenderer.render("A plain paragraph of body text.")
        let attrs = attributes(of: text, at: 0)
        #expect(attrs[MarkdownRenderer.inlineCodeBackgroundAttributeKey] == nil)
    }

    @Test("fenced code block content carries codeBlockBackgroundAttributeKey but not inlineCodeBackgroundAttributeKey — the two markers never cross over")
    func test_markdownRenderer_inlineMarkerAbsentOnFencedCodeBlock() throws {
        let markdown = "```swift\nlet x = 1\n```"
        let text = MarkdownRenderer.render(markdown)
        guard let loc = location(of: "let x = 1", in: text) else {
            Issue.record("fenced code content not found in rendered output")
            return
        }
        let attrs = attributes(of: text, at: loc)
        #expect(attrs[MarkdownRenderer.codeBlockBackgroundAttributeKey] != nil)
        #expect(attrs[MarkdownRenderer.inlineCodeBackgroundAttributeKey] == nil)
    }
}
