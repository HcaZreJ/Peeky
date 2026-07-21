import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONFoldComposer：可见样例
//
// 折叠一个跨多行的 array/object 区域 = 把其 innerCharRange 整体替换为单个
// U+FFFC 占位符。以下用一个 `{ "list": [ 1 ] }` 结构（`list` 数组跨 3 行）
// 验证：恒等态（collapsed 为空）、单区折叠后的可见文本/行映射/segments，
// 以及 sourceRange/visibleRange 两个坐标转换 API 在折叠态下的主干行为。
// 全部 range 均为 UTF-16 单位；样例的偏移量已逐字符手工核对：
//
//   0: {                    (len 1)
//   1:   "list": [          (len 11，"[" 在该行偏移 10，全局偏移 12)
//   2:     1                (len 5)
//   3:   ]                  (len 3，"]" 在该行偏移 2，全局偏移 22)
//   4: }                    (len 1)
//
// 源文本总长 25；list 区域 innerCharRange = (13, 9)（"[" 之后到 "]" 之前）。

private typealias Segment = FoldComposition.Segment

private let sampleLines = [
    "{",
    "  \"list\": [",
    "    1",
    "  ]",
    "}"
]
private let sampleSource = sampleLines.joined(separator: "\n")
private let sampleLineDepths = [0, 1, 2, 1, 0]
private let sampleListRegion = FoldRegion(
    openLine: 1,
    closeLine: 3,
    innerCharRange: NSRange(location: 13, length: 9),
    kind: .array
)
private let sampleFoldMap = JSONFoldMap(regions: [sampleListRegion], lineDepths: sampleLineDepths)

@Suite("Visible_jsonFoldComposer")
struct Visible_jsonFoldComposer {
    @Test("collapsed 为空：可见文本与源文本恒等，行映射/深度直接复用 foldMap，segments 为单一恒等段")
    func test_jsonFoldComposer_composeIdentityWhenCollapsedEmpty() {
        let result = JSONFoldComposer.compose(sourceText: sampleSource, foldMap: sampleFoldMap, collapsed: [])

        #expect(result.visibleText == sampleSource)
        #expect(result.chipRanges.isEmpty)
        #expect(result.visibleLineToSourceLine == [0, 1, 2, 3, 4])
        #expect(result.visibleLineDepths == sampleLineDepths)
        #expect(result.segments == [
            Segment(
                visibleRange: NSRange(location: 0, length: 25),
                sourceRange: NSRange(location: 0, length: 25)
            )
        ])
    }

    @Test("折叠 list 区域：inner 内容替换为单个 U+FFFC，行映射跳号，segments 为 恒等+chip+恒等 三段")
    func test_jsonFoldComposer_composeSingleRegionReplacesInnerWithChip() {
        let result = JSONFoldComposer.compose(sourceText: sampleSource, foldMap: sampleFoldMap, collapsed: [1])

        #expect(result.visibleText == "{\n  \"list\": [\u{FFFC}]\n}")
        #expect(result.chipRanges == [NSRange(location: 13, length: 1)])
        #expect(result.visibleLineToSourceLine == [0, 1, 4])
        #expect(result.visibleLineDepths == [0, 1, 0])
        #expect(result.segments == [
            Segment(visibleRange: NSRange(location: 0, length: 13), sourceRange: NSRange(location: 0, length: 13)),
            Segment(visibleRange: NSRange(location: 13, length: 1), sourceRange: NSRange(location: 13, length: 9)),
            Segment(visibleRange: NSRange(location: 14, length: 3), sourceRange: NSRange(location: 22, length: 3))
        ])
    }

    @Test("折叠态下：选中 chip 得到完整底层 JSON 源范围；源范围完全落在折叠内容中则收敛为该 chip 的可见范围")
    func test_jsonFoldComposer_sourceAndVisibleRangeRoundTripThroughFoldedChip() throws {
        let composition = JSONFoldComposer.compose(sourceText: sampleSource, foldMap: sampleFoldMap, collapsed: [1])

        let sourceOfChip = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 13, length: 1), in: composition)
        #expect(sourceOfChip == NSRange(location: 13, length: 9))

        let visibleOfInnerContent = try #require(
            JSONFoldComposer.visibleRange(forSource: NSRange(location: 15, length: 2), in: composition)
        )
        #expect(visibleOfInnerContent == NSRange(location: 13, length: 1))
    }
}
