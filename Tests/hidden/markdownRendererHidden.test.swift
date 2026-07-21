import Testing
import Foundation
@testable import PeekyKit

@Suite("Hidden_markdownRenderer")
struct Hidden_markdownRenderer {

    @Test("outline collects level, title, and 1-indexed source line for every heading in document order")
    func outlineLevelsTitlesAndSourceLines() throws {
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

        let outline = MarkdownRenderer.outline(in: markdown)

        #expect(outline.count == 4)

        let expected: [(level: Int, title: String, sourceLine: Int)] = [
            (1, "Title One", 1),
            (2, "Section Two", 5),
            (3, "Subsection Three", 9),
            (4, "Detail Four", 13),
        ]

        for (item, exp) in zip(outline, expected) {
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

        let outline = MarkdownRenderer.outline(in: markdown)

        #expect(outline.count == 3)
        let expected: [(level: Int, title: String, sourceLine: Int)] = [
            (1, "One", 1),
            (3, "Two", 3),
            (2, "Three", 5),
        ]
        for (item, exp) in zip(outline, expected) {
            #expect(item.level == exp.level)
            #expect(item.title == exp.title)
            #expect(item.sourceLine == exp.sourceLine)
        }
    }

    @Test("headings deeper than level 4 are excluded from the outline")
    func outlineExcludesHeadingsBelowLevelFour() throws {
        let lines = [
            "# One",       // line 1
            "",             // line 2
            "##### Deep",  // line 3 (level 5, excluded)
            "",             // line 4
            "###### Deeper", // line 5 (level 6, excluded)
            "",             // line 6
            "## Two",      // line 7
        ]
        let markdown = lines.joined(separator: "\n")

        let outline = MarkdownRenderer.outline(in: markdown)
        #expect(outline.count == 2)
        #expect(outline[0].title == "One")
        #expect(outline[1].title == "Two")
    }

    @Test("heading title flattens inline formatting (backticks, emphasis) to a plain-text label")
    func outlineFlattensInlineFormattingInHeadingTitle() throws {
        let markdown = "# The `foo` **bar**"
        let outline = MarkdownRenderer.outline(in: markdown)
        #expect(outline.count == 1)
        #expect(outline[0].title == "The foo bar")
    }

    @Test("empty input produces an empty outline")
    func emptyInputProducesEmptyOutline() throws {
        #expect(MarkdownRenderer.outline(in: "").isEmpty)
    }

    @Test("whitespace-only input produces an empty outline")
    func whitespaceOnlyInputProducesEmptyOutline() throws {
        #expect(MarkdownRenderer.outline(in: "\n\n   \n\t\n").isEmpty)
    }

    @Test(
        "degenerate inputs do not crash",
        arguments: [
            "",
            "\n\n   \n\t\n",
            "```swift\nlet x = 1\n",
            "\\*not-em\\*",
        ]
    )
    func robustnessAgainstDegenerateInput(markdown: String) throws {
        _ = MarkdownRenderer.outline(in: markdown)
    }

    @Test("body without any heading yields an empty outline")
    func outlineEmptyForHeadinglessBody() throws {
        let markdown = "Just a paragraph.\n\nAnother paragraph."
        #expect(MarkdownRenderer.outline(in: markdown).isEmpty)
    }
}
