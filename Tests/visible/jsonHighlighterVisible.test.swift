import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONHighlighter 可见样例
//
// 覆盖三条主干契约：pretty-print 对象的 key/string/punctuation 单遍分词、
// 数组内 number/boolLiteral/nullLiteral 与空白跳过、以及 `in:` 子范围
// 参数只回传"起点落在范围内"的 token。
//
// 所有 range 断言均为 UTF-16 偏移（与 NSString/NSAttributedString 一致），
// 手工核对每个 fixture 的字符位置。JSONToken 已声明 Equatable，可直接用
// `==` 比对整个 token 数组，stub 阶段返回空数组时比较不会 crash，只会
// 断言失败呈红。

private typealias Token = JSONHighlighter.JSONToken
private typealias Kind = JSONHighlighter.JSONTokenKind

private func tok(_ kind: Kind, _ location: Int, _ length: Int) -> Token {
    Token(kind: kind, range: NSRange(location: location, length: length))
}

@Suite("Visible_jsonHighlighter")
struct Visible_jsonHighlighter {
    @Test("pretty-print 对象：key 紧跟冒号判定为 .key，值字符串跳过换行后遇 } 判定为 .string")
    func tokenizePrettyPrintedObjectHappyPath() {
        // {\n  "name": "Peeky"\n}
        let text = "{\n  \"name\": \"Peeky\"\n}"

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),   // {
            tok(.key, 4, 6),           // "name"
            tok(.punctuation, 10, 1),  // :
            tok(.string, 12, 7),       // "Peeky"
            tok(.punctuation, 20, 1)   // }
        ]
        #expect(tokens == expected)
    }

    @Test("数组：number/boolLiteral/nullLiteral 各归位，逗号间空白被跳过不产 token")
    func tokenizeArrayWithNumberBoolNullLiterals() {
        let text = "[1, true, false, null]"

        let tokens = JSONHighlighter.tokenize(text)

        let expected: [Token] = [
            tok(.punctuation, 0, 1),   // [
            tok(.number, 1, 1),        // 1
            tok(.punctuation, 2, 1),   // ,
            tok(.boolLiteral, 4, 4),   // true
            tok(.punctuation, 8, 1),   // ,
            tok(.boolLiteral, 10, 5),  // false
            tok(.punctuation, 15, 1),  // ,
            tok(.nullLiteral, 17, 4),  // null
            tok(.punctuation, 21, 1)   // ]
        ]
        #expect(tokens == expected)
    }

    @Test("in: 子范围参数只回传起点落在该范围内的 token")
    func tokenizeSubRangeReturnsOnlyTokensStartingWithinRange() {
        let text = #"{"a":1,"b":2}"#
        // indices: 0{ 1" 2a 3" 4: 5:1 6, 7" 8b 9" 10: 11:2 12}

        let tokens = JSONHighlighter.tokenize(text, in: NSRange(location: 7, length: 6))

        let expected: [Token] = [
            tok(.key, 7, 3),          // "b"
            tok(.punctuation, 10, 1), // :
            tok(.number, 11, 1),      // 2
            tok(.punctuation, 12, 1)  // }
        ]
        #expect(tokens == expected)
    }
}
