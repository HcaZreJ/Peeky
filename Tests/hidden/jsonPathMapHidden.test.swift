import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONPathMap 全面用例
//
// 覆盖 build(prettyText:) 的父指针树契约：canonical 17 行 fixture 逐行断言（含
// "},” 带尾逗号闭括号行必须冻结在其自身节点、不被同行之后的逗号改写）、JSONL
// 括号不配对坏行的隔离（空行硬边界清栈，防止残留栈帧污染后续记录）、数组元素
// 为标量与为容器两种形态（含嵌套数组连续下标 jq 拼接）、非标识符 key 的六种
// 子类别（空格/连字符/中文/引号/反斜杠/控制字符）、单引号 key 转义为 '
// （自包含合法 jq/JSON 字符串转义，任何粘贴上下文下都合法，且不产生裸单引号）、
// 无空行终止的未闭合结构退化为当时栈顶节点、孤立闭括号容错、根为标量的
// fragment、空路径序列化、行号越界、以及大规模输入的性能冒烟。
//
// fixture 优先使用 JSONSerialization.prettyPrinted 真实产物（已验证本机 Foundation
// 输出为 `"key" : value` 形态）；canonical fixture 与截断/畸形输入按 plan 给定文本
// 手写（真实产物无法表达"括号不配对"），字符逐一与文档给出的形态核对。
// 所有断言均经 `path(line:)` 完成，不直接比较 `nodes` 数组内部下标（实现细节）。

private func prettyJSON(_ object: Any) -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: object,
        // .sortedKeys 让多 key object 的行序确定，可逐行断言；不影响仅靠
        // findSingleKeyPath 定位、原本就不依赖顺序的用例。
        options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
    )
    return String(data: data, encoding: .utf8)!
}

/// 在 map 中按 key 内容定位仅含单个 key 段的行，返回该行路径；用于 key 顺序不受
/// sortedKeys 控制的 fixture（同一 object 内多个非标识符 key）。
private func findSingleKeyPath(_ map: JSONPathMap, key: String, lineCount: Int) -> [JSONPathSegment]? {
    for line in 0..<lineCount {
        let p = map.path(line: line)
        if p.count == 1, case .key(let k) = p[0], k == key {
            return p
        }
    }
    return nil
}

@Suite("Hidden_jsonPathMap")
struct Hidden_jsonPathMap {

    // MARK: - Canonical 17 行 fixture（plan 给定，逐行断言）

    @Test("canonical fixture：20 行逐行路径精确匹配，闭括号带尾逗号行冻结在自身节点而非 index+1，空容器内部空行不清栈")
    func test_jsonPathMap_canonicalFixtureLineByLinePaths() {
        let text = """
        {
          "users" : [
            {
              "id" : 1
            },
            {
              "id" : 2
            }
          ],
          "counts" : [
            10,
            20
          ],
          "tags" : [

          ],
          "a" : {
            "b" : "x"
          }
        }
        """

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("users")])
        #expect(map.path(line: 2) == [.key("users"), .index(0)])
        #expect(map.path(line: 3) == [.key("users"), .index(0), .key("id")])
        #expect(map.path(line: 4) == [.key("users"), .index(0)])
        #expect(map.path(line: 5) == [.key("users"), .index(1)])
        #expect(map.path(line: 6) == [.key("users"), .index(1), .key("id")])
        #expect(map.path(line: 7) == [.key("users"), .index(1)])
        #expect(map.path(line: 8) == [.key("users")])
        #expect(map.path(line: 9) == [.key("counts")])
        #expect(map.path(line: 10) == [.key("counts"), .index(0)])
        #expect(map.path(line: 11) == [.key("counts"), .index(1)])
        #expect(map.path(line: 12) == [.key("counts")])
        #expect(map.path(line: 13) == [.key("tags")])
        // 行14："tags" 空数组的内部空行——不能被当成 JSONLines 记录分隔符清栈。
        #expect(map.path(line: 14) == [.key("tags")])
        #expect(map.path(line: 15) == [.key("tags")])
        #expect(map.path(line: 16) == [.key("a")])
        #expect(map.path(line: 17) == [.key("a"), .key("b")])
        #expect(map.path(line: 18) == [.key("a")])
        #expect(map.path(line: 19) == [])
        #expect(map.lineNode.count == 20)
    }

    // MARK: - 空容器跨行展开：内部空行不是 JSONLines 记录分隔符，不应清栈
    //
    // JSONSerialization.prettyPrinted 对空数组 / 空对象的真实产物会跨 3 行展开
    // （`[` / 空行 / `]`，`{` / 空行 / `}`），空行本身长度为 0——与 JSONLines
    // 记录分隔符字面相同。裁决规则：空行之前最近的非空白字符是 `{`/`[` 时，
    // 判定为空容器内部、不清栈；否则（`}`/`]`/数字/引号等）才是真正的记录
    // 分隔符。以下用例均为 JSONSerialization 真实产物（.sortedKeys 使多 key
    // object 的行序确定，可逐行断言）。

    @Test("空数组紧跟其它 key：空数组内部空行不清栈，其后的 key 路径正确、不退化为根")
    func test_jsonPathMap_emptyArrayInteriorBlankLineDoesNotClearStackBeforeSiblingKey() {
        // {
        //   "tags" : [
        //
        //   ],
        //   "z" : 1
        // }
        let text = prettyJSON(["tags": [Any](), "z": 1])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("tags")])
        #expect(map.path(line: 2) == [.key("tags")])
        #expect(map.path(line: 3) == [.key("tags")])
        #expect(map.path(line: 4) == [.key("z")])
        #expect(map.path(line: 5) == [])
        #expect(map.lineNode.count == 6)
    }

    @Test("空对象紧跟其它 key：空对象内部空行不清栈，其后的 key 路径正确、不退化为根")
    func test_jsonPathMap_emptyObjectInteriorBlankLineDoesNotClearStackBeforeSiblingKey() {
        // {
        //   "meta" : {
        //
        //   },
        //   "z" : 1
        // }
        let text = prettyJSON(["meta": [String: Any](), "z": 1])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("meta")])
        #expect(map.path(line: 2) == [.key("meta")])
        #expect(map.path(line: 3) == [.key("meta")])
        #expect(map.path(line: 4) == [.key("z")])
        #expect(map.path(line: 5) == [])
        #expect(map.lineNode.count == 6)
    }

    @Test("嵌套容器内的空数组：紧邻 key 的路径必须保留祖先前缀，不能丢成根级 [key(z)]")
    func test_jsonPathMap_nestedEmptyArrayPreservesAncestorPrefixForSiblingKey() {
        // {
        //   "a" : {
        //     "tags" : [
        //
        //     ],
        //     "z" : 1
        //   }
        // }
        let text = prettyJSON(["a": ["tags": [Any](), "z": 1]])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("a")])
        #expect(map.path(line: 2) == [.key("a"), .key("tags")])
        #expect(map.path(line: 3) == [.key("a"), .key("tags")])
        #expect(map.path(line: 4) == [.key("a"), .key("tags")])
        // 关键断言：必须带上 key(a) 前缀，不能因误清栈而退化成 [key(z)]。
        #expect(map.path(line: 5) == [.key("a"), .key("z")])
        #expect(map.path(line: 6) == [.key("a")])
        #expect(map.path(line: 7) == [])
        #expect(map.lineNode.count == 8)
    }

    @Test("数组内空容器元素后跟非空元素：非空元素下标仍正确递增（不受空元素内部空行干扰）")
    func test_jsonPathMap_emptyArrayElementFollowedBySiblingKeepsCorrectIndex() {
        // {
        //   "list" : [
        //     [
        //
        //     ],
        //     [
        //       1
        //     ]
        //   ]
        // }
        let text = prettyJSON(["list": [[Any](), [1]]])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("list")])
        #expect(map.path(line: 2) == [.key("list"), .index(0)])
        #expect(map.path(line: 3) == [.key("list"), .index(0)])
        #expect(map.path(line: 4) == [.key("list"), .index(0)])
        #expect(map.path(line: 5) == [.key("list"), .index(1)])
        #expect(map.path(line: 6) == [.key("list"), .index(1), .index(0)])
        #expect(map.path(line: 7) == [.key("list"), .index(1)])
        #expect(map.path(line: 8) == [.key("list")])
        #expect(map.path(line: 9) == [])
        #expect(map.lineNode.count == 10)
    }

    @Test("根为空容器（[] 或 {}）：内部空行不清栈（栈本就只有根帧），各行路径均为空，不崩溃")
    func test_jsonPathMap_rootEmptyContainersDoNotCrashAndAllLinesAreRootPath() {
        let arrayText = prettyJSON([Any]())
        let arrayMap = JSONPathMap.build(prettyText: arrayText)
        #expect(arrayMap.lineNode.count == 3)
        #expect(arrayMap.path(line: 0) == [])
        #expect(arrayMap.path(line: 1) == [])
        #expect(arrayMap.path(line: 2) == [])

        let objectText = prettyJSON([String: Any]())
        let objectMap = JSONPathMap.build(prettyText: objectText)
        #expect(objectMap.lineNode.count == 3)
        #expect(objectMap.path(line: 0) == [])
        #expect(objectMap.path(line: 1) == [])
        #expect(objectMap.path(line: 2) == [])
    }

    @Test("组合回归：记录内的空容器不清栈，且括号不配对坏行之后仍由空行分隔符正确隔离")
    func test_jsonPathMap_emptyContainerAndJSONLBadLineIsolationBothHoldTogether() {
        // 记录1（含空数组，内部空行不应清栈）/ 空行分隔符 / 记录2（括号不配对，
        // 原样输出）/ 空行分隔符（真正的记录边界，必须清栈）/ 记录3（合法）。
        // record1、record3 用 JSONSerialization 真实产物（.sortedKeys 保证确定
        // 行序），record2 与记录间分隔按 JSONFormatter.prettyJSONLines 的真实
        // 拼接约定（"\n\n"）手工拼接，避免依赖该 API 对多 key dict 的无序输出。
        //
        //  0 {                     6 (空行，真正的记录分隔符)
        //  1   "tags" : [          7 {"bad": [1,2
        //  2 (空行，空数组内部)     8 (空行，真正的记录分隔符)
        //  3   ],                  9 {
        //  4   "z" : 1            10   "c" : 3
        //  5 }                    11 }
        let record1 = prettyJSON(["tags": [Any](), "z": 1])
        let record2 = #"{"bad": [1,2"#
        let record3 = prettyJSON(["c": 3])
        let text = record1 + "\n\n" + record2 + "\n\n" + record3

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("tags")])
        #expect(map.path(line: 2) == [.key("tags")])
        #expect(map.path(line: 3) == [.key("tags")])
        #expect(map.path(line: 4) == [.key("z")])
        #expect(map.path(line: 5) == [])
        #expect(map.path(line: 6) == [])
        #expect(map.path(line: 7) == [.key("bad")])
        #expect(map.path(line: 8) == [])
        #expect(map.path(line: 9) == [])
        // 关键断言：记录3 的 "c" 行不能带上记录2 残留的 [key(bad), index(1)] 前缀。
        #expect(map.path(line: 10) == [.key("c")])
        #expect(map.path(line: 11) == [])
        #expect(map.lineNode.count == 12)
    }

    // MARK: - JSONL 坏行隔离：空行硬边界清栈

    @Test("JSONL 坏行隔离：括号不配对的坏行之后，空行清栈使下一条记录路径不带残留前缀")
    func test_jsonPathMap_jsonlBadLineIsolatedByBlankLineHardClear() {
        // 复用 JSONFormatter.prettyJSONLines 的真实拼接形态：
        // 记录1（合法）/ 记录2（"b": [1,2 括号不配对，原样输出）/ 记录3（合法）。
        // 已用独立脚本核对该 API 的真实产物，逐行内容如下（9 行）：
        //   0 {                    3 (空行)         6 {
        //   1   "a" : 1            4 {"b": [1,2     7   "c" : 3
        //   2 }                    5 (空行)         8 }
        let raw = #"{"a":1}"# + "\n" + #"{"b": [1,2"# + "\n" + #"{"c":3}"#
        let preview = JSONFormatter.prettyJSONLines(raw)
        let text = preview.text

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("a")])
        #expect(map.path(line: 2) == [])
        #expect(map.path(line: 3) == [])
        #expect(map.path(line: 4) == [.key("b")])
        #expect(map.path(line: 5) == [])
        #expect(map.path(line: 6) == [])
        // 关键断言：第三条记录的 "c" 行必须是 [key(c)]，不能带上第二条坏记录
        // 残留的 [key(b), index(2)] 前缀。
        #expect(map.path(line: 7) == [.key("c")])
        #expect(map.path(line: 8) == [])
    }

    // MARK: - 数组元素：标量

    @Test("根层数组元素为标量：下标按逗号递增，jqExpression 首段为 index 时输出 .[i]")
    func test_jsonPathMap_rootArrayOfScalarsIndexesIncrementSequentially() {
        // [
        //   1,
        //   2,
        //   3
        // ]
        let text = prettyJSON([1, 2, 3])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.index(0)])
        #expect(map.path(line: 2) == [.index(1)])
        #expect(map.path(line: 3) == [.index(2)])
        #expect(map.path(line: 4) == [])

        #expect(JSONPathMap.jqExpression(map.path(line: 1)) == ".[0]")
        #expect(JSONPathMap.dotPath(map.path(line: 1)) == "0")
        #expect(JSONPathMap.jqExpression(map.path(line: 3)) == ".[2]")
        #expect(JSONPathMap.dotPath(map.path(line: 3)) == "2")
    }

    // MARK: - 数组元素：容器（嵌套数组，连续下标）

    @Test("数组元素为容器：嵌套数组连续下标正确嵌套，jqExpression 连续 [i][j] 拼接不重复加点")
    func test_jsonPathMap_nestedArrayElementsProduceChainedIndexSegments() {
        // [
        //   [
        //     1,
        //     2
        //   ],
        //   [
        //     3,
        //     4
        //   ]
        // ]
        let text = prettyJSON([[1, 2], [3, 4]])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.index(0)])
        #expect(map.path(line: 2) == [.index(0), .index(0)])
        #expect(map.path(line: 3) == [.index(0), .index(1)])
        #expect(map.path(line: 4) == [.index(0)])
        #expect(map.path(line: 5) == [.index(1)])
        #expect(map.path(line: 6) == [.index(1), .index(0)])
        #expect(map.path(line: 7) == [.index(1), .index(1)])
        #expect(map.path(line: 8) == [.index(1)])
        #expect(map.path(line: 9) == [])

        #expect(JSONPathMap.jqExpression(map.path(line: 2)) == ".[0][0]")
        #expect(JSONPathMap.dotPath(map.path(line: 2)) == "0.0")
        #expect(JSONPathMap.jqExpression(map.path(line: 6)) == ".[1][0]")
        #expect(JSONPathMap.dotPath(map.path(line: 6)) == "1.0")
    }

    // MARK: - 闭括号带尾逗号行：冻结在自身节点（独立于 canonical fixture 的最小复现）

    @Test("数组中间元素的闭括号带尾逗号：该行路径是被闭合对象自身节点，不是下一元素的下标")
    func test_jsonPathMap_closingBraceWithTrailingCommaFreezesToOwnNodeNotNextIndex() {
        // {
        //   "list" : [
        //     {
        //       "x" : 1
        //     },
        //     {
        //       "y" : 2
        //     }
        //   ]
        // }
        let text = prettyJSON(["list": [["x": 1], ["y": 2]]])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("list")])
        #expect(map.path(line: 2) == [.key("list"), .index(0)])
        #expect(map.path(line: 3) == [.key("list"), .index(0), .key("x")])
        // "    }," —— 元素0自身闭合节点，不是 index(1)。
        #expect(map.path(line: 4) == [.key("list"), .index(0)])
        #expect(map.path(line: 5) == [.key("list"), .index(1)])
        #expect(map.path(line: 6) == [.key("list"), .index(1), .key("y")])
        #expect(map.path(line: 7) == [.key("list"), .index(1)])
        #expect(map.path(line: 8) == [.key("list")])
        #expect(map.path(line: 9) == [])
    }

    // MARK: - 非标识符 key：六种子类别

    @Test("非标识符 key 六种子类别（空格/连字符/中文/引号/反斜杠/控制字符）jq 转义正确、dotPath 保留原文")
    func test_jsonPathMap_nonIdentifierKeySixCategoriesEscapeCorrectly() throws {
        let controlCharKey = "ctrl\u{07}key"
        let quoteKey = "a\"b"
        let backslashKey = "a\\b"
        let dict: [String: Any] = [
            "id": 1,
            "a b": 2,
            "a-b": 3,
            "键": 4,
            quoteKey: 5,
            backslashKey: 6,
            controlCharKey: 7
        ]
        let text = prettyJSON(dict)
        let lineCount = text.components(separatedBy: "\n").count

        let map = JSONPathMap.build(prettyText: text)

        let idPath = try #require(findSingleKeyPath(map, key: "id", lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(idPath) == ".id")

        let spacePath = try #require(findSingleKeyPath(map, key: "a b", lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(spacePath) == #"."a b""#)
        #expect(JSONPathMap.dotPath(spacePath) == "a b")

        let hyphenPath = try #require(findSingleKeyPath(map, key: "a-b", lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(hyphenPath) == #"."a-b""#)
        #expect(JSONPathMap.dotPath(hyphenPath) == "a-b")

        let chinesePath = try #require(findSingleKeyPath(map, key: "键", lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(chinesePath) == #"."键""#)
        #expect(JSONPathMap.dotPath(chinesePath) == "键")

        let quotePath = try #require(findSingleKeyPath(map, key: quoteKey, lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(quotePath) == #"."a\"b""#)
        #expect(JSONPathMap.dotPath(quotePath) == quoteKey)

        let backslashPath = try #require(findSingleKeyPath(map, key: backslashKey, lineCount: lineCount))
        #expect(JSONPathMap.jqExpression(backslashPath) == #"."a\\b""#)
        #expect(JSONPathMap.dotPath(backslashPath) == backslashKey)

        let controlPath = try #require(findSingleKeyPath(map, key: controlCharKey, lineCount: lineCount))
        let expectedControlEscape = "." + "\"" + "ctrl" + "\\u0007" + "key" + "\""
        #expect(JSONPathMap.jqExpression(controlPath) == expectedControlEscape)
        #expect(JSONPathMap.dotPath(controlPath) == controlCharKey)
    }

    // MARK: - 单引号 key：shell 单引号安全转义

    @Test("key 含单引号：jqExpression 输出 \\u0027 转义（自包含合法字面量，不依赖 shell 拼接技巧）")
    func test_jsonPathMap_singleQuoteInKeyEscapedAsUnicodeSequence() {
        // { "can't" : 1 }
        let text = prettyJSON(["can't": 1])

        let map = JSONPathMap.build(prettyText: text)
        let path = map.path(line: 1)

        // 期望值用字符串拼接构造（而非 raw string 字面量），避免 ' 转义
        // 序列在源码里被误写成实际控制字符（此前控制字符测试踩过这个坑）。
        let expectedEscape = "." + "\"" + "can" + "\\u0027" + "t" + "\""

        #expect(path == [.key("can't")])
        #expect(JSONPathMap.jqExpression(path) == expectedEscape)
        #expect(JSONPathMap.dotPath(path) == "can't")
    }

    // MARK: - 未闭合结构（无空行终止）：沿用当时栈状态直到文本结束

    @Test("深层未闭合结构且无空行终止：末尾未确定节点的行退化为当时栈顶（最内层容器）的路径")
    func test_jsonPathMap_deeplyUnclosedStructureWithoutBlankLineFallsBackToDeepestOpenNode() {
        // {
        //   "a" : {
        //     "b" : {
        //       tru   ← 截断的 "true"，不含引号/冒号/括号/逗号，不产生任何确定节点
        let text = "{\n  \"a\" : {\n    \"b\" : {\n      tru"

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("a")])
        #expect(map.path(line: 2) == [.key("a"), .key("b")])
        #expect(map.path(line: 3) == [.key("a"), .key("b")])
        #expect(map.lineNode.count == 4)
    }

    // MARK: - 孤立闭括号：无匹配 opener 时被忽略，不崩溃

    @Test("孤立闭括号（无匹配 opener）被忽略，其后合法内容路径不受影响")
    func test_jsonPathMap_orphanClosingBracketIgnoredWithoutCrashing() {
        // }
        // {
        //   "x" : 1
        // }
        let text = "}\n{\n  \"x\" : 1\n}"

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [])
        #expect(map.path(line: 2) == [.key("x")])
        #expect(map.path(line: 3) == [])
    }

    // MARK: - 根为标量的 fragment

    @Test("根为标量的 fragment（数字/字符串/布尔）：单行，路径为空，不崩溃")
    func test_jsonPathMap_rootScalarFragmentsProduceSingleEmptyPathLine() {
        let numberData = try! JSONSerialization.data(withJSONObject: 42, options: [.prettyPrinted, .fragmentsAllowed])
        let numberText = String(data: numberData, encoding: .utf8)!
        let numberMap = JSONPathMap.build(prettyText: numberText)
        #expect(numberMap.lineNode.count == 1)
        #expect(numberMap.path(line: 0) == [])

        let stringData = try! JSONSerialization.data(withJSONObject: "hello", options: [.prettyPrinted, .fragmentsAllowed])
        let stringText = String(data: stringData, encoding: .utf8)!
        let stringMap = JSONPathMap.build(prettyText: stringText)
        #expect(stringMap.lineNode.count == 1)
        #expect(stringMap.path(line: 0) == [])

        let boolData = try! JSONSerialization.data(withJSONObject: true, options: [.prettyPrinted, .fragmentsAllowed])
        let boolText = String(data: boolData, encoding: .utf8)!
        let boolMap = JSONPathMap.build(prettyText: boolText)
        #expect(boolMap.lineNode.count == 1)
        #expect(boolMap.path(line: 0) == [])
    }

    // MARK: - 空路径序列化

    @Test("空路径序列化：jqExpression 为 \".\"，dotPath 为空串")
    func test_jsonPathMap_emptyPathSerializesToDotAndEmptyString() {
        #expect(JSONPathMap.jqExpression([]) == ".")
        #expect(JSONPathMap.dotPath([]) == "")
    }

    // MARK: - 行号越界

    @Test("行号越界（负数 / 等于行数 / 远超行数）一律返回空数组")
    func test_jsonPathMap_outOfBoundsLineNumberReturnsEmptyArray() {
        let text = "{\n  \"x\" : 1\n}"
        let map = JSONPathMap.build(prettyText: text)

        #expect(map.lineNode.count == 3)
        #expect(map.path(line: -1) == [])
        #expect(map.path(line: -100) == [])
        #expect(map.path(line: 3) == [])
        #expect(map.path(line: 10_000) == [])
    }

    // MARK: - 规模：单遍 O(n)，大输入性能冒烟

    @Test("~10 万行规模输入：build 在数秒内返回，行数与首尾块路径正确")
    func test_jsonPathMap_largeInputPerformanceSmokeReturnsWithinBudget() {
        let blockCount = 33_000
        let block = "{\n  \"n\": 0\n}"
        let text = Array(repeating: block, count: blockCount).joined(separator: "\n")

        let clock = ContinuousClock()
        let start = clock.now
        let map = JSONPathMap.build(prettyText: text)
        let elapsed = clock.now - start

        #expect(elapsed < .seconds(5))
        #expect(map.lineNode.count == blockCount * 3)
        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("n")])
        #expect(map.path(line: 2) == [])
        let lastBlockStart = (blockCount - 1) * 3
        #expect(map.path(line: lastBlockStart) == [])
        #expect(map.path(line: lastBlockStart + 1) == [.key("n")])
        #expect(map.path(line: lastBlockStart + 2) == [])
    }

    // MARK: - truncatedForDisplay：超短 limit 退化为纯省略号

    @Test("truncatedForDisplay：limit 过小（保留长度算出 <= 0）时退化为仅返回省略号，不崩溃、不产生负长度切片")
    func test_jsonPathMap_truncatedForDisplayDegeneratesToEllipsisForVeryShortLimit() {
        let text = String(repeating: "p", count: 10)

        #expect(JSONPathMap.truncatedForDisplay(text, limit: 1) == "…")
        #expect(JSONPathMap.truncatedForDisplay(text, limit: 4) == "…")
        #expect(JSONPathMap.truncatedForDisplay("hello", limit: 0) == "…")

        // limit 为 0 且文本本就为空：0 个字符不超过 limit 0，不进入截断分支，原样返回空串。
        #expect(JSONPathMap.truncatedForDisplay("", limit: 0) == "")
    }

    // MARK: - truncatedForDisplay：多字节字符按 Character 切片，不切碎字形

    @Test("truncatedForDisplay：超出 BMP 的 CJK 扩展字符（Character 计 1、UTF-16 计 2）落在截断边界时保持完整，不产生断裂 surrogate")
    func test_jsonPathMap_truncatedForDisplayPreservesMultiByteCharacterNotSplittingSurrogatePair() {
        // U+20BB7（CJK Extension B，"吉" 的异体字）：Swift Character 计数为 1，
        // 但 UTF-16 需要一个 surrogate pair（2 个 code unit）表示。
        let specialChar = "𠮷"
        #expect(specialChar.count == 1)
        #expect(specialChar.utf16.count == 2)

        let headFiller = String(repeating: "h", count: 27)
        let tailFiller = String(repeating: "t", count: 27)
        let middle = String(repeating: "m", count: 20)
        // 序列：[27 个 h][特殊字符][20 个 m][特殊字符][27 个 t] —— 共 76 个 Character。
        // 若按 Character 切片，prefix(28) 恰好在第一个特殊字符处收尾（27 + 1），
        // suffix(28) 恰好从第二个特殊字符处起始（1 + 27）——两处都是完整字形。
        let text = headFiller + specialChar + middle + specialChar + tailFiller
        #expect(text.count == 76)

        let truncated = JSONPathMap.truncatedForDisplay(text, limit: 60)

        let expectedHead = headFiller + specialChar
        let expectedTail = specialChar + tailFiller
        #expect(truncated == expectedHead + "…" + expectedTail)
        // 未产生 U+FFFD 替换字符，即两个特殊字符的 surrogate pair 均完整、未被腰斩。
        #expect(!truncated.unicodeScalars.contains { $0.value == 0xFFFD })
    }
}
