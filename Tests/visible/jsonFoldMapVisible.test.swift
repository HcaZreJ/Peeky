import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONFoldMap 可见样例
//
// 覆盖三条主干契约：跨行 object 产出单个折叠区（含 UTF-16 innerCharRange
// 精确计算）、跨行 array 产出单个折叠区（kind 区分）、以及"同一行内开又闭
// 的容器不产折叠区"（仅 depth 计算生效）。
//
// 所有 range 断言均为 UTF-16 偏移（NSRange），每个 fixture 的字符位置均
// 手工核对并在注释中标注索引。FoldRegion/JSONFoldMap 已声明 Equatable，
// 可直接用 `==` 比对整份数组；stub 阶段返回空集合时比较只会断言失败，
// 不会 crash。

private typealias Kind = FoldRegion.Kind

private func region(_ openLine: Int, _ closeLine: Int, _ location: Int, _ length: Int, _ kind: Kind) -> FoldRegion {
    FoldRegion(openLine: openLine, closeLine: closeLine, innerCharRange: NSRange(location: location, length: length), kind: kind)
}

@Suite("Visible_jsonFoldMap")
struct Visible_jsonFoldMap {
    @Test("跨行 object：单个折叠区，innerCharRange 精确到开括号后/闭括号前，lineDepths 按行给出")
    func test_jsonFoldMap_multiLineObjectProducesSingleRegionWithRangeAndDepths() {
        // "{\n  \"a\": 1\n}"
        // 0{ 1\n 2(sp) 3(sp) 4" 5a 6" 7: 8(sp) 9:1 10\n 11}
        let text = "{\n  \"a\": 1\n}"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 2, 1, 10, .object)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 0])
    }

    @Test("跨行 array：单个折叠区，kind 为 .array")
    func test_jsonFoldMap_multiLineArrayProducesSingleRegionOfArrayKind() {
        // "[\n  1,\n  2\n]"
        // 0[ 1\n 2(sp) 3(sp) 4:1 5, 6\n 7(sp) 8(sp) 9:2 10\n 11]
        let text = "[\n  1,\n  2\n]"

        let map = JSONFoldMap.build(prettyText: text)

        let expectedRegions = [region(0, 3, 1, 10, .array)]
        #expect(map.regions == expectedRegions)
        #expect(map.lineDepths == [0, 1, 1, 0])
    }

    @Test("同一行内开又闭的容器（object 与 array 均全在单行）不产生折叠区")
    func test_jsonFoldMap_sameLineContainersProduceZeroRegions() {
        let text = #"{"a": 1, "b": [1,2,3]}"#

        let map = JSONFoldMap.build(prettyText: text)

        #expect(map.regions == [])
        #expect(map.lineDepths == [0])
    }
}
