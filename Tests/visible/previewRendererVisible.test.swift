import Testing
import Foundation
import AppKit
@testable import PeekyKit

// MARK: - Helpers
//
// Markdown 文档恒以 formatted 富文本渲染的行为断言：这里只构造 LoadedText
// 输入并检视 PreviewRenderer.render 的输出契约（字体/主题/note/大纲），不
// 涉及渲染器内部实现细节。

@Suite("Visible_previewRenderer")
struct Visible_previewRenderer {
    private func loadedMarkdown(_ text: String, readBytes: Int? = nil) -> LoadedText {
        let byteCount = text.utf8.count
        return LoadedText(
            url: URL(fileURLWithPath: "/tmp/sample.md"),
            kind: .markdown,
            text: text,
            totalBytes: Int64(readBytes ?? byteCount),
            readBytes: readBytes ?? byteCount,
            isTruncated: false,
            encodingName: "UTF-8"
        )
    }

    private func headingFont(in rendered: RenderedPreview, substring: String = "Heading") throws -> NSFont {
        let ns = rendered.attributedText.string as NSString
        let range = ns.range(of: substring)
        #expect(range.location != NSNotFound)
        return try #require(rendered.attributedText.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }

    @Test("markdown 在 raw 模式下仍以 formatted 富文本渲染标题：32pt 加粗")
    func test_previewRenderer_markdownRawModeStillFormatsHeading() throws {
        let document = loadedMarkdown("# Heading\n\nSome body text.")
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        let font = try headingFont(in: rendered)
        #expect(abs(font.pointSize - 32) < 0.01)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!rendered.usesDarkModernTheme)
    }

    @Test("markdown 在 formatted 模式下渲染标题：32pt 加粗，主题恒非 dark modern")
    func test_previewRenderer_markdownFormattedModeFormatsHeading() throws {
        let document = loadedMarkdown("# Heading\n\nSome body text.")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        let font = try headingFont(in: rendered)
        #expect(abs(font.pointSize - 32) < 0.01)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!rendered.usesDarkModernTheme)
    }

    @Test("readBytes 超过 8MB 的 markdown 回落 raw 文本，note 提示且大纲非空")
    func test_previewRenderer_largeMarkdownFallsBackToRawWithOutline() throws {
        let document = loadedMarkdown("# Heading\n\nSome body text.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
    }
}
