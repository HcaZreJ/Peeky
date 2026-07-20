import Testing
import Foundation
@testable import PeekyKit

// MARK: - PreviewRenderer JSON/JSONL 分支：全面用例
//
// 覆盖 `render(document:mode:collapseNestedJSON:)` 在 `.formatted` 模式下
// 的 JSON 与 JSONL 分支契约：
// - JSON 可解析（对象/数组/深层嵌套）与不可解析（残缺括号/多余逗号/空文本）
//   两条路径下 attributedText / note / usesJSONHighlighting /
//   followsSystemAppearance / highlightLanguage 的取值。
// - 8MB 富格式化上限对 JSON/JSONL 豁免：`readBytes` 超过 8MB 时仍走
//   formatted，不降级为 raw。
// - JSONL 坏行 range：全部合法、全部非法、合法与非法混合三种组合下
//   `display.invalidRecordRanges` 与 note 的 "N invalid line(s)" 文案。
//
// JSONFormatter.prettyJSON / prettyJSONLines 是纯函数 oracle，测试断言
// render 分支产出与其逐字节/逐 range 一致；不猜测未在 spec 中写明的行为
// （例如 collapse 是否对 JSONL 生效未在 spec 断言范围内，故不测）。

@Suite("Hidden_previewRendererJSON")
struct Hidden_previewRendererJSON {
    private static let largeReadBytes = 9_000_000 // > 8 * 1024 * 1024

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

    // MARK: - JSON：可解析

    @Test("JSON 对象：attributedText 与 JSONFormatter.prettyJSON 一致")
    func renderJsonValidObjectMatchesPrettyJSONOracle() throws {
        let text = "{\"a\": 1, \"b\": 2}"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let expected = try JSONFormatter.prettyJSON(text)

        #expect(rendered.attributedText.string == expected)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
    }

    @Test("JSON 顶层数组：attributedText 与 JSONFormatter.prettyJSON 一致")
    func renderJsonValidArrayTopLevelMatchesPrettyJSONOracle() throws {
        let text = "[1, 2, {\"c\": 3}]"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let expected = try JSONFormatter.prettyJSON(text)

        #expect(rendered.attributedText.string == expected)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    @Test("JSON 深层嵌套：完整展开，不出现折叠占位符，且与 oracle 一致")
    func renderJsonDeeplyNestedMatchesPrettyJSONOracleWithoutFoldPlaceholders() throws {
        let text = "{\"outer\":{\"inner\":{\"deep\":[1,2,3]}}}"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let expected = try JSONFormatter.prettyJSON(text)

        #expect(rendered.attributedText.string == expected)
        #expect(!rendered.attributedText.string.contains("{ ... }"))
        #expect(!rendered.attributedText.string.contains("[ ... ]"))
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    // MARK: - JSON：不可解析

    @Test("JSON 残缺括号：attributedText 保留原文，note 为 Invalid JSON")
    func renderJsonInvalidMalformedBracesPreservesOriginalText() {
        let text = "[1, 2,"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.attributedText.string == text)
        #expect(rendered.note == "Invalid JSON")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    @Test("JSON 缺失值（{\"a\":}）：不可解析，note 为 Invalid JSON，装配标志置位")
    func renderJsonInvalidMissingValueNoteInvalidJSON() {
        // 注意：JSONSerialization 会接受尾随逗号（{"a":1,} 合法），故此处用
        // 缺失值 {"a":} 作为确实非法的输入来验证 Invalid 分支。
        let text = "{\"a\":}"
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.attributedText.string == text)
        #expect(rendered.note == "Invalid JSON")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    @Test("JSON 空文本：不崩溃，按 JSONFormatter.prettyJSON 能否解析归类到 Formatted 或 Invalid JSON")
    func renderJsonEmptyTextDoesNotCrashAndMatchesOracleBranch() {
        let text = ""
        let document = loadedText(text, kind: .json)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        if let expected = try? JSONFormatter.prettyJSON(text) {
            #expect(rendered.attributedText.string == expected)
            #expect(rendered.note == "Formatted")
        } else {
            #expect(rendered.attributedText.string == text)
            #expect(rendered.note == "Invalid JSON")
        }
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    // MARK: - JSON：8MB 富格式化上限豁免

    @Test("JSON readBytes 超过 8MB 时仍走 formatted，不降级为 raw")
    func renderJsonLargeReadBytesExemptionStillUsesJSONHighlighting() throws {
        let text = "{\"a\": 1}"
        let document = loadedText(text, kind: .json, readBytes: Self.largeReadBytes)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let expected = try JSONFormatter.prettyJSON(text)

        #expect(rendered.attributedText.string == expected)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.note != "Raw preview for large file")
    }

    // MARK: - JSON：装配位标志

    @Test("JSON 可解析与不可解析两条路径下 highlightLanguage 均为 nil")
    func renderJsonHighlightLanguageAlwaysNilForValidAndInvalid() {
        let validDocument = loadedText("{\"a\": 1}", kind: .json)
        let invalidDocument = loadedText("{bad", kind: .json)

        let validRendered = PreviewRenderer.render(document: validDocument, mode: .formatted)
        let invalidRendered = PreviewRenderer.render(document: invalidDocument, mode: .formatted)

        #expect(validRendered.highlightLanguage == nil)
        #expect(invalidRendered.highlightLanguage == nil)
        #expect(validRendered.followsSystemAppearance)
        #expect(invalidRendered.followsSystemAppearance)
    }

    // MARK: - JSONL：坏行 range 与 note

    @Test("JSONL 全部合法行：invalidRecordRanges 为空，note 为 Formatted")
    func renderJsonlAllValidLinesNoInvalidRangesNoteFormatted() {
        let text = "{\"a\": 1}\n{\"b\": 2}\n{\"c\": 3}"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)

        #expect(oracle.invalidLineCount == 0)
        #expect(rendered.attributedText.string == oracle.text)
        #expect(rendered.display.invalidRecordRanges.isEmpty)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    @Test("JSONL 全部非法行（两行）：invalidRecordRanges 覆盖两行，note 含 2 invalid line(s)")
    func renderJsonlAllInvalidLinesBothRangesReturnedNoteHasCountTwo() {
        let text = "not json\nalso bad"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)
        let expectedInvalidRanges = oracle.records.filter(\.isInvalid).map(\.range)

        #expect(oracle.invalidLineCount == 2)
        #expect(expectedInvalidRanges.count == 2)
        #expect(rendered.attributedText.string == oracle.text)
        #expect(rendered.display.invalidRecordRanges == expectedInvalidRanges)
        #expect(rendered.note == "Formatted, 2 invalid line(s)")
    }

    @Test("JSONL 合法与非法混合：invalidRecordRanges 只含坏行 range")
    func renderJsonlMixedValidInvalidRangesOnlyCoverInvalidLines() {
        let text = "{\"id\": 1}\nnot json\n{\"id\": 3}"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)
        let expectedInvalidRanges = oracle.records.filter(\.isInvalid).map(\.range)

        #expect(expectedInvalidRanges.count == 1)
        #expect(rendered.display.invalidRecordRanges == expectedInvalidRanges)
        #expect(rendered.display.invalidRecordRanges.count == 1)
    }

    @Test("JSONL 单一非法行：note 文案精确为 Formatted, 1 invalid line(s)")
    func renderJsonlSingleInvalidLineNoteSingularCount() {
        let text = "{\"a\": 1}\nbad line"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)

        #expect(oracle.invalidLineCount == 1)
        #expect(rendered.note == "Formatted, 1 invalid line(s)")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    @Test("JSONL 空文本：不崩溃，输出为空且 note 为 Formatted")
    func renderJsonlEmptyTextDoesNotCrashAndProducesEmptyOutput() {
        let text = ""
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)

        #expect(oracle.records.isEmpty)
        #expect(rendered.attributedText.string == oracle.text)
        #expect(rendered.display.invalidRecordRanges.isEmpty)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
    }

    // MARK: - JSONL：8MB 富格式化上限豁免

    @Test("JSONL readBytes 超过 8MB 时仍走 formatted，不降级为 raw")
    func renderJsonlLargeReadBytesExemptionStillFormatted() {
        let text = "{\"a\": 1}\n{\"b\": 2}"
        let document = loadedText(text, kind: .jsonl, readBytes: Self.largeReadBytes)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)
        let oracle = JSONFormatter.prettyJSONLines(text)

        #expect(rendered.attributedText.string == oracle.text)
        #expect(rendered.note == "Formatted")
        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.note != "Raw preview for large file")
    }

    // MARK: - JSONL：装配位标志

    @Test("JSONL 分支 usesJSONHighlighting / followsSystemAppearance 为 true，highlightLanguage 为 nil")
    func renderJsonlAssemblyFlagsMatchContract() {
        let text = "{\"a\": 1}\n{\"b\": 2}"
        let document = loadedText(text, kind: .jsonl)

        let rendered = PreviewRenderer.render(document: document, mode: .formatted)

        #expect(rendered.usesJSONHighlighting)
        #expect(rendered.followsSystemAppearance)
        #expect(rendered.highlightLanguage == nil)
    }
}
