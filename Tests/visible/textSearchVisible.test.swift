import Testing
import Foundation
@testable import PeekyKit
@testable import PeekyCore

@Suite("Visible_textSearch")
struct Visible_textSearch {

    @Test("不分大小写找出全部匹配，区间按 UTF-16 计（与 NSString / JS 字符串下标一致）")
    func test_textSearch_findsAllMatchesCaseInsensitively() {
        let text = "先回答：孤儿药 (Orphan Drug)。🙂孤儿药认定；orphan drug 与 ORPHAN DRUG。"
        let chinese = TextSearch.matches(of: "孤儿药", in: text)
        let nsText = text as NSString
        #expect(chinese.ranges == [nsText.range(of: "孤儿药"), nsText.range(of: "孤儿药", options: .backwards)])
        #expect(chinese.ranges.map { nsText.substring(with: $0) } == ["孤儿药", "孤儿药"])
        #expect(chinese.isTruncated == false)

        let english = TextSearch.matches(of: "orphan drug", in: text)
        #expect(english.ranges.map { nsText.substring(with: $0) } == ["Orphan Drug", "orphan drug", "ORPHAN DRUG"])
    }

    @Test("搜索词里的空白匹配正文任意一段空白：Markdown 软换行在页面上显示成空格，照样搜得到")
    func test_textSearch_whitespaceInQueryMatchesAnyWhitespaceRun() {
        let text = "rare disease\nmedicine; rare   disease medicine; rare\tdisease; raredisease"
        let nsText = text as NSString
        let result = TextSearch.matches(of: "rare disease", in: text)
        #expect(result.ranges.map { nsText.substring(with: $0) } == ["rare disease", "rare   disease", "rare\tdisease"])
        #expect(TextSearch.matches(of: "disease medicine", in: text).ranges.count == 2)
    }

    @Test("正则特殊字符按字面匹配；空搜索词没有匹配")
    func test_textSearch_specialCharactersAreLiteral() {
        let text = "call a.b(x) then axb(x) and a.b(y)"
        let nsText = text as NSString
        let result = TextSearch.matches(of: "a.b(", in: text)
        #expect(result.ranges.map { nsText.substring(with: $0) } == ["a.b(", "a.b("])
        #expect(TextSearch.matches(of: "", in: text).ranges.isEmpty)
        #expect(TextSearch.matches(of: "[*]", in: "x [*] y").ranges == [NSRange(location: 2, length: 3)])
    }

    @Test("超过上限就停，标记截断；恰好等于上限不算截断")
    func test_textSearch_stopsAtLimitAndMarksTruncation() {
        let text = String(repeating: "ab ", count: 10)
        let truncated = TextSearch.matches(of: "ab", in: text, limit: 4)
        #expect(truncated.ranges.count == 4)
        #expect(truncated.isTruncated == true)

        let exact = TextSearch.matches(of: "ab", in: String(repeating: "ab ", count: 4), limit: 4)
        #expect(exact.ranges.count == 4)
        #expect(exact.isTruncated == false)
    }

    @Test("从某个位置起找第一个匹配：起点在它之后的第一个，后面没有就回到第一个；没有匹配为 nil")
    func test_textSearch_firstIndexAtOrAfterAnchorWraps() {
        let ranges = [NSRange(location: 10, length: 3), NSRange(location: 50, length: 3), NSRange(location: 90, length: 3)]
        #expect(TextSearch.firstIndex(atOrAfter: 0, in: ranges) == 0)
        #expect(TextSearch.firstIndex(atOrAfter: 10, in: ranges) == 0)
        #expect(TextSearch.firstIndex(atOrAfter: 11, in: ranges) == 1)
        #expect(TextSearch.firstIndex(atOrAfter: 60, in: ranges) == 2)
        #expect(TextSearch.firstIndex(atOrAfter: 91, in: ranges) == 0)
        #expect(TextSearch.firstIndex(atOrAfter: 5, in: []) == nil)
    }

    @Test("下一个 / 上一个首尾循环")
    func test_textSearch_stepWrapsAround() {
        #expect(TextSearch.step(from: 0, count: 3, forward: true) == 1)
        #expect(TextSearch.step(from: 2, count: 3, forward: true) == 0)
        #expect(TextSearch.step(from: 0, count: 3, forward: false) == 2)
        #expect(TextSearch.step(from: 1, count: 3, forward: false) == 0)
        #expect(TextSearch.step(from: 0, count: 1, forward: true) == 0)
    }

    @Test("只挑出与可见区相交的匹配（代码视图只画屏幕上的那几个）")
    func test_textSearch_indicesIntersectingVisibleRange() {
        let ranges = (0..<10).map { NSRange(location: $0 * 10, length: 4) }
        #expect(TextSearch.indices(intersecting: NSRange(location: 22, length: 20), in: ranges) == 2..<5)
        #expect(TextSearch.indices(intersecting: NSRange(location: 25, length: 5), in: ranges) == 3..<3)
        #expect(TextSearch.indices(intersecting: NSRange(location: 0, length: 1000), in: ranges) == 0..<10)
        #expect(TextSearch.indices(intersecting: NSRange(location: 33, length: 1), in: ranges) == 3..<4)
        #expect(TextSearch.indices(intersecting: NSRange(location: 5, length: 5), in: []) == 0..<0)
    }

    @Test("计数文案：空词不显示、无结果、第几个共几个、截断时加 +")
    func test_textSearch_countText() {
        let three = TextSearch.Result(ranges: Array(repeating: NSRange(location: 0, length: 1), count: 12), isTruncated: false)
        #expect(TextSearch.countText(query: "", currentIndex: nil, result: TextSearch.Result(ranges: [], isTruncated: false)) == "")
        #expect(TextSearch.countText(query: "孤儿药", currentIndex: nil, result: TextSearch.Result(ranges: [], isTruncated: false)) == "No matches")
        #expect(TextSearch.countText(query: "孤儿药", currentIndex: 2, result: three) == "3 of 12")
        let truncated = TextSearch.Result(ranges: three.ranges, isTruncated: true)
        #expect(TextSearch.countText(query: "a", currentIndex: 0, result: truncated) == "1 of 12+")
    }
}
