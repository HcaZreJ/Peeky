import Testing
import Foundation
@testable import PeekyKit

// MARK: - Helpers
//
// Markdown 由 PreviewWindowController 前置拦截：≤8MB 走 WebView（不经
// PreviewRenderer），>8MB 落到 PreviewRenderer 的 raw 兜底并保留大纲。这里
// 只断言兜底路径的输出契约（note、raw 文本原样、大纲抽取）。

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

@Suite("Hidden_previewRenderer")
struct Hidden_previewRenderer {

    // MARK: - >8MB 兜底路径：raw 文本 + 大纲

    @Test("readBytes 超过 8MB（formatted 请求）回落 raw 文本并保留大纲")
    func test_previewRenderer_largeMarkdownFallsBackRawNoteFormattedMode() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
    }

    @Test("readBytes 超过 8MB（raw 请求）同样回落 raw 文本并保留大纲")
    func test_previewRenderer_largeMarkdownFallsBackRawNoteRawMode() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
    }

    @Test("大文件回落时 attributedText 内容与原始文本一致（原样展示 raw 文本）")
    func test_previewRenderer_largeMarkdownAttributedTextMatchesRawSourceText() {
        let text = "# Heading\n\nBody paragraph."
        let document = loadedMarkdown(text, readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.attributedText.string == text)
    }

    @Test("大文件回落时多个标题按文档顺序完整抽取进大纲")
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

    // MARK: - 边界：readBytes 严格 > 8MB 才触发回落

    @Test("readBytes 超出 8MB 一个字节即触发回落")
    func test_previewRenderer_boundaryOneByteOver8MBFallsBack() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: eightMB + 1)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
    }

    // MARK: - markdown usesDarkModernTheme / highlightLanguage 恒为 nil

    @Test("markdown 无 dark modern 主题标记，highlightLanguage 为 nil")
    func test_previewRenderer_markdownNoDarkModernNoHighlightLanguage() {
        let document = loadedMarkdown("# Heading\n\nBody paragraph.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(!rendered.usesDarkModernTheme)
        #expect(rendered.highlightLanguage == nil)
    }
}
