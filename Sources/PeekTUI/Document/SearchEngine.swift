/// 搜索的对象：按行存的文本（纯文本、源码、XML、格式化后的 JSON），或排好版的 Markdown 行。
package enum SearchCorpus: Equatable, Sendable {
    case lines(LineStore)
    case markdown([MarkdownRow])

    /// 一共多少行（Markdown 为排版行）。
    var lineCount: Int {
        switch self {
        case let .lines(store): store.count
        case let .markdown(rows): rows.count
        }
    }
}

/// 一处匹配在屏幕上的位置：第 `line` 行的视觉列区间（展开制表符；Markdown 为排版行里含装饰的列）。
/// 文本与 JSON 的 `line` 是源行，Markdown 是排版行。Markdown 里跨软换行的一处匹配拆成每行一段，
/// 第二段起 `isContinuation` 为 true。
package struct SearchMatch: Equatable, Sendable {
    package var line: Int
    package var columns: Range<Int>
    package var isContinuation: Bool

    package init(line: Int, columns: Range<Int>, isContinuation: Bool = false) {
        self.line = line
        self.columns = columns
        self.isContinuation = isContinuation
    }
}

/// 纯函数：在文本里找搜索词。按 UTF-8 字节比较，英文字母不区分大小写；搜索词里的换行去掉。
package enum SearchEngine {
    /// 最多记这么多处匹配（按段计），之后的不再找。
    package static let maximumMatches = 100_000
    /// 分批搜索时每批的行数（Markdown 批尾延到下一段的开头，一段不拆到两批里）。
    static let linesPerChunk = 50_000

    /// 搜索词的字节：去掉换行，英文字母转小写。
    static func needle(_ query: String) -> [UInt8] {
        query.utf8.filter { $0 != 0x0A && $0 != 0x0D }.map(folded)
    }

    @inline(__always)
    static func folded(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte
    }

    /// 分批搜索的行区间，从头到尾。
    package static func chunks(of corpus: SearchCorpus) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < corpus.lineCount {
            var end = min(start + linesPerChunk, corpus.lineCount)
            if case let .markdown(rows) = corpus {
                while end < rows.count, rows[end].joinsPrevious != nil { end += 1 }
            }
            result.append(start..<end)
            start = end
        }
        return result
    }

    /// 整篇搜一遍（测试与小文件用；运行时按 `chunks` 分批调用 `matches(in:query:lines:)`）。
    package static func matches(in corpus: SearchCorpus, query: String) -> [SearchMatch] {
        var result: [SearchMatch] = []
        for chunk in chunks(of: corpus) {
            result += matches(in: corpus, query: query, lines: chunk, limit: maximumMatches - result.count)
            if result.count >= maximumMatches { break }
        }
        return result
    }

    /// 在 `lines` 这些行里搜，最多 `limit` 段。
    package static func matches(in corpus: SearchCorpus, query: String, lines: Range<Int>, limit: Int = maximumMatches) -> [SearchMatch] {
        let needle = needle(query)
        guard !needle.isEmpty, !lines.isEmpty, limit > 0 else { return [] }
        switch corpus {
        case let .lines(store):
            return lineMatches(store, needle: needle, lines: lines, limit: limit)
        case let .markdown(rows):
            return markdownMatches(rows, needle: needle, lines: lines, limit: limit)
        }
    }

    // MARK: - 按行存的文本

    private static func lineMatches(_ store: LineStore, needle: [UInt8], lines: Range<Int>, limit: Int) -> [SearchMatch] {
        var text = store.text
        text.makeContiguousUTF8()
        let start = store.utf8Range(ofLine: lines.lowerBound).lowerBound
        let end = store.utf8Range(ofLine: lines.upperBound - 1).upperBound
        return text.utf8.withContiguousStorageIfAvailable { bytes -> [SearchMatch] in
            var result: [SearchMatch] = []
            // 同一行里接着上一处匹配往后算列，不从行首重算
            var line = -1
            var measuredByte = 0
            var measuredColumn = 0
            for offset in occurrences(of: needle, in: bytes, range: start..<end, limit: limit) {
                let matchLine = store.line(containingUTF8Offset: offset)
                if matchLine != line {
                    line = matchLine
                    measuredByte = store.utf8Range(ofLine: matchLine).lowerBound
                    measuredColumn = 0
                }
                let startColumn = VisualColumns.column(after: decode(bytes, measuredByte..<offset), from: measuredColumn)
                let endColumn = VisualColumns.column(after: decode(bytes, offset..<(offset + needle.count)), from: startColumn)
                result.append(SearchMatch(line: matchLine, columns: startColumn..<endColumn))
                measuredByte = offset + needle.count
                measuredColumn = endColumn
            }
            return result
        } ?? []
    }

    private static func decode(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
    }

    /// `range` 里搜索词出现的起点，从前往后、互不重叠，最多 `limit` 处。
    private static func occurrences(of needle: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, range: Range<Int>, limit: Int) -> [Int] {
        var result: [Int] = []
        guard let first = needle.first else { return result }
        var index = range.lowerBound
        let last = range.upperBound - needle.count
        while index <= last, result.count < limit {
            if folded(bytes[index]) == first {
                var matched = 1
                while matched < needle.count, folded(bytes[index + matched]) == needle[matched] { matched += 1 }
                if matched == needle.count {
                    result.append(index)
                    index += needle.count
                    continue
                }
            }
            index += 1
        }
        return result
    }

    // MARK: - Markdown 排版行

    /// 排版行里可搜索的字：装饰不算；替换了复制文字的片段（表格竖线）按复制文字搜，位置是整个片段。
    private struct Glyph {
        let row: Int
        let columns: Range<Int>
    }

    /// 一段（行首行加上它的软换行续行）的文字与每个字节对应的位置；续行接回处的字没有位置。
    private static func paragraph(_ rows: [MarkdownRow], from first: Int, through last: Int) -> (bytes: [UInt8], glyphs: [Glyph?]) {
        var bytes: [UInt8] = []
        var glyphs: [Glyph?] = []
        for index in first...last {
            let row = rows[index]
            if index > first, let join = row.joinsPrevious {
                bytes += join.utf8
                glyphs += Array(repeating: nil, count: join.utf8.count)
            }
            var column = 0
            for span in row.spans {
                let width = TextWidth.width(of: span.text)
                defer { column += width }
                if let copyText = span.copyText {
                    let glyph = Glyph(row: index, columns: column..<(column + max(width, 1)))
                    bytes += copyText.utf8
                    glyphs += Array(repeating: glyph, count: copyText.utf8.count)
                    continue
                }
                var characterColumn = column
                for character in span.text {
                    let characterWidth = TextWidth.width(of: character)
                    let glyph = Glyph(row: index, columns: characterColumn..<(characterColumn + characterWidth))
                    let utf8 = String(character).utf8
                    bytes += utf8
                    glyphs += Array(repeating: glyph, count: utf8.count)
                    characterColumn += characterWidth
                }
            }
        }
        return (bytes, glyphs)
    }

    private static func markdownMatches(_ rows: [MarkdownRow], needle: [UInt8], lines: Range<Int>, limit: Int) -> [SearchMatch] {
        var result: [SearchMatch] = []
        var first = lines.lowerBound
        while first < lines.upperBound, result.count < limit {
            var last = first
            while last + 1 < rows.count, rows[last + 1].joinsPrevious != nil { last += 1 }
            let paragraph = paragraph(rows, from: first, through: last)
            paragraph.bytes.withUnsafeBufferPointer { bytes in
                for offset in occurrences(of: needle, in: bytes, range: 0..<bytes.count, limit: limit - result.count) {
                    result += segments(of: paragraph.glyphs[offset..<(offset + needle.count)])
                }
            }
            first = last + 1
        }
        return Array(result.prefix(limit))
    }

    /// 一处匹配覆盖的字按行合成每行一段。
    private static func segments(of glyphs: ArraySlice<Glyph?>) -> [SearchMatch] {
        var result: [SearchMatch] = []
        for glyph in glyphs.compactMap({ $0 }) {
            if let previous = result.last, previous.line == glyph.row {
                result[result.count - 1].columns = min(previous.columns.lowerBound, glyph.columns.lowerBound)..<max(previous.columns.upperBound, glyph.columns.upperBound)
            } else {
                result.append(SearchMatch(line: glyph.row, columns: glyph.columns, isContinuation: !result.isEmpty))
            }
        }
        return result
    }
}
