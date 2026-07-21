import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONFoldMap 全面用例
//
// 覆盖 build(prettyText:) 的单遍词法契约：空串/纯文本/坏 JSON 的零抛错
// 容错、行深度计算（空格计数 + 向下取整 + tab 不计入）、跨行容器的
// innerCharRange 精确计算（含 UTF-16 代理对）、字符串字面量内括号与
// 转义引号被正确忽略、JSONL 多顶层记录各自独立产区、嵌套容器 openLine
// 升序排列、错误表两条容错规则（未闭合 opener 整体跳过 / 无 opener 的
// 闭括号被忽略）、以及大规模输入的性能冒烟。
//
// 所有 range 断言均为 UTF-16 偏移（NSRange），多数 fixture 的字符位置
// 手工核对并在注释中标注索引；涉及代理对的用例改用从 NSString.length
// 派生的独立 oracle，避免手工计数代理对导致的误差。regions/lineDepths
// 均为普通数组比较，stub 阶段返回空集合时比较只会断言失败，不会 crash；
// 涉及单个区域字段检查的用例先以 `try #require` 锁定 count 再安全下标。

private typealias Kind = FoldRegion.Kind

private func region(_ openLine: Int, _ closeLine: Int, _ location: Int, _ length: Int, _ kind: Kind) -> FoldRegion {
    FoldRegion(openLine: openLine, closeLine: closeLine, innerCharRange: NSRange(location: location, length: length), kind: kind)
}

@Suite("Hidden_jsonFoldMap")
struct Hidden_jsonFoldMap {

    // MARK: - 空串 / 纯文本 / 坏 JSON 容错

    @Test("空字符串输入：regions 为空，lineDepths 恰有 1 个元素且深度为 0")
    func test_jsonFoldMap_emptyStringReturnsSingleZeroDepthLineAndNoRegions() {
        let map = JSONFoldMap.build(prettyText: "")

        #expect(map.regions == [])
        #expect(map.lineDepths == [0])
    }

    @Test("纯文本夹带未闭合的孤立开括号：不抛错、不崩溃，regions 为空（未闭合容器整体跳过）")
    func test_jsonFoldMap_plainTextWithUnclosedBraceReturnsEmptyRegionsWithoutCrashing() {
        let text = "hello {\nworld\nend"

        let map = JSONFoldMap.build(prettyText: text)

        #expect(map.regions == [])
        #expect(map.lineDepths == [0, 0, 0])
    }

    // MARK: - 行深度：空格计数 / 向下取整 / tab 不计入

    @Test("lineDepths：行首空格数按 2 整除向下取整，tab 不计入空格数（深度记为 0）")
    func test_jsonFoldMap_lineDepthsFloorDivisionAndTabsNotCountedAsSpaces() {
        // 依次：0 空格、1 空格、2 空格、3 空格、4 空格、1 个 tab
        let lines = ["a", " a", "  a", "   a", "    a", "\ta"]
        let text = lines.joined(separator: "\n")

        let map = JSONFoldMap.build(prettyText: text)

        #expect(map.lineDepths == [0, 0, 1, 1, 2, 0])
        #expect(map.regions == [])
    }

    // MARK: - 空容器跨行（spec 示例）

    @Test("空容器跨两行（{\\n}）：innerCharRange 恰为夹在中间的 1 个换行字符")
    func test_jsonFoldMap_emptyContainerSpanningTwoLinesHasSingleCharInnerRange() {
        // "{\n}"  0{ 1\n 2}
        let text = "{\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 1, 1, 1, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 0])
    }

    // MARK: - 嵌套容器：父子都收，openLine 升序

    @Test("object 内嵌 object：两个区域均产出，openLine 升序，innerCharRange 精确计算")
    func test_jsonFoldMap_nestedObjectInsideObjectProducesBothRegionsOpenLineAscending() {
        // "{\n  \"inner\": {\n    \"a\": 1\n  }\n}"
        // line0 "{"                  index0
        // line1 "  \"inner\": {"      indices2-13（开括号在13）
        // line2 "    \"a\": 1"        indices15-24
        // line3 "  }"                 indices26-28（闭括号在28）
        // line4 "}"                   index30
        let text = "{\n  \"inner\": {\n    \"a\": 1\n  }\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [
            region(0, 4, 1, 29, .object),
            region(1, 3, 14, 14, .object)
        ]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 2, 1, 0])
    }

    @Test("array 内嵌两个 object 兄弟节点：4 个区域按 openLine 升序排列，kind 各自正确")
    func test_jsonFoldMap_nestedArrayAndSiblingObjectsOpenLineAscendingOrdering() throws {
        let text = """
        {
          "list": [
            {
              "x": 1
            },
            {
              "y": 2
            }
          ]
        }
        """

        let map = JSONFoldMap.build(prettyText: text)

        try #require(map.regions.count == 4)
        #expect(map.regions[0].openLine == 0)
        #expect(map.regions[0].closeLine == 9)
        #expect(map.regions[0].kind == .object)
        #expect(map.regions[1].openLine == 1)
        #expect(map.regions[1].closeLine == 8)
        #expect(map.regions[1].kind == .array)
        #expect(map.regions[2].openLine == 2)
        #expect(map.regions[2].closeLine == 4)
        #expect(map.regions[2].kind == .object)
        #expect(map.regions[3].openLine == 5)
        #expect(map.regions[3].closeLine == 7)
        #expect(map.regions[3].kind == .object)
        #expect(map.lineDepths == [0, 1, 2, 3, 2, 2, 3, 2, 1, 0])
    }

    // MARK: - 字符串字面量内的括号与转义引号被忽略

    @Test("字符串值内的 { } [ ] 与转义引号 \\\" 均不产生结构性折叠区，仅外层 object 产出 1 个区域")
    func test_jsonFoldMap_stringLiteralBracketsAndEscapedQuoteIgnoredAsStructural() {
        // "{\n  \"note\": \"a { b } [ c ] \\\" end\"\n}"
        // 前缀 "{\n  \"note\": \"" 共 13 字符（indices 0-12，值的起始引号在 12）
        // 字符串内容 "a { b } [ c ] \" end" 共 20 字符（indices 13-32）
        // 收尾引号 index33，\n index34，外层闭括号 index35
        let text = "{\n  \"note\": \"a { b } [ c ] \\\" end\"\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 2, 1, 34, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0])
    }

    @Test("字符串以 \\\\ 结尾再闭引号：反斜杠转义序列不吞掉字符串收尾引号")
    func test_jsonFoldMap_doubleBackslashBeforeClosingQuoteStillEndsString() {
        // "{\n  \"p\": \"a\\\\\"\n}"
        // 0{ 1\n 2sp 3sp 4" 5p 6" 7: 8sp 9"(值起引号) 10a 11\ 12\ 13"(值收引号) 14\n 15}
        // 值内容为 a\（\\ 是一个反斜杠的转义），13 处引号正常收束字符串。
        let text = "{\n  \"p\": \"a\\\\\"\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 2, 1, 14, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0])
    }

    // MARK: - JSONL：多顶层记录各自独立产区

    @Test("JSONL 两条顶层记录：各自产出独立折叠区，互不影响")
    func test_jsonFoldMap_jsonlMultipleTopLevelRecordsEachProduceIndependentRegions() {
        // 第一条记录与第二条记录结构完全相同（仅 key/value 字符替换，长度不变），
        // 以 "\n" 相接：第二条记录整体右移 13 个字符位置。
        let text = "{\n  \"a\": 1\n}\n{\n  \"b\": 2\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [
            region(0, 2, 1, 10, .object),
            region(3, 5, 14, 10, .object)
        ]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0, 0, 1, 0])
    }

    // MARK: - 错误表：未闭合 opener 整体跳过

    @Test("末尾未闭合的 opener 该区域整体跳过，此前已闭合的合法区域不受影响")
    func test_jsonFoldMap_unclosedOpenerAtEndOfTextIsSkippedButPriorRegionRemains() {
        // 第一条记录合法闭合（同 jsonlMultipleTopLevelRecords 的首记录），
        // 第二条记录的 "{" 直到文本结束都未遇到匹配的 "}"。
        let text = "{\n  \"a\": 1\n}\n{\n  \"b\": 2"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 2, 1, 10, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0, 0, 1])
    }

    // MARK: - 错误表：无 opener 的闭括号被忽略

    @Test("无匹配 opener 的孤立闭括号被忽略，其后合法区域正常产出")
    func test_jsonFoldMap_closingBracketWithoutMatchingOpenerIsIgnored() {
        // "}\n{\n  \"x\": 1\n}"
        // line0 "}"（孤立，忽略） index0
        // line1 "{"（合法 opener） index2
        // line2 "  \"x\": 1"        indices4-11
        // line3 "}"（合法 closer） index13
        let text = "}\n{\n  \"x\": 1\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(1, 3, 3, 10, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 0, 1, 0])
    }

    // MARK: - UTF-16：代理对（补充平面字符）精确计数

    @Test("字符串值内含补充平面字符（emoji，代理对）时，innerCharRange 按 UTF-16 单位精确计算")
    func test_jsonFoldMap_utf16SurrogatePairEmojiCountedCorrectlyInInnerCharRange() throws {
        // 该 fixture 全文本仅有一对花括号，且首字符为 "{"、末字符为 "}"，
        // 借助 NSString.length 独立推导 expected range，规避手工数代理对。
        let text = "{\n  \"e\": \"😀🎉\"\n}"
        let nsText = text as NSString
        #expect(nsText.substring(to: 1) == "{")
        #expect(nsText.substring(from: nsText.length - 1) == "}")

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRange = NSRange(location: 1, length: nsText.length - 1 - 1)
        let expectedRegions = [FoldRegion(openLine: 0, closeLine: 2, innerCharRange: expectedRange, kind: .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0])
    }

    // MARK: - FoldRegion.id 派生自 openLine

    @Test("FoldRegion.id 恒等于该区域的 openLine")
    func test_jsonFoldMap_regionIdEqualsOpenLine() throws {
        let text = "{\n  \"a\": 1\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let onlyRegion = try #require(map.regions.first)
        #expect(onlyRegion.id == onlyRegion.openLine)
        #expect(onlyRegion.id == 0)
    }

    // MARK: - 规模：单遍 O(n)，大输入性能冒烟

    @Test("~10 万行规模输入：build 在数秒内返回，且 regions/lineDepths 数量与预期一致")
    func test_jsonFoldMap_largeInputPerformanceSmokeReturnsWithinBudget() {
        let blockCount = 33_000
        let block = "{\n  \"n\": 0\n}"
        let text = Array(repeating: block, count: blockCount).joined(separator: "\n")

        let clock = ContinuousClock()
        let start = clock.now
        let map = JSONFoldMap.build(prettyText: text)
        let elapsed = clock.now - start

        #expect(elapsed < .seconds(5))
        #expect(map.lineDepths.count == blockCount * 3)
        #expect(map.regions.count == blockCount)
    }
}
