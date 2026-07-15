import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONTreeIndex 可见样例
//
// 覆盖三条主干契约：JSON 对象单遍扫描建节点表、JSONL 每行独立成根节点、
// 以及 key/rawValue 两个访问器（key 解转义，rawValue 保留原文不解转义）。
//
// 所有对 build() 返回集合的下标访问都先经 `try #require` 校验，避免在
// stub（返回空索引）阶段发生越界 crash——crash 会中止整个测试进程，
// 而非被记录为单个用例失败。

private extension Array {
    /// 安全下标：越界返回 nil 而非 trap，供尚未实现（返回空集合）的
    /// stub 阶段配合 `#require` 干净地失败。
    func at(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@Suite("Visible_jsonTreeIndex")
struct Visible_jsonTreeIndex {
    @Test("JSON 对象：根节点 childCount 与子节点 key/rawValue 均正确")
    func buildJsonSimpleObjectIndexesChildren() throws {
        let text = #"{"name": "Peeky", "count": 3, "active": true}"#

        let index = JSONTreeIndex.build(text: text, kind: .json)

        try #require(index.rootIndices.count == 1)
        let root = try #require(index.rootIndices.at(0))
        let rootNode = try #require(index.nodes.at(root))
        #expect(rootNode.type == .object)
        #expect(rootNode.childCount == 3)

        let members = index.children(of: root)
        try #require(members.count == 3)
        #expect(index.key(at: members[0], in: text) == "name")
        #expect(index.rawValue(at: members[0], in: text) == "\"Peeky\"")
        #expect(index.key(at: members[1], in: text) == "count")
        #expect(index.rawValue(at: members[1], in: text) == "3")
        #expect(index.key(at: members[2], in: text) == "active")
        #expect(index.rawValue(at: members[2], in: text) == "true")
    }

    @Test("JSONL：每条非空行各自成一个顶层根节点")
    func buildJsonlEachLineBecomesOwnRoot() throws {
        let text = "{\"id\": 1}\n{\"id\": 2}\n"

        let index = JSONTreeIndex.build(text: text, kind: .jsonl)

        try #require(index.rootIndices.count == 2)
        let firstNode = try #require(index.nodes.at(index.rootIndices[0]))
        let secondNode = try #require(index.nodes.at(index.rootIndices[1]))
        #expect(firstNode.type == .object)
        #expect(secondNode.type == .object)
        #expect(firstNode.isInvalid == false)
        #expect(secondNode.isInvalid == false)
    }

    @Test("key 解码转义；rawValue 对字符串保留原文（含引号，不解转义）")
    func keyDecodesEscapeRawValueKeepsOriginalText() throws {
        let text = #"{"Hello": "wor\nld"}"#

        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let members = index.children(of: root)
        try #require(members.count == 1)

        #expect(index.key(at: members[0], in: text) == "Hello")
        #expect(index.rawValue(at: members[0], in: text) == #""wor\nld""#)
    }
}
