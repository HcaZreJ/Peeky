import Testing
import Foundation
@testable import PeekyKit

@Suite("Visible_markdownRenderer")
struct Visible_markdownRenderer {

    @Test("outline extracts heading structure with correct level, title, and 1-indexed sourceLine")
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

        let outline = MarkdownRenderer.outline(in: markdown)

        #expect(outline.count == 2)

        #expect(outline[0].level == 1)
        #expect(outline[0].title == "Getting Started")
        #expect(outline[0].sourceLine == 1)

        #expect(outline[1].level == 2)
        #expect(outline[1].title == "Installation")
        #expect(outline[1].sourceLine == 5)
    }
}
