import Testing
import Foundation
import AppKit
@testable import PeekyKit

// MARK: - Attribute helpers
//
// 小工具：从 NSAttributedString 的属性字典里取出 R2 spec 明确给出的断言目标
// （字号/行高/段距/加粗），不涉及渲染器内部实现细节。

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

private func isBold(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.bold)
}

private func location(of substring: String, in text: NSAttributedString) -> Int? {
    let ns = text.string as NSString
    let range = ns.range(of: substring)
    return range.location == NSNotFound ? nil : range.location
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
}
