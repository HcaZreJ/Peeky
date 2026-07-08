import Testing
import Foundation
@testable import PeekyKit

@Suite("Visible_previewDisplay")
struct Visible_previewDisplay {
    private func loadedText(_ text: String, kind: FileKind) -> LoadedText {
        LoadedText(
            url: URL(fileURLWithPath: "/tmp/sample"),
            kind: kind,
            text: text,
            totalBytes: Int64(text.utf8.count),
            readBytes: text.utf8.count,
            isTruncated: false,
            encodingName: "UTF-8"
        )
    }

    @Test("json formatted 恢复行号 gutter")
    func jsonFormattedHasLineNumberGutter() {
        let document = loadedText("{\"a\": 1, \"b\": [1, 2]}", kind: .json)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.display.gutter.isVisible)
        guard case .lineNumbers(let starts) = rendered.display.gutter.mode else {
            Issue.record("期望 lineNumbers gutter，实际 \(rendered.display.gutter.mode)")
            return
        }
        #expect(starts.count > 1)
        #expect(rendered.display.textOverlay.showsIndentGuides)
    }

    @Test("json raw 恢复行号 gutter")
    func jsonRawHasLineNumberGutter() {
        let document = loadedText("{\"a\": 1}", kind: .json)
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        #expect(rendered.display.gutter.isVisible)
        guard case .lineNumbers = rendered.display.gutter.mode else {
            Issue.record("期望 lineNumbers gutter，实际 \(rendered.display.gutter.mode)")
            return
        }
    }

    @Test("jsonl formatted 恢复记录 markers gutter")
    func jsonlFormattedHasMarkerGutter() {
        let text = "{\"id\": 1}\nnot json\n{\"id\": 3}"
        let document = loadedText(text, kind: .jsonl)
        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.display.gutter.isVisible)
        guard case .markers(let markers) = rendered.display.gutter.mode else {
            Issue.record("期望 markers gutter，实际 \(rendered.display.gutter.mode)")
            return
        }
        #expect(markers.count == 3)
        #expect(markers.map(\.label) == ["1", "2", "3"])
        #expect(markers.filter(\.isWarning).count == 1)
        #expect(!rendered.display.targetLocationsByOriginalLine.isEmpty)
    }

    @Test("jsonl raw 恢复行号 gutter 且无缩进参考线")
    func jsonlRawHasLineNumberGutter() {
        let document = loadedText("{\"id\": 1}\n{\"id\": 2}", kind: .jsonl)
        let rendered = PreviewRenderer.render(document: document, mode: .raw)

        #expect(rendered.display.gutter.isVisible)
        guard case .lineNumbers = rendered.display.gutter.mode else {
            Issue.record("期望 lineNumbers gutter，实际 \(rendered.display.gutter.mode)")
            return
        }
        #expect(!rendered.display.textOverlay.showsIndentGuides)
    }
}
