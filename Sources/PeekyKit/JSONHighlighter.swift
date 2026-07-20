import Foundation

/// 原生 JSON 词法分色器：单遍扫描 pretty-print 后的 JSON/JSONL 文本，产出
/// token 类型 + range（不含颜色，颜色由 `PeekyTheme` 按 kind 映射，解耦）。
///
/// 支持按子范围 tokenize，服务 viewport-only 惰性上色（只对屏幕可见区上色）。
enum JSONHighlighter {
    enum JSONTokenKind {
        case key
        case string
        case number
        case boolLiteral
        case nullLiteral
        case punctuation
    }

    struct JSONToken: Equatable {
        let kind: JSONTokenKind
        let range: NSRange

        init(kind: JSONTokenKind, range: NSRange) {
            self.kind = kind
            self.range = range
        }
    }

    static func tokenize(_ text: String, in range: NSRange? = nil) -> [JSONToken] {
        let nsText = text as NSString
        let length = nsText.length
        var tokens: [JSONToken] = []
        var i = 0

        while i < length {
            let c = nsText.character(at: i)

            switch c {
            case 32, 9, 10, 13:
                i += 1

            case 34:
                let start = i
                var j = start + 1
                while j < length {
                    let ch = nsText.character(at: j)
                    if ch == 92 {
                        j = j + 1 < length ? j + 2 : length
                        continue
                    }
                    if ch == 34 {
                        j += 1
                        break
                    }
                    j += 1
                }
                let kind: JSONTokenKind = isKeyFollowing(nsText, after: j) ? .key : .string
                tokens.append(JSONToken(kind: kind, range: NSRange(location: start, length: j - start)))
                i = j

            case 123, 125, 91, 93, 44, 58:
                tokens.append(JSONToken(kind: .punctuation, range: NSRange(location: i, length: 1)))
                i += 1

            case 45, 48...57:
                if c == 45, !(i + 1 < length && isDigit(nsText.character(at: i + 1))) {
                    i += 1
                    continue
                }

                let start = i
                if c == 45 { i += 1 }
                while i < length, isDigit(nsText.character(at: i)) { i += 1 }

                if i < length, nsText.character(at: i) == 46 {
                    i += 1
                    while i < length, isDigit(nsText.character(at: i)) { i += 1 }
                }

                if i < length, nsText.character(at: i) == 101 || nsText.character(at: i) == 69 {
                    let expStart = i
                    i += 1
                    if i < length, nsText.character(at: i) == 43 || nsText.character(at: i) == 45 {
                        i += 1
                    }
                    if i < length, isDigit(nsText.character(at: i)) {
                        while i < length, isDigit(nsText.character(at: i)) { i += 1 }
                    } else {
                        i = expStart
                    }
                }

                tokens.append(JSONToken(kind: .number, range: NSRange(location: start, length: i - start)))

            case 116:
                if matchesKeyword(trueKeyword, at: i, in: nsText) {
                    tokens.append(JSONToken(kind: .boolLiteral, range: NSRange(location: i, length: trueKeyword.count)))
                    i += trueKeyword.count
                } else {
                    i += 1
                }

            case 102:
                if matchesKeyword(falseKeyword, at: i, in: nsText) {
                    tokens.append(JSONToken(kind: .boolLiteral, range: NSRange(location: i, length: falseKeyword.count)))
                    i += falseKeyword.count
                } else {
                    i += 1
                }

            case 110:
                if matchesKeyword(nullKeyword, at: i, in: nsText) {
                    tokens.append(JSONToken(kind: .nullLiteral, range: NSRange(location: i, length: nullKeyword.count)))
                    i += nullKeyword.count
                } else {
                    i += 1
                }

            default:
                i += 1
            }
        }

        guard let range else { return tokens }
        let lowerBound = range.location
        let upperBound = range.location + range.length
        return tokens.filter { $0.range.location >= lowerBound && $0.range.location < upperBound }
    }

    private static let trueKeyword: [unichar] = Array("true".utf16)
    private static let falseKeyword: [unichar] = Array("false".utf16)
    private static let nullKeyword: [unichar] = Array("null".utf16)

    private static func isDigit(_ c: unichar) -> Bool {
        c >= 48 && c <= 57
    }

    private static func isIdentifierContinuation(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    }

    private static func matchesKeyword(_ keyword: [unichar], at index: Int, in nsText: NSString) -> Bool {
        let length = nsText.length
        guard index + keyword.count <= length else { return false }

        for offset in 0..<keyword.count where nsText.character(at: index + offset) != keyword[offset] {
            return false
        }

        if index + keyword.count < length, isIdentifierContinuation(nsText.character(at: index + keyword.count)) {
            return false
        }

        return true
    }

    private static func isKeyFollowing(_ nsText: NSString, after index: Int) -> Bool {
        let length = nsText.length
        var k = index
        while k < length {
            let ch = nsText.character(at: k)
            if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
                k += 1
                continue
            }
            return ch == 58
        }
        return false
    }
}
