import Testing
import Foundation
@testable import PeekyKit

// MARK: - HighlightService 全面用例
//
// 覆盖 language(forExtension:) 的全部映射表 + 未知扩展名、highlight() 的
// 行数/文本重建/dark_modern 颜色断言/未知语言/超预算/空串边界、
// highlightStream() 与 highlight() 的一致性 + 分块覆盖无重叠无缺行 +
// 未知语言/超预算、以及 warmUp() 幂等性。
//
// bundle 加载失败的降级路径不在此测试（单例无法注入坏 bundle，
// 该 error_case 由架构师代码审查覆盖）。

@Suite("Hidden_highlightService")
struct Hidden_highlightService {

    // MARK: - language(forExtension:)

    @Test(
        "every documented extension maps to its shiki language id",
        arguments: [
            (ext: "py", expected: "python"),
            (ext: "ts", expected: "typescript"),
            (ext: "js", expected: "javascript"),
            (ext: "mjs", expected: "javascript"),
            (ext: "cjs", expected: "javascript"),
            (ext: "json", expected: "json"),
            (ext: "yaml", expected: "yaml"),
            (ext: "yml", expected: "yaml"),
            (ext: "toml", expected: "toml"),
            (ext: "sh", expected: "bash"),
            (ext: "bash", expected: "bash"),
            (ext: "zsh", expected: "bash"),
            (ext: "swift", expected: "swift"),
            (ext: "ini", expected: "ini"),
            (ext: "conf", expected: "ini"),
            (ext: "config", expected: "ini"),
        ]
    )
    func languageForExtensionMapsAllKnownExtensions(_ testCase: (ext: String, expected: String)) {
        #expect(HighlightService.language(forExtension: testCase.ext) == testCase.expected)
    }

    @Test(
        "extensions with no shiki mapping (including the empty string) return nil",
        arguments: ["rs", "txt", "", "foobar", "md"]
    )
    func languageForExtensionUnknownExtensionsReturnNil(ext: String) {
        #expect(HighlightService.language(forExtension: ext) == nil)
    }

    // MARK: - highlight(text:language:) — line count / reconstruction

    @Test(
        "highlight() returns exactly one HighlightedLine per line produced by splitting the input on \\n",
        arguments: [
            "",
            "single line, no trailing newline",
            "line one\nline two\nline three",
            "line one\nline two\n",
            "line one\n\nline three",
        ]
    )
    func highlightLineCountMatchesNewlineSplitCounts(source: String) async throws {
        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "python"))
        let expectedCount = source.components(separatedBy: "\n").count
        #expect(lines.count == expectedCount)
    }

    @Test("each returned line's tokens, joined in order, reconstruct the original line text (including blank lines)")
    func highlightReconstructsOriginalLineTextForEachLine() async throws {
        let source = """
        # header comment

        def compute(x, y):
            total = x + y
            return total
        """
        let expectedLines = source.components(separatedBy: "\n")

        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "python"))

        #expect(lines.count == expectedLines.count)
        for (actual, expected) in zip(lines, expectedLines) {
            let reconstructed = actual.map(\.text).joined()
            #expect(reconstructed == expected)
        }
    }

    @Test("an empty string highlights to a single line whose tokens reconstruct to an empty string")
    func highlightEmptyStringReturnsSingleEmptyLine() async throws {
        let lines = try #require(await HighlightService.shared.highlight(text: "", language: "python"))
        #expect(lines.count == 1)
        #expect(lines[0].map(\.text).joined() == "")
    }

    // MARK: - highlight(text:language:) — dark_modern 颜色断言

    @Test("a Python comment line contains a token colored with the dark_modern comment color")
    func highlightPythonCommentColorMatchesDarkModern() async throws {
        let source = "# this line is a comment"
        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "python"))
        try #require(lines.count == 1)
        #expect(lines[0].contains { $0.colorHex.lowercased() == "#6a9955" })
    }

    @Test("a Python 'def' keyword line contains a token colored with the dark_modern keyword color")
    func highlightPythonDefKeywordColorMatchesDarkModern() async throws {
        let source = "def compute():"
        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "python"))
        try #require(lines.count == 1)
        #expect(lines[0].contains { $0.colorHex.lowercased() == "#569cd6" })
    }

    @Test("a JSON string value contains a token colored with the dark_modern string color")
    func highlightJsonStringValueColorMatchesDarkModern() async throws {
        let source = #"{"greeting": "hello world"}"#
        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "json"))
        try #require(lines.count == 1)
        #expect(lines[0].contains { $0.colorHex.lowercased() == "#ce9178" })
    }

    @Test("a JSON number value contains a token colored with the dark_modern number color")
    func highlightJsonNumberColorMatchesDarkModern() async throws {
        let source = #"{"count": 12345}"#
        let lines = try #require(await HighlightService.shared.highlight(text: source, language: "json"))
        try #require(lines.count == 1)
        #expect(lines[0].contains { $0.colorHex.lowercased() == "#b5cea8" })
    }

    // MARK: - highlight(text:language:) — error cases

    @Test("an unrecognized language id returns nil (caller falls back to plain text)")
    func highlightUnknownLanguageReturnsNil() async {
        let result = await HighlightService.shared.highlight(text: "some text", language: "klingon")
        #expect(result == nil)
    }

    @Test("input exceeding the 1.5M UTF-16 budget returns nil regardless of language validity")
    func highlightOverBudgetReturnsNil() async {
        let oversized = String(repeating: "a", count: HighlightService.maxUTF16Length + 1)
        #expect(oversized.utf16.count > HighlightService.maxUTF16Length)

        let result = await HighlightService.shared.highlight(text: oversized, language: "python")
        #expect(result == nil)
    }

    // MARK: - highlightStream(text:language:) — 一致性 + 分块覆盖

    @Test("highlightStream() chunks, sorted by firstLine and flattened, match highlight()'s full result for a multi-line Python sample")
    func highlightStreamMatchesFullHighlightForMultilinePythonInput() async throws {
        let source = """
        # comment line
        def add(a, b):
            return a + b

        def sub(a, b):
            return a - b
        """

        let fullLines = try #require(await HighlightService.shared.highlight(text: source, language: "python"))
        let stream = try #require(HighlightService.shared.highlightStream(text: source, language: "python"))

        var chunks: [HighlightChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        chunks.sort { $0.firstLine < $1.firstLine }
        let reassembled = chunks.flatMap(\.lines)

        #expect(reassembled.count == fullLines.count)
        for (streamed, full) in zip(reassembled, fullLines) {
            #expect(streamed.map(\.text).joined() == full.map(\.text).joined())
        }
    }

    @Test("highlightStream() chunks cover every line exactly once, in order, with no gap and no overlap")
    func highlightStreamChunksCoverAllLinesWithoutOverlapOrGap() async throws {
        let source = "line 0\nline 1\nline 2\nline 3\nline 4"
        let totalLines = source.components(separatedBy: "\n").count

        let stream = try #require(HighlightService.shared.highlightStream(text: source, language: "python"))
        var chunks: [HighlightChunk] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        chunks.sort { $0.firstLine < $1.firstLine }

        var expectedNextLine = 0
        for chunk in chunks {
            #expect(chunk.firstLine == expectedNextLine)
            expectedNextLine += chunk.lines.count
        }
        #expect(expectedNextLine == totalLines)
    }

    @Test("highlightStream() returns nil for an unrecognized language id")
    func highlightStreamUnknownLanguageReturnsNil() {
        let stream = HighlightService.shared.highlightStream(text: "abc", language: "klingon")
        #expect(stream == nil)
    }

    @Test("highlightStream() returns nil for input exceeding the 1.5M UTF-16 budget")
    func highlightStreamOverBudgetReturnsNil() {
        let oversized = String(repeating: "a", count: HighlightService.maxUTF16Length + 1)
        let stream = HighlightService.shared.highlightStream(text: oversized, language: "python")
        #expect(stream == nil)
    }

    // MARK: - warmUp() 幂等性

    @Test("calling warmUp() twice in a row does not crash, and highlight() still works normally afterward")
    func warmUpCalledTwiceDoesNotCrashAndHighlightStillWorksAfterward() async throws {
        HighlightService.shared.warmUp()
        HighlightService.shared.warmUp()

        let lines = try #require(await HighlightService.shared.highlight(text: "x = 1", language: "python"))
        #expect(lines.count == 1)
        #expect(lines[0].map(\.text).joined() == "x = 1")
    }

    // MARK: - 预算常量

    @Test("the documented highlight budget constant is 1.5M UTF-16 code units")
    func maxUTF16LengthConstantMatchesSpecifiedBudget() {
        #expect(HighlightService.maxUTF16Length == 1_500_000)
    }
}
