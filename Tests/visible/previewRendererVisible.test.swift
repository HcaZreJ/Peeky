import Testing
import Foundation
@testable import PeekyKit

// MARK: - Helpers
//
// PreviewRenderer 只处理 markdown 的 >8MB raw 兜底路径（≤8MB 由
// PreviewWindowController 前置拦截、走 WebView），这里断言兜底路径仍产
// note + 保留大纲。

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

    @Test("readBytes 超过 8MB 的 markdown 回落 raw 文本，note 提示且大纲非空")
    func test_previewRenderer_largeMarkdownFallsBackToRawWithOutline() throws {
        let document = loadedMarkdown("# Heading\n\nSome body text.", readBytes: 9 * 1024 * 1024)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.note == "Raw preview for large file")
        #expect(!rendered.outline.isEmpty)
        #expect(rendered.attributedText.string == "# Heading\n\nSome body text.")
    }
}
