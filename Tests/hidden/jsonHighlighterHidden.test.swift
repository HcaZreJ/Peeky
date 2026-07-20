import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONHighlighter 全面用例
//
// 覆盖 tokenize(_:in:) 的单遍词法契约：空输入、key/value 字符串靠"其后
// 是否紧跟 :（跳过空白）"判别、全部结构标点、数字各形态（负号/小数/
// 指数）、true/false/null 字面量、字符串转义（\" \\ \n \uXXXX）在不
// 结束字符串前提下的完整性、未闭合字符串的降级不崩溃、UTF-16 代理对
// range 的精确性、以及 `in:` 子范围参数按 token 起点过滤的语义。
//
// range 均为 UTF-16 偏移，每条 fixture 的位置均手工核对。JSONToken 是
// Equatable，多数用例直接用 `==` 比对整份 token 数组；stub 阶段返回空
// 数组时比较只会断言失败，不会 crash。少数用例（未闭合字符串的 kind
// 允许 .string 或 .key 二选一）先经 `try #require` 锁定数组长度，再对
// 单个 token 做 range 精确断言 + kind 二选一断言，避免下标越界 trap。

private typealias Token = JSONHighlighter.JSONToken
private typealias Kind = JSONHighlighter.JSONTokenKind

private func tok(_ kind: Kind, _ location: Int, _ length: Int) -> Token {
    Token(kind: kind, range: NSRange(location: location, length: length))
}

@Suite("Hidden_jsonHighlighter")
struct Hidden_jsonHighlighter {

    // MARK: - 空输入 / 纯空白

    @Test("空字符串输入返回空 token 数组")
    func tokenizeEmptyStringReturnsEmptyArray() {
        #expect(JSONHighlighter.tokenize("") == [])
    }

    @Test("纯空白（空格/tab/换行混合）输入返回空 token 数组")
    func tokenizeWhitespaceOnlyReturnsEmptyArray() {
        #expect(JSONHighlighter.tokenize("   \n\t  \n") == [])
    }

    // MARK: - key vs value 字符串判别

    @Test("对象内相邻两个字符串：紧跟 : 的判定为 .key，紧跟 } 的判定为 .string")
    func tokenizeObjectKeyAndValueStringDistinguishedByFollowingColon() {
        let text = #"{"a":"b"}"#
        // 0{ 1" 2a 3" 4: 5" 6b 7" 8}

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.key, 1, 3),
            tok(.punctuation, 4, 1),
            tok(.string, 5, 3),
            tok(.punctuation, 8, 1)
        ]
        #expect(tokens == expected)
    }

    @Test("数组内裸字符串其后是 ]，判定为 .string 而非 .key")
    func tokenizeBareStringInArrayIsStringNotKey() {
        let text = #"["a"]"#
        // 0[ 1" 2a 3" 4]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.string, 1, 3),
            tok(.punctuation, 4, 1)
        ]
        #expect(tokens == expected)
    }

    @Test("字符串与冒号之间存在空白时，跳过空白后仍判定为 .key")
    func tokenizeKeyDetectionSkipsWhitespaceBeforeColon() {
        let text = #"{"a" : 1}"#
        // 0{ 1" 2a 3" 4(sp) 5: 6(sp) 7:1 8}

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.key, 1, 3),
            tok(.punctuation, 5, 1),
            tok(.number, 7, 1),
            tok(.punctuation, 8, 1)
        ]
        #expect(tokens == expected)
    }

    // MARK: - 结构标点

    @Test("六种结构标点 { } [ ] , : 各自单独成一个 .punctuation token")
    func tokenizeAllStructuralPunctuationTokens() {
        let text = #"{"a":[1,2]}"#
        // 0{ 1" 2a 3" 4: 5[ 6:1 7, 8:2 9] 10}

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),   // {
            tok(.key, 1, 3),           // "a"
            tok(.punctuation, 4, 1),   // :
            tok(.punctuation, 5, 1),   // [
            tok(.number, 6, 1),        // 1
            tok(.punctuation, 7, 1),   // ,
            tok(.number, 8, 1),        // 2
            tok(.punctuation, 9, 1),   // ]
            tok(.punctuation, 10, 1)   // }
        ]
        #expect(tokens == expected)
    }

    // MARK: - 数字

    @Test("数字：负号、小数、正号指数一并识别为单个 .number token")
    func tokenizeNumberWithSignDecimalAndExponent() {
        let text = "[-12.3e+4]"
        // 0[ 1- 2:1 3:2 4:. 5:3 6:e 7:+ 8:4 9]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.number, 1, 8),
            tok(.punctuation, 9, 1)
        ]
        #expect(tokens == expected)
    }

    // MARK: - true / false / null

    @Test("true/false/null 各自识别为完整字面量 token，逗号后空白被跳过")
    func tokenizeTrueFalseNullLiterals() {
        let text = "[true, false, null]"

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.boolLiteral, 1, 4),
            tok(.punctuation, 5, 1),
            tok(.boolLiteral, 7, 5),
            tok(.punctuation, 12, 1),
            tok(.nullLiteral, 14, 4),
            tok(.punctuation, 18, 1)
        ]
        #expect(tokens == expected)
    }

    // MARK: - 转义字符串完整性

    @Test("转义引号 \\\" 不结束字符串，真正的收尾引号在其后")
    func tokenizeEscapedQuoteDoesNotTerminateString() {
        let text = #"["a\"b"]"#
        // 0[ 1" 2a 3\ 4" 5b 6" 7]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.string, 1, 6),
            tok(.punctuation, 7, 1)
        ]
        #expect(tokens == expected)
    }

    @Test("转义反斜杠 \\\\ 成对消耗后，紧随其后的引号是真正的收尾引号")
    func tokenizeEscapedBackslashPairDoesNotEscapeFollowingQuote() {
        let text = #"["a\\"]"#
        // 0[ 1" 2a 3\ 4\ 5" 6]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.string, 1, 5),
            tok(.punctuation, 6, 1)
        ]
        #expect(tokens == expected)
    }

    @Test("字面转义 \\n（反斜杠+n 两字符）不结束字符串，整体仍是单个 token")
    func tokenizeBackslashNEscapeWithinString() {
        let text = #"["line1\nline2"]"#
        // 0[ 1" 2l 3i 4n 5e 6:1 7\ 8n 9l 10i 11n 12e 13:2 14" 15]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.string, 1, 14),
            tok(.punctuation, 15, 1)
        ]
        #expect(tokens == expected)
    }

    @Test("\\uXXXX 转义序列整体属于同一个字符串 token，不被拆分")
    func tokenizeUnicodeEscapeSequenceStaysWithinSingleToken() {
        let text = "[\"a\\u0041b\"]"
        // 0[ 1" 2a 3\ 4u 5:0 6:0 7:4 8:1 9b 10" 11]

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.string, 1, 10),
            tok(.punctuation, 11, 1)
        ]
        #expect(tokens == expected)
    }

    // MARK: - 未闭合字符串（不崩溃降级）

    @Test("顶层未闭合字符串：延伸到文本末尾的单一 token，kind 为 .string 或 .key 二选一，不崩溃")
    func tokenizeUnterminatedStringAtTopLevelExtendsToEndOfText() throws {
        let text = "\"abc"
        // 0" 1a 2b 3c，无收尾引号

        let tokens = JSONHighlighter.tokenize(text)

        try #require(tokens.count == 1)
        let onlyToken = tokens[0]
        #expect(onlyToken.range == NSRange(location: 0, length: 4))
        #expect(onlyToken.kind == .string || onlyToken.kind == .key)
    }

    @Test("对象内未闭合的值字符串：前缀 token 正常产出，末尾字符串延伸到文本末尾不崩溃")
    func tokenizeUnterminatedStringAsObjectValueExtendsToEndOfText() throws {
        let text = "{\"a\": \"b"
        // 0{ 1" 2a 3" 4: 5(sp) 6" 7b，无收尾引号

        let tokens = JSONHighlighter.tokenize(text)

        try #require(tokens.count == 4)
        #expect(tokens[0] == tok(.punctuation, 0, 1))
        #expect(tokens[1] == tok(.key, 1, 3))
        #expect(tokens[2] == tok(.punctuation, 4, 1))
        #expect(tokens[3].range == NSRange(location: 6, length: 2))
        #expect(tokens[3].kind == .string || tokens[3].kind == .key)
    }

    // MARK: - UTF-16 代理对（补充平面字符）

    @Test("字符串值内含补充平面字符（emoji）时，range 长度按 UTF-16 代理对（2 units）计算")
    func tokenizeAstralPlaneCharacterUsesTwoUTF16UnitsInRange() {
        let text = #"{"e":"😀"}"#
        #expect((text as NSString).length == 10)
        // 0{ 1" 2e 3" 4: 5" 6-7:😀(2 units) 8" 9}

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.key, 1, 3),
            tok(.punctuation, 4, 1),
            tok(.string, 5, 4),
            tok(.punctuation, 9, 1)
        ]
        #expect(tokens == expected)
    }

    // MARK: - in: 子范围过滤

    @Test("子范围严格按 token 起点过滤：起点落在范围之前的 token 即便与范围重叠也被排除")
    func tokenizeSubRangeExcludesTokenStartingBeforeRangeEvenIfOverlapping() {
        let text = #"{"a":1,"b":2}"#
        // "b" key token 起点在 7，range 从 9 开始 → 即便 range 与该 token 的
        // [7,10) 区间重叠，仍不应回传该 token（起点 7 不在 [9,13) 内）。

        let tokens = JSONHighlighter.tokenize(text, in: NSRange(location: 9, length: 4))

        let expected: [Token] = [
            tok(.punctuation, 10, 1), // :
            tok(.number, 11, 1),      // 2
            tok(.punctuation, 12, 1)  // }
        ]
        #expect(tokens == expected)
    }

    @Test("省略 in: 参数（默认 nil）与显式传入覆盖全文的 range 结果一致")
    func tokenizeNilRangeDefaultsToFullTextEquivalentToExplicitFullRange() {
        let text = #"{"a":1}"#
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        let defaultResult = JSONHighlighter.tokenize(text)
        let explicitFullResult = JSONHighlighter.tokenize(text, in: fullRange)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.key, 1, 3),
            tok(.punctuation, 4, 1),
            tok(.number, 5, 1),
            tok(.punctuation, 6, 1)
        ]
        #expect(defaultResult == expected)
        #expect(defaultResult == explicitFullResult)
    }

    @Test("子范围仅覆盖空白区域时不回传任何 token")
    func tokenizeSubRangeCoveringOnlyWhitespaceReturnsEmptyArray() {
        let text = #" {"a":1} "#
        // 0(sp) 1{ ... 7} 8(sp)

        let tokens = JSONHighlighter.tokenize(text, in: NSRange(location: 0, length: 1))

        #expect(tokens == [])
    }

    // MARK: - JSONL：多行独立扫描

    @Test("JSONL 多行文本：逐行词法扫描产出连续 token 流，换行符跳过不产 token")
    func tokenizeJsonlMultipleLinesTokenizedSequentially() {
        let text = "{\"a\":1}\n{\"b\":2}\n"
        // 0{ 1" 2a 3" 4: 5:1 6} 7\n 8{ 9" 10b 11" 12: 13:2 14} 15\n

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),
            tok(.key, 1, 3),
            tok(.punctuation, 4, 1),
            tok(.number, 5, 1),
            tok(.punctuation, 6, 1),
            tok(.punctuation, 8, 1),
            tok(.key, 9, 3),
            tok(.punctuation, 12, 1),
            tok(.number, 13, 1),
            tok(.punctuation, 14, 1)
        ]
        #expect(tokens == expected)
    }
}
