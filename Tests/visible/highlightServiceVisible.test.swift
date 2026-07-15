import Testing
import Foundation
@testable import PeekyKit

// MARK: - HighlightService 可见样例
//
// 覆盖三条主干契约：扩展名 → language id 映射、全量 highlight() 的行数/
// 文本重建/dark_modern 颜色断言、以及 highlightStream() 与 highlight()
// 结果一致。

/// 把一行 token 依序拼接回原始文本（不含换行符）。
private func joinedText(_ line: HighlightedLine) -> String {
    line.map(\.text).joined()
}

@Suite("Visible_highlightService")
struct Visible_highlightService {
    @Test("常见扩展名映射到对应 shiki language id，未知扩展名映射到 nil")
    func languageForExtensionMapsKnownExtensions() {
        #expect(HighlightService.language(forExtension: "py") == "python")
        #expect(HighlightService.language(forExtension: "json") == "json")
        #expect(HighlightService.language(forExtension: "swift") == "swift")
        #expect(HighlightService.language(forExtension: "rs") == nil)
    }

    @Test("highlight() 对 Python 小样例：行数正确、逐行文本可重建、注释与关键字命中 dark_modern 期望色")
    func highlightPythonSampleProducesExpectedLinesAndColors() async throws {
        let source = "# a comment\ndef greet(name):\n    return name"

        let lines = await HighlightService.shared.highlight(text: source, language: "python")
        let result = try #require(lines)

        // 行数与 "\n" 切分行数一致
        let expectedLineTexts = source.components(separatedBy: "\n")
        #expect(result.count == expectedLineTexts.count)

        // 每行 token 依序拼接 == 原文该行
        for (index, expectedText) in expectedLineTexts.enumerated() {
            #expect(joinedText(result[index]) == expectedText)
        }

        // 注释行含 #6a9955 token；def 关键字行含 #569cd6 token
        #expect(result[0].contains { $0.colorHex.lowercased() == "#6a9955" })
        #expect(result[1].contains { $0.colorHex.lowercased() == "#569cd6" })
    }

    @Test("highlightStream() 分块结果按 firstLine 排序拼接后与 highlight() 全量结果一致")
    func highlightStreamMatchesFullHighlightForJsonSample() async throws {
        let source = #"{"name": "Peeky", "count": 42}"#

        let fullLines = try #require(await HighlightService.shared.highlight(text: source, language: "json"))
        let stream = try #require(HighlightService.shared.highlightStream(text: source, language: "json"))

        var chunks: [HighlightChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        chunks.sort { $0.firstLine < $1.firstLine }

        let reassembledLines = chunks.flatMap(\.lines)
        #expect(reassembledLines.count == fullLines.count)
        for (streamed, full) in zip(reassembledLines, fullLines) {
            #expect(joinedText(streamed) == joinedText(full))
        }
    }
}
