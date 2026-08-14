import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONPathMap 可见样例
//
// 覆盖三条主干契约：跨行 object/array 混合结构逐行求出正确节点路径并能序列化为
// jq 表达式与点分形态（对应 plan Overview 的头条示例 `.users[0].user.phone`）、
// 非标识符 key（含空格）在 jq 表达式里走带引号转义形态而标识符 key 不带引号、
// 以及空文本与越界行号的零抛错退化行为。fixture 使用 JSONSerialization.prettyPrinted
// 真实产物（已验证本机 Foundation 输出格式为 `"key" : value`，键值间冒号两侧各一个空格，
// 每层缩进 2 个空格）。

private func prettyJSON(_ object: Any) -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .withoutEscapingSlashes]
    )
    return String(data: data, encoding: .utf8)!
}

@Suite("Visible_jsonPathMap")
struct Visible_jsonPathMap {
    @Test("跨行 object/array 混合结构：逐行路径正确，jqExpression 与 dotPath 序列化匹配头条示例")
    func test_jsonPathMap_nestedObjectArrayMixedProducesHeadlineExamplePath() {
        // {
        //   "users" : [
        //     {
        //       "user" : {
        //         "phone" : "123"
        //       }
        //     }
        //   ]
        // }
        let text = prettyJSON(["users": [["user": ["phone": "123"]]]])

        let map = JSONPathMap.build(prettyText: text)

        #expect(map.path(line: 0) == [])
        #expect(map.path(line: 1) == [.key("users")])
        #expect(map.path(line: 2) == [.key("users"), .index(0)])
        #expect(map.path(line: 3) == [.key("users"), .index(0), .key("user")])
        let phonePath = map.path(line: 4)
        #expect(phonePath == [.key("users"), .index(0), .key("user"), .key("phone")])
        #expect(map.path(line: 5) == [.key("users"), .index(0), .key("user")])
        #expect(map.path(line: 6) == [.key("users"), .index(0)])
        #expect(map.path(line: 7) == [.key("users")])
        #expect(map.path(line: 8) == [])

        #expect(JSONPathMap.jqExpression(phonePath) == ".users[0].user.phone")
        #expect(JSONPathMap.dotPath(phonePath) == "users.0.user.phone")
    }

    @Test("非标识符 key（含空格）序列化为 jq 带引号形式；标识符 key 序列化为不带引号形式")
    func test_jsonPathMap_nonIdentifierKeyQuotedIdentifierKeyBare() throws {
        // {
        //   "id" : 1,
        //   "user name" : 2
        // }
        let text = prettyJSON(["id": 1, "user name": 2])

        let map = JSONPathMap.build(prettyText: text)

        // 两个 key 行在 sortedKeys 缺省（无序）情况下位置不确定，逐行扫描定位。
        var idPath: [JSONPathSegment]?
        var userNamePath: [JSONPathSegment]?
        let lineCount = text.components(separatedBy: "\n").count
        for line in 0..<lineCount {
            let p = map.path(line: line)
            guard p.count == 1, case .key(let k) = p[0] else { continue }
            if k == "id" { idPath = p }
            if k == "user name" { userNamePath = p }
        }

        let id = try #require(idPath)
        let userName = try #require(userNamePath)

        #expect(JSONPathMap.jqExpression(id) == ".id")
        #expect(JSONPathMap.dotPath(id) == "id")
        #expect(JSONPathMap.jqExpression(userName) == #"."user name""#)
        #expect(JSONPathMap.dotPath(userName) == "user name")
    }

    @Test("空文本与越界行号：build 不抛错，path(line:) 越界一律返回空数组")
    func test_jsonPathMap_emptyTextAndOutOfBoundsLineDegradeGracefully() {
        let map = JSONPathMap.build(prettyText: "")

        #expect(map.lineNode.count == 1)
        #expect(map.path(line: 0) == [])
        #expect(map.path(line: -1) == [])
        #expect(map.path(line: 1) == [])
        #expect(map.path(line: 999) == [])
    }

    @Test("truncatedForDisplay：未超限原样返回，恰好等于 limit 同样原样返回（不触发截断）")
    func test_jsonPathMap_truncatedForDisplayReturnsOriginalWhenNotExceedingLimit() {
        let shortText = String(repeating: "x", count: 40)
        #expect(JSONPathMap.truncatedForDisplay(shortText, limit: 60) == shortText)

        let exactlyAtLimit = String(repeating: "y", count: 60)
        #expect(JSONPathMap.truncatedForDisplay(exactlyAtLimit, limit: 60) == exactlyAtLimit)
    }

    @Test("truncatedForDisplay：超过 60 字符时保留首 28 + 省略号 + 末 28（状态栏路径的实际调用形态）")
    func test_jsonPathMap_truncatedForDisplayKeepsHeadAndTailWithEllipsisWhenExceedingLimit() {
        let head = String(repeating: "a", count: 28)
        let middle = String(repeating: "m", count: 20)
        let tail = String(repeating: "z", count: 28)
        let text = head + middle + tail // 76 字符，超过 60

        let truncated = JSONPathMap.truncatedForDisplay(text, limit: 60)

        #expect(truncated == head + "…" + tail)
    }
}
