/// 正文按词折行：西文在空格处断，CJK（宽字符）在任意两个字之间可断，
/// 收尾标点不落在行首（回退一个字一起换行），超过一整行的长词硬断，换行处的空格不带到下一行。
package enum WrapEngine {
    /// 不能出现在行首的收尾标点。
    static let closingPunctuation: Set<Character> = [
        "，", "。", "、", "；", "：", "？", "！", "）", "」", "』", "】", "》", "〉", "…", "—", "～", "％",
        ",", ".", ";", ":", "?", "!", ")", "]", "}",
    ]

    private struct Unit {
        var pieces: [StyledSpan]
        var width: Int
        var isSpace: Bool
        var isClosingPunctuation: Bool
    }

    package static func wrap(_ spans: [StyledSpan], width: Int) -> [[StyledSpan]] {
        guard width > 0 else { return [spans] }
        var lines: [[Unit]] = []
        var current: [Unit] = []
        var used = 0

        func flush() {
            while let last = current.last, last.isSpace {
                current.removeLast()
            }
            lines.append(current)
            current = []
            used = 0
        }

        for unit in units(of: spans) {
            if unit.isSpace {
                if current.isEmpty { continue }
                if used + unit.width > width {
                    flush()
                    continue
                }
                current.append(unit)
                used += unit.width
                continue
            }
            if used + unit.width <= width {
                current.append(unit)
                used += unit.width
                continue
            }
            if unit.isClosingPunctuation, let carried = carriedUnits(from: current, adding: unit, width: width) {
                current.removeLast(carried.count)
                flush()
                current = carried + [unit]
                used = current.reduce(0) { $0 + $1.width }
                continue
            }
            if !current.isEmpty {
                flush()
            }
            if unit.width <= width {
                current = [unit]
                used = unit.width
                continue
            }
            for piece in hardSplit(unit, width: width) {
                if used + piece.width > width {
                    flush()
                }
                current.append(piece)
                used += piece.width
            }
        }
        if !current.isEmpty || lines.isEmpty {
            flush()
        }
        return lines.map(merge)
    }

    /// 收尾标点放不下时要一起带到下一行的行尾单位：行尾连着的收尾标点（如「）」之后再来「。」），
    /// 再加它们前面的一个字或词。带走后这一行会空、前面是空格、或带走的放不进一行时为 nil。
    private static func carriedUnits(from current: [Unit], adding unit: Unit, width: Int) -> [Unit]? {
        var count = 0
        while count < current.count, current[current.count - 1 - count].isClosingPunctuation {
            count += 1
        }
        guard count < current.count, !current[current.count - 1 - count].isSpace else { return nil }
        count += 1
        guard count < current.count else { return nil }
        let carried = Array(current.suffix(count))
        guard carried.reduce(unit.width, { $0 + $1.width }) <= width else { return nil }
        return carried
    }

    /// 切成可断开的单位：一个空格、一个 CJK 字、或一串连续的西文字符（可跨样式片段）。
    private static func units(of spans: [StyledSpan]) -> [Unit] {
        var result: [Unit] = []
        var word: Unit?

        func endWord() {
            if let finished = word {
                result.append(finished)
                word = nil
            }
        }

        for span in spans {
            for character in span.text {
                let characterWidth = TextWidth.width(of: character)
                let piece = span.with(text: String(character))
                if character == " " {
                    endWord()
                    result.append(Unit(pieces: [piece], width: characterWidth, isSpace: true, isClosingPunctuation: false))
                } else if characterWidth == 2 {
                    endWord()
                    result.append(Unit(pieces: [piece], width: characterWidth, isSpace: false, isClosingPunctuation: closingPunctuation.contains(character)))
                } else {
                    if word == nil {
                        word = Unit(pieces: [], width: 0, isSpace: false, isClosingPunctuation: false)
                    }
                    word?.pieces.append(piece)
                    word?.width += characterWidth
                }
            }
        }
        endWord()
        return result
    }

    /// 超过一整行的西文词按字符切成每段不超过 `width` 的块。
    private static func hardSplit(_ unit: Unit, width: Int) -> [Unit] {
        var pieces: [Unit] = []
        var current = Unit(pieces: [], width: 0, isSpace: false, isClosingPunctuation: false)
        for piece in unit.pieces {
            let pieceWidth = TextWidth.width(of: piece.text)
            if current.width + pieceWidth > width, current.width > 0 {
                pieces.append(current)
                current = Unit(pieces: [], width: 0, isSpace: false, isClosingPunctuation: false)
            }
            current.pieces.append(piece)
            current.width += pieceWidth
        }
        if current.width > 0 {
            pieces.append(current)
        }
        return pieces
    }

    /// 相邻同样式的单字片段合并回一段。
    private static func merge(_ units: [Unit]) -> [StyledSpan] {
        var spans: [StyledSpan] = []
        for piece in units.flatMap(\.pieces) {
            if let last = spans.last, last.style == piece.style, last.target == piece.target {
                spans[spans.count - 1].text += piece.text
            } else {
                spans.append(piece)
            }
        }
        return spans
    }
}
