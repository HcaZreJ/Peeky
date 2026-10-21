/// 按行存的文本：只存全文与每行起点（UTF-8 偏移），取行时才切片，几百万行的大文件也不按行建字符串。
///
/// 结尾的换行不再多出一个空行；`\r\n` 取行时去掉 `\r`；空文本是一行空行。
package struct LineStore: Equatable, Sendable {
    package let text: String
    private let starts: [Int]
    private let endOffset: Int

    package init(_ text: String) {
        self.text = text
        var starts = [0]
        var count = 0
        text.utf8.withContiguousStorageIfAvailable { bytes in
            count = bytes.count
            for index in 0..<bytes.count where bytes[index] == 0x0A {
                starts.append(index + 1)
            }
        } ?? {
            for (index, byte) in text.utf8.enumerated() {
                count = index + 1
                if byte == 0x0A { starts.append(index + 1) }
            }
        }()
        if starts.count > 1, starts.last == count {
            starts.removeLast()
        }
        self.starts = starts
        self.endOffset = count
    }

    package var count: Int { starts.count }

    /// 第 `index` 行起点在全文里的 UTF-16 偏移（与 NSString / NSRange 的坐标一致）。
    package func utf16Offset(ofLine index: Int) -> Int {
        guard index > 0 else { return 0 }
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: starts[min(index, starts.count - 1)])
        return text.utf16.distance(from: text.utf16.startIndex, to: start)
    }

    /// 第 `index` 行（0 起算），不含行尾换行。越界返回空串。
    package func line(_ index: Int) -> String {
        guard index >= 0, index < starts.count else { return "" }
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: starts[index])
        let endOffsetForLine = index + 1 < starts.count ? starts[index + 1] - 1 : endOffset
        var end = utf8.index(utf8.startIndex, offsetBy: max(endOffsetForLine, starts[index]))
        if end > start, index + 1 == starts.count, utf8[utf8.index(before: end)] == 0x0A {
            end = utf8.index(before: end)
        }
        if end > start, utf8[utf8.index(before: end)] == 0x0D {
            end = utf8.index(before: end)
        }
        return String(text[start..<end])
    }
}
