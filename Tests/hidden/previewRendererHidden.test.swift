import Testing
import Foundation
import AppKit
@testable import PeekyKit

// MARK: - Helpers
//
// PreviewRenderer 重构后的核心契约：markdown 文档恒以 formatted 富文本渲染
// （不再因 mode == .raw 退化成纯文本），仅当 readBytes 超过 8MB 才安全回落
// 到 raw 文本（note 固定文案 + 仍保留大纲），且 markdown 的
// usesDarkModernTheme 恒为 false。这些 helper 只是把 spec 给出的断言目标从
// NSAttributedString / RenderedPreview 里取出来，不涉及渲染器内部实现。

private let eightMB = 8 * 1024 * 1024

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

private func location(of substring: String, in attributedText: NSAttributedString) -> Int? {
    let ns = attributedText.string as NSString
    let range = ns.range(of: substring)
    return range.location == NSNotFound ? nil : range.location
}

private func font(at location: Int, in attributedText: NSAttributedString) -> NSFont? {
    guard attributedText.length > location, location >= 0 else { return nil }
    return attributedText.attribute(.font, at: location, effectiveRange: nil) as? NSFont
}

private func isBold(_ font: NSFont) -> Bool {
    font.fontDescriptor.symbolicTraits.contains(.bold)
}

@Suite("Hidden_previewRenderer")
struct Hidden_previewRenderer {

    // MARK: - 核心行为变更：markdown 恒 formatted，忽略传入 mode

    @Test("previewRenderer: markdown 传入 .raw 仍渲染标题为 32pt 加粗（忽略 raw 请求）")
    func test_previewRenderer_markdownRawModeIgnoresRawFlagHeadingBoldFont() throws {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.")
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        let loc = try #require(location(of: "Heading", in: rendered.attributedText))
        let headingFont = try #require(font(at: loc, in: rendered.attributedText))
        #expect(abs(headingFont.pointSize - 32) < 0.01)
        #expect(isBold(headingFont))
    }

    @Test("previewRenderer: markdown 传入 .formatted 渲染标题为 32pt 加粗")
    func test_previewRenderer_markdownFormattedModeHeadingBoldFont() throws {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        let loc = try #require(location(of: "Heading", in: rendered.attributedText))
        let headingFont = try #require(font(at: loc, in: rendered.attributedText))
        #expect(abs(headingFont.pointSize - 32) < 0.01)
        #expect(isBold(headingFont))
    }

    // MARK: - 主题：markdown 恒非 dark modern

    @Test("previewRenderer: markdown formatted 模式下 usesDarkModernTheme 为 false 且 highlightLanguage 为 nil")
    func test_previewRenderer_markdownUsesDarkModernThemeFalseFormatted() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(!rendered.usesDarkModernTheme)
        #expect(rendered.highlightLanguage == nil)
    }

    @Test("previewRenderer: markdown raw 模式下 usesDarkModernTheme 为 false 且 highlightLanguage 为 nil")
    func test_previewRenderer_markdownUsesDarkModernThemeFalseRaw() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.")
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        #expect(!rendered.usesDarkModernTheme)
        #expect(rendered.highlightLanguage == nil)
    }

    // MARK: - 大文件回落（readBytes 严格超过 8MB）

    @Test("previewRenderer: readBytes 超过 8MB（formatted 请求）回落 raw 文本并保留大纲")
    func test_previewRenderer_largeMarkdownFallsBackRawNoteFormattedMode() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
    }

    @Test("previewRenderer: readBytes 超过 8MB（raw 请求）同样回落 raw 文本并保留大纲")
    func test_previewRenderer_largeMarkdownFallsBackRawNoteRawMode() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
    }

    @Test("previewRenderer: 大文件回落时 attributedText 内容与原始文本一致（原样展示 raw 文本）")
    func test_previewRenderer_largeMarkdownAttributedTextMatchesRawSourceText() {
        let text = "# Heading\n\nBody paragraph."
        let document = loadedMarkdown(text, readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.attributedText.string == text)
    }

    @Test("previewRenderer: 大文件回落时多个标题仍被完整抽取进大纲（顺序、层级、标题文本）")
    func test_previewRenderer_largeMarkdownMultipleHeadingsOutlineExtracted() {
        let text = "# Title One\n\nIntro.\n\n## Section Two\n\nMore text."
        let document = loadedMarkdown(text, readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
        #expect(rendered.outline.count == 2)
        #expect(rendered.outline[0].level == 1)
        #expect(rendered.outline[0].title == "Title One")
        #expect(rendered.outline[1].level == 2)
        #expect(rendered.outline[1].title == "Section Two")
    }

    // MARK: - 边界：恰好 8MB 不回落，超出 1 字节即回落

    @Test("previewRenderer: readBytes 恰好等于 8MB 时不回落——标题仍是 32pt 加粗富文本")
    func test_previewRenderer_boundaryExactly8MBDoesNotFallBack() throws {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: eightMB)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note != "Raw preview for large file")

        let loc = try #require(location(of: "Heading", in: rendered.attributedText))
        let headingFont = try #require(font(at: loc, in: rendered.attributedText))
        #expect(abs(headingFont.pointSize - 32) < 0.01)
        #expect(isBold(headingFont))
    }

    @Test("previewRenderer: readBytes 超出 8MB 一个字节即触发回落")
    func test_previewRenderer_boundaryOneByteOver8MBFallsBack() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: eightMB + 1)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
    }

    // MARK: - 空/仅标题/多标题边界

    @Test("previewRenderer: 空 markdown 不崩溃，大纲为空")
    func test_previewRenderer_emptyMarkdownProducesEmptyOutline() {
        let document = loadedMarkdown("")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.outline.isEmpty)
        #expect(rendered.attributedText.length >= 0)
    }

    @Test("previewRenderer: 仅标题无正文的 markdown 产出单条大纲且标题仍是 32pt 加粗")
    func test_previewRenderer_headingOnlyMarkdownProducesSingleOutlineItem() throws {
        let document = loadedMarkdown("# Solo Heading")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.outline.count == 1)
        #expect(rendered.outline[0].title == "Solo Heading")
        #expect(rendered.outline[0].level == 1)

        let loc = try #require(location(of: "Solo Heading", in: rendered.attributedText))
        let headingFont = try #require(font(at: loc, in: rendered.attributedText))
        #expect(abs(headingFont.pointSize - 32) < 0.01)
        #expect(isBold(headingFont))
    }

    @Test("previewRenderer: 含多个标题的 markdown 大纲按文档顺序收录全部标题层级与文本")
    func test_previewRenderer_multipleHeadingsProduceOrderedOutlineItems() {
        let lines = [
            "# Title One",
            "",
            "Intro text.",
            "",
            "## Section Two",
            "",
            "More text.",
            "",
            "### Subsection Three",
        ]
        let document = loadedMarkdown(lines.joined(separator: "\n"))
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.outline.count == 3)
        #expect(rendered.outline[0].level == 1)
        #expect(rendered.outline[0].title == "Title One")
        #expect(rendered.outline[1].level == 2)
        #expect(rendered.outline[1].title == "Section Two")
        #expect(rendered.outline[2].level == 3)
        #expect(rendered.outline[2].title == "Subsection Three")
    }

    @Test("previewRenderer: 无标题的正文 markdown 大纲为空但不崩溃")
    func test_previewRenderer_noHeadingsProducesEmptyOutline() {
        let document = loadedMarkdown("Just a plain paragraph with no headings at all.")
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.outline.isEmpty)
        #expect(rendered.attributedText.length > 0)
    }
}
