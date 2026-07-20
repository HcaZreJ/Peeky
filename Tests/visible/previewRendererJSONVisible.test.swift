import Testing
import Foundation
@testable import PeekyKit

// MARK: - PreviewRenderer JSON/JSONL 分支：可见样例
//
// 覆盖 `.formatted` 模式下三条主干路径：JSON 可解析、JSON 不可解析、JSONL
// 混合坏行。attributedText 的内容与 JSONL 坏行 range 均以 JSONFormatter 的
// 纯函数输出（`prettyJSON` / `prettyJSONLines`）为 oracle，note 文案、
// usesJSONHighlighting / followsSystemAppearance / highlightLanguage 三个
// 装配位标志按 spec 逐条断言。

@Suite("Visible_previewRendererJSON")
struct Visible_previewRendererJSON {
    private func loadedText(_ text: String, kind: FileKind, readBytes: Int? = nil) -> LoadedText {
        let bytes = readBytes ?? text.utf8.count
        return LoadedText(
            url: URL(fileURLWithPath: kind == .json ? "/tmp/sample.json" : "/tmp/sample.jsonl"),
            kind: kind,
            text: text,
            totalBytes: Int64(bytes),
            readBytes: bytes,
            isTruncated: false,
            encodingName: "UTF-8"
        )
    }

    @Test("JSON 可解析：attributedText 与 JSONFormatter.prettyJSON 一致，note 为 Formatted")
    func jsonValidFormattedMatchesPrettyJSONOracle() throws {
        let text = "{\"a\": 1, \"b\": [1, 2, 3]}"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let expected = try JSONFormatter.prettyJSON(text)

        #expect(rendered.attributedText.string == expected)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
        #expect(rendered.highlightLanguage == nil)
    }

    @Test("JSON 不可解析：attributedText 保留原文，note 为 Invalid JSON")
    func jsonInvalidFormattedPreservesOriginalText() {
        let text = "{bad"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.attributedText.string == text)
        #expect(rendered.note == "Invalid JSON")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
        #expect(rendered.highlightLanguage == nil)
    }

    @Test("JSONL 混合坏行：attributedText 与坏行 range 以 JSONFormatter.prettyJSONLines 为 oracle")
    func jsonlMixedInvalidMatchesOracle() {
        let text = "{\"id\": 1}\nnot json\n{\"id\": 3}"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)
        let expectedInvalidRanges = oracle.records.filter(\.isInvalid).map(\.range)

        #expect(rendered.attributedText.string == oracle.text)
        #expect(rendered.display.invalidRecordRanges == expectedInvalidRanges)
        #expect(rendered.note == "Formatted, \(oracle.invalidLineCount) invalid line(s)")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
        #expect(rendered.highlightLanguage == nil)
    }
}
