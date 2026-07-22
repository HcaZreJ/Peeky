import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONFoldComposer 全面用例
//
// 覆盖 compose(sourceText:foldMap:collapsed:) / sourceRange(forVisible:in:) /
// visibleRange(forSource:in:) 的完整契约：
// - 恒等态（collapsed 为空 / 全部 id 不存在 / foldMap 为 .empty）。
// - 单区折叠：inner 替换为单个 U+FFFC、行映射跳号、segments 三段。
// - 嵌套折叠：外层折叠吞并内层（无论内层 id 是否也在 collapsed 中）；
//   仅内层折叠时外层照常展开。
// - 多个互不嵌套区域独立折叠：chipRanges 升序、长度恒 1。
// - segments 通用不变量：升序、互不重叠、联合覆盖全部可见文本。
// - chip 段 sourceRange 恒等于对应区域的 innerCharRange。
// - UTF-16 / 补充平面字符（emoji）坐标精确性。
// - 边界：空源文本 + 匹配的空 foldMap。
// - sourceRange(forVisible:) 与 visibleRange(forSource:) 的恒等段平移、
//   跨段并、chip 展开/收敛、零长度光标、越界 nil。
//
// 期望值来自两条独立路径：(a) `expectedComposition` oracle——只用
// NSString 子串拼接 + 逐行步进模拟折叠规则，与被测 compose() 实现完全
// 解耦；(b) 对 sourceRange/visibleRange 的针对性用例，基于 (a) 产出的
// composition 手工推导（每个偏移量均逐字符核对，见各 fixture 注释）。
// stub 阶段 compose() 返回恒等值、sourceRange/visibleRange 原样透传，
// 因此下列用例在 stub 下应全部因行映射/segments/chipRanges 或具体偏移量
// 不符而失败。

private typealias Segment = FoldComposition.Segment

private func bracketColumn(_ line: String, _ bracket: String) -> Int {
    (line as NSString).range(of: bracket).location
}

private func lineStartOffsets(_ lines: [String]) -> [Int] {
    var starts: [Int] = []
    var acc = 0
    for line in lines {
        starts.append(acc)
        acc += (line as NSString).length + 1
    }
    return starts
}

private func makeRegion(
    lines: [String],
    starts: [Int],
    openLine: Int,
    openBracket: String,
    closeLine: Int,
    closeBracket: String,
    kind: FoldRegion.Kind
) -> FoldRegion {
    let openCol = bracketColumn(lines[openLine], openBracket)
    let closeCol = bracketColumn(lines[closeLine], closeBracket)
    let start = starts[openLine] + openCol + 1
    let end = starts[closeLine] + closeCol
    return FoldRegion(
        openLine: openLine,
        closeLine: closeLine,
        innerCharRange: NSRange(location: start, length: end - start),
        kind: kind
    )
}

/// 独立 oracle：给定「解析嵌套吞并后生效的顶层折叠区域集合」，机械拼接
/// 可见文本 / chipRanges / 行映射 / segments。只用 NSString 子串与逐行
/// 步进，不调用被测 compose()。
private func expectedComposition(
    source: String,
    sourceLineDepths: [Int],
    foldedRegions: [FoldRegion]
) -> FoldComposition {
    let ns = source as NSString
    let byLocation = foldedRegions.sorted { $0.innerCharRange.location < $1.innerCharRange.location }

    var text = ""
    var chips: [NSRange] = []
    var segments: [Segment] = []
    var sourceCursor = 0

    for regionItem in byLocation {
        let idLen = regionItem.innerCharRange.location - sourceCursor
        if idLen > 0 {
            let visibleStart = (text as NSString).length
            text += ns.substring(with: NSRange(location: sourceCursor, length: idLen))
            segments.append(Segment(
                visibleRange: NSRange(location: visibleStart, length: idLen),
                sourceRange: NSRange(location: sourceCursor, length: idLen)
            ))
        }
        let chipLocation = (text as NSString).length
        text += "\u{FFFC}"
        chips.append(NSRange(location: chipLocation, length: 1))
        segments.append(Segment(
            visibleRange: NSRange(location: chipLocation, length: 1),
            sourceRange: regionItem.innerCharRange
        ))
        sourceCursor = regionItem.innerCharRange.location + regionItem.innerCharRange.length
    }

    let tailLen = ns.length - sourceCursor
    if tailLen > 0 {
        let visibleStart = (text as NSString).length
        text += ns.substring(from: sourceCursor)
        segments.append(Segment(
            visibleRange: NSRange(location: visibleStart, length: tailLen),
            sourceRange: NSRange(location: sourceCursor, length: tailLen)
        ))
    }

    let byOpenLine = foldedRegions.sorted { $0.openLine < $1.openLine }
    var mapping: [Int] = []
    var depths: [Int] = []
    var line = 0
    var regionIdx = 0
    while line < sourceLineDepths.count {
        mapping.append(line)
        depths.append(sourceLineDepths[line])
        if regionIdx < byOpenLine.count, byOpenLine[regionIdx].openLine == line {
            line = byOpenLine[regionIdx].closeLine + 1
            regionIdx += 1
        } else {
            line += 1
        }
    }

    return FoldComposition(
        visibleText: text,
        chipRanges: chips,
        visibleLineToSourceLine: mapping,
        visibleLineDepths: depths,
        segments: segments
    )
}

// MARK: - Fixture A：object 内一个 array 与一个 object 两个兄弟折叠区
//
//   0: {                     depth 0
//   1:   "a": 1,             depth 1
//   2:   "list": [           depth 1  ← array region openLine=2
//   3:     2,                depth 2
//   4:     3                 depth 2
//   5:   ],                  depth 1  ← array region closeLine=5
//   6:   "obj": {            depth 1  ← object region openLine=6
//   7:     "x": 9            depth 2
//   8:   }                   depth 1  ← object region closeLine=8
//   9: }                     depth 0
//
// outer region 横跨整个文本（openLine=0, closeLine=9），把 list/obj 两个
// 区域整体嵌套在内。全部 innerCharRange 由 makeRegion 依据实际字符串长度
// 在运行时计算，不依赖手工数的偏移量；下方数值只用于交叉核对/文档目的：
// outer.innerCharRange = (1, 67)，list.innerCharRange = (23, 16)，
// obj.innerCharRange = (52, 14)，源文本总长 69。

private let fixtureALines = [
    "{",
    "  \"a\": 1,",
    "  \"list\": [",
    "    2,",
    "    3",
    "  ],",
    "  \"obj\": {",
    "    \"x\": 9",
    "  }",
    "}"
]
private let fixtureAStarts = lineStartOffsets(fixtureALines)
private let fixtureASource = fixtureALines.joined(separator: "\n")
private let fixtureADepths = [0, 1, 1, 2, 2, 1, 1, 2, 1, 0]

private let fixtureAOuter = makeRegion(
    lines: fixtureALines, starts: fixtureAStarts,
    openLine: 0, openBracket: "{", closeLine: 9, closeBracket: "}", kind: .object
)
private let fixtureAList = makeRegion(
    lines: fixtureALines, starts: fixtureAStarts,
    openLine: 2, openBracket: "[", closeLine: 5, closeBracket: "]", kind: .array
)
private let fixtureAObj = makeRegion(
    lines: fixtureALines, starts: fixtureAStarts,
    openLine: 6, openBracket: "{", closeLine: 8, closeBracket: "}", kind: .object
)
private let fixtureAFoldMap = JSONFoldMap(
    regions: [fixtureAOuter, fixtureAList, fixtureAObj],
    lineDepths: fixtureADepths
)

// MARK: - Fixture B：字符串值内含补充平面字符（emoji，2 个 UTF-16 units）

private let fixtureBLines = [
    "{",
    "  \"list\": [",
    "    \"\u{1F600}\"",
    "  ]",
    "}"
]
private let fixtureBStarts = lineStartOffsets(fixtureBLines)
private let fixtureBSource = fixtureBLines.joined(separator: "\n")
private let fixtureBDepths = [0, 1, 2, 1, 0]
private let fixtureBList = makeRegion(
    lines: fixtureBLines, starts: fixtureBStarts,
    openLine: 1, openBracket: "[", closeLine: 3, closeBracket: "]", kind: .array
)
private let fixtureBFoldMap = JSONFoldMap(regions: [fixtureBList], lineDepths: fixtureBDepths)

@Suite("Hidden_jsonFoldComposer")
struct Hidden_jsonFoldComposer {

    // MARK: - compose: 恒等态

    @Test("collapsed 为空：与 oracle 恒等态一致")
    func test_jsonFoldComposer_composeIdentityWhenCollapsedEmpty() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [])
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [])

        #expect(result == expected)
        #expect(result.chipRanges.isEmpty)
        #expect(result.visibleText == fixtureASource)
    }

    @Test("collapsed 仅含 foldMap 中不存在的 id：忽略后与恒等态一致")
    func test_jsonFoldComposer_composeIgnoresUnknownCollapsedIdsEntirely() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [999, -1])
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [])

        #expect(result == expected)
    }

    @Test("collapsed 含未知 id 与合法 id 混合：未知 id 被忽略，合法 id 正常折叠")
    func test_jsonFoldComposer_composeIgnoresUnknownIdMixedWithValidId() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2, 999])
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [fixtureAList])

        #expect(result == expected)
    }

    @Test("foldMap 为 .empty 且 collapsed 非空：恒等态输出")
    func test_jsonFoldComposer_composeFoldMapEmptySentinelWithNonEmptyCollapsedYieldsIdentity() {
        let text = "plain text, no fold regions"
        let result = JSONFoldComposer.compose(sourceText: text, foldMap: .empty, collapsed: [5, 10])

        #expect(result.visibleText == text)
        #expect(result.chipRanges.isEmpty)
        #expect(result.segments == [
            Segment(
                visibleRange: NSRange(location: 0, length: (text as NSString).length),
                sourceRange: NSRange(location: 0, length: (text as NSString).length)
            )
        ])
    }

    // MARK: - compose: 单区折叠 + 行映射

    @Test("单区折叠：inner 内容替换为单个 U+FFFC，整份 FoldComposition 与 oracle 一致")
    func test_jsonFoldComposer_composeSingleRegionReplacesInnerWithSingleChip() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [fixtureAList])

        #expect(result == expected)
        #expect(result.chipRanges.count == 1)
        #expect(result.visibleText.filter { $0 == "\u{FFFC}" }.count == 1)
    }

    @Test("行映射：折叠行映射到 openLine，折叠区之后可见行跳号到 closeLine+1；深度取自对应源行")
    func test_jsonFoldComposer_composeLineMappingJumpsAcrossFoldedLines() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        #expect(result.visibleLineToSourceLine == [0, 1, 2, 6, 7, 8, 9])
        #expect(result.visibleLineDepths == [0, 1, 1, 1, 2, 1, 0])
    }

    // MARK: - compose: 嵌套折叠

    @Test(
        "嵌套：外层区折叠时内层区被整体吞并，结果与内层 id 是否也在 collapsed 中无关",
        arguments: [Set<Int>([0]), Set<Int>([0, 2, 6])]
    )
    func test_jsonFoldComposer_composeNestedOuterFoldSubsumesInnerRegardlessOfInnerMembership(_ collapsed: Set<Int>) {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: collapsed)
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [fixtureAOuter])

        #expect(result == expected)
        #expect(result.chipRanges.count == 1)
    }

    @Test("嵌套：仅内层区被折叠时，外层区照常展开")
    func test_jsonFoldComposer_composeNestedOnlyInnerFoldedLeavesOuterExpanded() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [6])
        let expected = expectedComposition(source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [fixtureAObj])

        #expect(result == expected)
        #expect(result.chipRanges.count == 1)
    }

    // MARK: - compose: 多区（互不嵌套）折叠

    @Test("多个互不嵌套的区各自折叠：chipRanges 按可见位置升序，长度恒为 1")
    func test_jsonFoldComposer_composeMultipleNonNestedRegionsFoldIndependently() {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2, 6])
        let expected = expectedComposition(
            source: fixtureASource, sourceLineDepths: fixtureADepths, foldedRegions: [fixtureAList, fixtureAObj]
        )

        #expect(result == expected)
        #expect(result.chipRanges.count == 2)
        #expect(result.chipRanges == result.chipRanges.sorted { $0.location < $1.location })
        for chip in result.chipRanges {
            #expect(chip.length == 1)
        }
    }

    // MARK: - compose: segments 通用不变量

    @Test("segments 按位置升序、互不重叠、联合覆盖全部可见文本")
    func test_jsonFoldComposer_composeSegmentsAreContiguousAscendingAndCoverFullVisibleText() throws {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2, 6])
        let totalVisibleLength = (result.visibleText as NSString).length

        let first = try #require(result.segments.first)
        #expect(first.visibleRange.location == 0)

        var expectedNext = 0
        for segment in result.segments {
            #expect(segment.visibleRange.location == expectedNext)
            expectedNext = segment.visibleRange.location + segment.visibleRange.length
        }
        #expect(expectedNext == totalVisibleLength)
        #expect(totalVisibleLength == 41)
    }

    @Test("chip 段的 sourceRange 恒等于对应折叠区的 innerCharRange，visibleRange 长度恒为 1")
    func test_jsonFoldComposer_composeChipSegmentSourceRangeEqualsRegionInnerCharRange() throws {
        let result = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [6])

        let chipSegment = try #require(result.segments.first { $0.visibleRange.length == 1 })
        #expect(chipSegment.sourceRange == fixtureAObj.innerCharRange)
    }

    // MARK: - compose: UTF-16 / 补充平面字符

    @Test("字符串内含补充平面字符（emoji）时，折叠占位与坐标映射均按 UTF-16 单位精确计算")
    func test_jsonFoldComposer_composeHandlesNonASCIISurrogatePairContent() {
        let result = JSONFoldComposer.compose(sourceText: fixtureBSource, foldMap: fixtureBFoldMap, collapsed: [1])
        let expected = expectedComposition(source: fixtureBSource, sourceLineDepths: fixtureBDepths, foldedRegions: [fixtureBList])

        #expect(result == expected)
        #expect(result.visibleText == "{\n  \"list\": [\u{FFFC}]\n}")
        #expect(result.chipRanges == [NSRange(location: 13, length: 1)])
        #expect(result.visibleLineToSourceLine == [0, 1, 4])
        #expect(result.visibleLineDepths == [0, 1, 0])
    }

    // MARK: - compose: 边界——空文本

    @Test("空源文本 + 与之匹配的空 foldMap：可见文本为空、单一零长度恒等段")
    func test_jsonFoldComposer_composeEmptySourceTextWithMatchingEmptyFoldMapProducesEmptyIdentity() {
        let emptyFoldMap = JSONFoldMap(regions: [], lineDepths: [0])
        let result = JSONFoldComposer.compose(sourceText: "", foldMap: emptyFoldMap, collapsed: [])

        #expect(result.visibleText == "")
        #expect(result.chipRanges.isEmpty)
        #expect(result.visibleLineToSourceLine == [0])
        #expect(result.visibleLineDepths == [0])
        #expect(result.segments == [
            Segment(visibleRange: NSRange(location: 0, length: 0), sourceRange: NSRange(location: 0, length: 0))
        ])
    }

    // MARK: - sourceRange(forVisible:in:)

    @Test("完全落在恒等段内：按该段的固定偏移量平移")
    func test_jsonFoldComposer_sourceRangeForVisibleFullyWithinIdentitySegmentShiftsByOffset() {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 30, length: 4), in: composition)

        #expect(result == NSRange(location: 45, length: 4))
    }

    @Test("跨恒等段与 chip 段的范围：映射结果的并为首尾相接的连续源范围")
    func test_jsonFoldComposer_sourceRangeForVisibleCrossSegmentUnionIsContiguous() {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 20, length: 5), in: composition)

        #expect(result == NSRange(location: 20, length: 20))
    }

    @Test("可见范围恰为 chip 段：展开为该 chip 的完整源范围（innerCharRange）")
    func test_jsonFoldComposer_sourceRangeForVisibleExactlyAtChipExpandsToFullInnerRange() {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 23, length: 1), in: composition)

        #expect(result == fixtureAList.innerCharRange)
    }

    @Test("零长度光标落在恒等段内部：源坐标按同一偏移量平移，长度仍为 0")
    func test_jsonFoldComposer_sourceRangeForVisibleZeroLengthCursorWithinIdentitySegment() {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 35, length: 0), in: composition)

        #expect(result == NSRange(location: 50, length: 0))
    }

    @Test("零长度光标恰在某 chip 的可见起点：映射到该区 innerCharRange.location")
    func test_jsonFoldComposer_sourceRangeForVisibleZeroLengthCursorAtChipStartMapsToInnerLocation() {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2, 6])

        let result = JSONFoldComposer.sourceRange(forVisible: NSRange(location: 37, length: 0), in: composition)

        #expect(result == NSRange(location: fixtureAObj.innerCharRange.location, length: 0))
    }

    // MARK: - visibleRange(forSource:in:)

    @Test("完全落在恒等段内：按该段的固定偏移量平移")
    func test_jsonFoldComposer_visibleRangeForSourceFullyWithinIdentitySegmentShiftsByOffset() throws {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = try #require(
            JSONFoldComposer.visibleRange(forSource: NSRange(location: 45, length: 4), in: composition)
        )

        #expect(result == NSRange(location: 30, length: 4))
    }

    @Test("完全落在被折叠区的 inner 内容中：返回该 chip 的可见范围（长度 1）")
    func test_jsonFoldComposer_visibleRangeForSourceFullyWithinFoldedInnerContentReturnsChipRange() throws {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = try #require(
            JSONFoldComposer.visibleRange(forSource: NSRange(location: 25, length: 5), in: composition)
        )

        #expect(result == NSRange(location: 23, length: 1))
    }

    @Test("部分重叠折叠内容：返回覆盖全部重叠内容的最小可见范围（含 chip 字符）")
    func test_jsonFoldComposer_visibleRangeForSourcePartialOverlapReturnsMinimalCoveringRange() throws {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])

        let result = try #require(
            JSONFoldComposer.visibleRange(forSource: NSRange(location: 30, length: 20), in: composition)
        )

        #expect(result == NSRange(location: 23, length: 12))
    }

    @Test(
        "源范围超出全部段覆盖（越界）：返回 nil",
        arguments: [(location: 69, length: 5), (location: 200, length: 1)]
    )
    func test_jsonFoldComposer_visibleRangeForSourceOutOfBoundsReturnsNil(_ testCase: (location: Int, length: Int)) {
        let composition = JSONFoldComposer.compose(sourceText: fixtureASource, foldMap: fixtureAFoldMap, collapsed: [2])
        let outOfBoundsRange = NSRange(location: testCase.location, length: testCase.length)

        let result = JSONFoldComposer.visibleRange(forSource: outOfBoundsRange, in: composition)

        #expect(result == nil)
    }
}
