import Foundation

/// app 窗口里 ⌘F 查找的纯函数核心：找匹配、决定从哪一个开始、前后跳、可见区筛选、计数文案。
///
/// 区间一律按 UTF-16 计：代码视图的 NSTextView 与 Markdown 页面里的 JS 字符串都用这套下标，
/// 同一份结果两边都能直接用。
package enum TextSearch {
    /// 最多记这么多处匹配，之后的不再找（与终端版 `SearchEngine.maximumMatches` 一致）。
    package static let maximumMatches = 100_000

    package struct Result: Equatable, Sendable {
        /// 升序、互不重叠。
        package var ranges: [NSRange]
        /// 匹配数超过上限、后面的没再找。
        package var isTruncated: Bool

        package init(ranges: [NSRange], isTruncated: Bool) {
            self.ranges = ranges
            self.isTruncated = isTruncated
        }

        package static let empty = Result(ranges: [], isTruncated: false)
    }

    /// 在 `text` 里找 `query`：不分大小写，其余字符按字面匹配；搜索词里的一段空白（含换行）
    /// 匹配正文里任意一段空白——Markdown 的软换行在页面上显示成空格，用户照着屏幕打的空格要能搜到。
    /// `isCancelled` 在后台搜大文件时用来提前收工（返回已找到的部分）。
    package static func matches(
        of query: String,
        in text: String,
        limit: Int = maximumMatches,
        isCancelled: () -> Bool = { false }
    ) -> Result {
        guard let regex = pattern(for: query), limit > 0 else { return .empty }

        let nsText = text as NSString
        var ranges: [NSRange] = []
        var isTruncated = false
        regex.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) { match, _, stop in
            guard let match else { return }
            if ranges.count == limit {
                isTruncated = true
                stop.pointee = true
                return
            }
            ranges.append(match.range)
            if ranges.count % 1024 == 0, isCancelled() {
                stop.pointee = true
            }
        }
        return Result(ranges: ranges, isTruncated: isTruncated)
    }

    /// 搜索词 → 正则：连续空白变成 `\s+`，其余逐段转义成字面量。空搜索词为 nil。
    static func pattern(for query: String) -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }

        var pattern = ""
        var literal = ""
        var inWhitespace = false
        for character in query {
            if character.isWhitespace {
                if !inWhitespace {
                    pattern += NSRegularExpression.escapedPattern(for: literal) + "\\s+"
                    literal = ""
                    inWhitespace = true
                }
            } else {
                literal.append(character)
                inWhitespace = false
            }
        }
        pattern += NSRegularExpression.escapedPattern(for: literal)
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// 起点不早于 `anchor` 的第一个匹配；`anchor` 之后没有就回到第一个。没有匹配为 nil。
    package static func firstIndex(atOrAfter anchor: Int, in ranges: [NSRange]) -> Int? {
        guard !ranges.isEmpty else { return nil }
        let index = partitionPoint(ranges) { $0.location >= anchor }
        return index < ranges.count ? index : 0
    }

    /// 下一个 / 上一个，首尾相接。
    package static func step(from index: Int, count: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        let next = forward ? index + 1 : index - 1
        return (next % count + count) % count
    }

    /// 与 `range` 相交的匹配下标区间（`ranges` 升序且互不重叠，起点与终点都单调）。
    package static func indices(intersecting range: NSRange, in ranges: [NSRange]) -> Range<Int> {
        let lower = partitionPoint(ranges) { NSMaxRange($0) > range.location }
        let upper = partitionPoint(ranges) { $0.location >= NSMaxRange(range) }
        return lower..<max(lower, upper)
    }

    /// 查找栏里的计数：搜索词为空时不显示；没有匹配「No matches」；否则「3 of 12」，截断时「3 of 12+」。
    package static func countText(query: String, currentIndex: Int?, result: Result) -> String {
        guard !query.isEmpty else { return "" }
        guard !result.ranges.isEmpty else { return "No matches" }
        let total = "\(result.ranges.count)\(result.isTruncated ? "+" : "")"
        guard let currentIndex else { return "\(total) matches" }
        return "\(currentIndex + 1) of \(total)"
    }

    /// 第一个满足 `predicate` 的下标（`predicate` 在数组上先假后真）；都不满足为 `count`。
    private static func partitionPoint(_ ranges: [NSRange], where predicate: (NSRange) -> Bool) -> Int {
        var low = 0
        var high = ranges.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(ranges[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
