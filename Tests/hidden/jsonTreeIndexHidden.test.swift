import Testing
import Foundation
@testable import PeekyKit

// MARK: - JSONTreeIndex 全面用例
//
// 覆盖 build(text:kind:) 的 JSON / JSONL 两条路径（happy path、空输入、
// 深度截断、语法错误部分索引保留）、children(of:) 的文档顺序遍历、
// key(at:in:) 的转义解码、以及 rawValue(at:in:) 的“保留原文不解转义”契约。
// 每个测试独立构造自己的文本 fixture，互不共享可变状态。
//
// 所有对 build() 返回集合的下标访问都先经 `try #require`（或
// guard + Issue.record）校验，避免在 stub（返回空索引）阶段发生越界
// crash——crash 会中止整个测试进程，而非被记录为单个用例失败。

private extension Array {
    /// 安全下标：越界返回 nil 而非 trap，供尚未实现（返回空集合）的
    /// stub 阶段配合 `#require` 干净地失败。
    func at(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

@Suite("Hidden_jsonTreeIndex")
struct Hidden_jsonTreeIndex {

    // MARK: - build：空输入 / 全空白

    @Test("JSON：空字符串输入返回零节点空索引，不 throw")
    func buildJsonEmptyInputReturnsEmptyIndex() {
        let index = JSONTreeIndex.build(text: "", kind: .json)

        #expect(index.nodes.isEmpty)
        #expect(index.rootIndices.isEmpty)
        #expect(index.errorIndex == nil)
    }

    @Test("JSON：全空白输入返回零节点空索引")
    func buildJsonWhitespaceOnlyReturnsEmptyIndex() {
        let index = JSONTreeIndex.build(text: "   \n\t  \n", kind: .json)

        #expect(index.nodes.isEmpty)
        #expect(index.rootIndices.isEmpty)
        #expect(index.errorIndex == nil)
    }

    @Test("JSONL：全部为空行/空白行时不产生任何根节点")
    func buildJsonlAllBlankLinesReturnsEmptyIndex() {
        let text = "\n   \n\t\n"
        let index = JSONTreeIndex.build(text: text, kind: .jsonl)

        #expect(index.nodes.isEmpty)
        #expect(index.rootIndices.isEmpty)
    }

    // MARK: - build：JSON 标量根 / 空白容忍

    @Test("JSON：合法的标量根节点（数字/字符串/布尔/null）均单根，childCount 为 0，且无语法错误")
    func buildJsonScalarRootValues() {
        let cases: [(String, JSONTreeIndex.NodeType)] = [
            ("42", .number),
            ("\"hi\"", .string),
            ("true", .bool),
            ("false", .bool),
            ("null", .null)
        ]

        for (text, expectedType) in cases {
            let index = JSONTreeIndex.build(text: text, kind: .json)
            guard index.rootIndices.count == 1, let root = index.rootIndices.at(0) else {
                Issue.record("输入 \(text) 应恰好单根")
                continue
            }
            guard let rootNode = index.nodes.at(root) else {
                Issue.record("输入 \(text) 的根下标 \(root) 越界")
                continue
            }
            #expect(rootNode.type == expectedType, "输入 \(text)")
            #expect(rootNode.childCount == 0, "输入 \(text)")
            #expect(index.errorIndex == nil, "输入 \(text)")
        }
    }

    @Test("JSON：根节点前后允许空白，不视为语法错误")
    func buildJsonWhitespaceAroundRootIsAllowed() throws {
        let text = "  \n  42  \n "
        let index = JSONTreeIndex.build(text: text, kind: .json)

        #expect(index.errorIndex == nil)
        try #require(index.rootIndices.count == 1)
        let root = try #require(index.rootIndices.at(0))
        #expect(index.rawValue(at: root, in: text) == "42")
    }

    // MARK: - build：嵌套容器结构 / children 顺序

    @Test("JSON：嵌套容器的 children(of:) 按文档顺序返回直接子节点")
    func buildJsonNestedContainersChildrenInDocumentOrder() throws {
        let text = #"{"list": [10, {"k": 20}, 30], "flag": false}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)

        let root = try #require(index.rootIndices.at(0))
        let topMembers = index.children(of: root)
        try #require(topMembers.count == 2)
        #expect(index.key(at: topMembers[0], in: text) == "list")
        #expect(index.key(at: topMembers[1], in: text) == "flag")

        let listNode = topMembers[0]
        let listNodeData = try #require(index.nodes.at(listNode))
        #expect(listNodeData.type == .array)
        let listElements = index.children(of: listNode)
        try #require(listElements.count == 3)
        #expect(index.rawValue(at: listElements[0], in: text) == "10")
        let secondElementNode = try #require(index.nodes.at(listElements[1]))
        #expect(secondElementNode.type == .object)
        #expect(index.rawValue(at: listElements[2], in: text) == "30")

        let nestedMembers = index.children(of: listElements[1])
        try #require(nestedMembers.count == 1)
        #expect(index.key(at: nestedMembers[0], in: text) == "k")
        #expect(index.rawValue(at: nestedMembers[0], in: text) == "20")
    }

    @Test("JSON：数组元素 keyRange 为 nil，object 成员 keyRange 非 nil")
    func arrayElementsHaveNilKeyRangeObjectMembersHaveKeyRange() throws {
        let text = #"{"items": [1, 2], "meta": {"n": 1}}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let topMembers = index.children(of: root)
        try #require(topMembers.count == 2)

        for member in topMembers {
            let node = try #require(index.nodes.at(member))
            #expect(node.keyRange != nil)
        }

        let itemsNode = topMembers[0]
        for item in index.children(of: itemsNode) {
            let node = try #require(index.nodes.at(item))
            #expect(node.keyRange == nil)
            #expect(index.key(at: item, in: text) == nil)
        }

        let metaNode = topMembers[1]
        let metaMembers = index.children(of: metaNode)
        try #require(metaMembers.count == 1)
        let metaMemberNode = try #require(index.nodes.at(metaMembers[0]))
        #expect(metaMemberNode.keyRange != nil)
    }

    @Test("JSON：空对象 {} 与空数组 [] 的 childCount 均为 0，children(of:) 为空")
    func emptyObjectAndArrayHaveZeroChildren() throws {
        let text = #"{"obj": {}, "arr": []}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let members = index.children(of: root)
        try #require(members.count == 2)

        for member in members {
            let node = try #require(index.nodes.at(member))
            #expect(node.childCount == 0)
            #expect(index.children(of: member).isEmpty)
        }
    }

    @Test("children(of:)：标量节点没有子节点")
    func childrenOfScalarNodeIsEmpty() throws {
        let text = "[1, 2, 3]"
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let elements = index.children(of: root)
        try #require(elements.count == 3)

        for element in elements {
            #expect(index.children(of: element).isEmpty)
            let node = try #require(index.nodes.at(element))
            #expect(node.childCount == 0)
        }
    }

    // MARK: - build：嵌套深度截断

    @Test("JSON：嵌套深度超过 512 时该容器被截断（isTruncated == true 且 childCount == 0）")
    func nestingDeeperThan512Truncates() {
        let depth = 520
        let text = String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let index = JSONTreeIndex.build(text: text, kind: .json)

        #expect(index.rootIndices.count == 1)
        let hasTruncatedContainer = index.nodes.contains { $0.isTruncated && $0.childCount == 0 }
        #expect(hasTruncatedContainer)
    }

    // MARK: - build：JSON 语法错误 → 部分索引

    @Test("JSON：值缺失的语法错误设置 errorIndex，且已成功解析的前缀节点保留")
    func syntaxErrorMissingValueKeepsPrefixNodes() {
        let text = #"{"a": 1, "b": }"#
        let index = JSONTreeIndex.build(text: text, kind: .json)

        #expect(index.errorIndex != nil)
        let hasMemberA = index.nodes.contains { node in
            guard let keyRange = node.keyRange else { return false }
            return String(text[keyRange]) == "\"a\"" && String(text[node.valueRange]) == "1"
        }
        #expect(hasMemberA)
    }

    @Test("JSON：文档从起始处即无法识别任何合法 token 时设置 errorIndex 且节点表为空")
    func immediatelyInvalidDocumentSetsErrorIndex() {
        let text = "not-json-at-all"
        let index = JSONTreeIndex.build(text: text, kind: .json)

        #expect(index.errorIndex != nil)
        #expect(index.nodes.isEmpty)
        #expect(index.rootIndices.isEmpty)
    }

    @Test("JSON：合法根节点之后存在多余非空白内容时设置 errorIndex，但根节点及其成员仍保留在节点表中")
    func trailingContentAfterRootSetsErrorIndex() {
        let text = #"{"a": 1}garbage"#
        let index = JSONTreeIndex.build(text: text, kind: .json)

        #expect(index.errorIndex != nil)
        let hasRootObject = index.nodes.contains { $0.type == .object && $0.childCount == 1 }
        #expect(hasRootObject)
        let hasMemberA = index.nodes.contains { node in
            guard let keyRange = node.keyRange else { return false }
            return String(text[keyRange]) == "\"a\"" && String(text[node.valueRange]) == "1"
        }
        #expect(hasMemberA)
    }

    // MARK: - build：JSONL 坏行 / 混合行

    @Test("JSONL：有效记录之间的空行/空白行被跳过，不产生根节点")
    func jsonlBlankLinesSkippedBetweenValidRecords() throws {
        let text = "{\"a\":1}\n\n   \n{\"b\":2}\n"
        let index = JSONTreeIndex.build(text: text, kind: .jsonl)

        try #require(index.rootIndices.count == 2)
        let first = index.rootIndices[0]
        let second = index.rootIndices[1]
        let firstMember = try #require(index.children(of: first).at(0))
        let secondMember = try #require(index.children(of: second).at(0))
        #expect(index.key(at: firstMember, in: text) == "a")
        #expect(index.key(at: secondMember, in: text) == "b")
    }

    @Test("JSONL：无法解析的记录行产生单一 invalid 节点，childCount 为 0")
    func jsonlInvalidLineMarkedAsInvalidNode() throws {
        let text = "totally-not-json\n{\"ok\":true}\n"
        let index = JSONTreeIndex.build(text: text, kind: .jsonl)

        try #require(index.rootIndices.count == 2)
        let badIndex = index.rootIndices[0]
        let goodIndex = index.rootIndices[1]
        let badNode = try #require(index.nodes.at(badIndex))
        #expect(badNode.type == .invalid)
        #expect(badNode.isInvalid == true)
        #expect(badNode.childCount == 0)
        #expect(index.rawValue(at: badIndex, in: text) == "totally-not-json")

        let goodNode = try #require(index.nodes.at(goodIndex))
        #expect(goodNode.type == .object)
        #expect(goodNode.isInvalid == false)
    }

    @Test("JSONL：合法与非法行交替出现时逐行独立成根，坏行不影响其余行")
    func jsonlMixedValidAndInvalidLinesRootCount() throws {
        let text = "{\"a\":1}\nbad1\nbad2\n{\"b\":2}\n"
        let index = JSONTreeIndex.build(text: text, kind: .jsonl)

        try #require(index.rootIndices.count == 4)
        let n0 = try #require(index.nodes.at(index.rootIndices[0]))
        let n1 = try #require(index.nodes.at(index.rootIndices[1]))
        let n2 = try #require(index.nodes.at(index.rootIndices[2]))
        let n3 = try #require(index.nodes.at(index.rootIndices[3]))
        #expect(n0.type == .object)
        #expect(n1.isInvalid == true)
        #expect(n2.isInvalid == true)
        #expect(n3.type == .object)
    }

    // MARK: - key(at:in:)

    @Test("key(at:in:)：根节点与数组元素均无 key，返回 nil")
    func keyReturnsNilForRootAndArrayElements() throws {
        let objectRootText = #"{"a": 1}"#
        let objectIndex = JSONTreeIndex.build(text: objectRootText, kind: .json)
        let objectRoot = try #require(objectIndex.rootIndices.at(0))
        #expect(objectIndex.key(at: objectRoot, in: objectRootText) == nil)

        let arrayText = "[1, 2]"
        let arrayIndex = JSONTreeIndex.build(text: arrayText, kind: .json)
        let arrayRoot = try #require(arrayIndex.rootIndices.at(0))
        for element in arrayIndex.children(of: arrayRoot) {
            #expect(arrayIndex.key(at: element, in: arrayText) == nil)
        }
    }

    @Test("key(at:in:)：解码转义引号 \\\" 与转义反斜杠 \\\\")
    func keyDecodesEscapedQuoteAndBackslash() throws {
        let text = #"{"a\"b": 1, "c\\d": 2}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let members = index.children(of: root)
        try #require(members.count == 2)

        #expect(index.key(at: members[0], in: text) == "a\"b")
        #expect(index.key(at: members[1], in: text) == "c\\d")
    }

    @Test("key(at:in:)：解码 \\uXXXX 转义与代理对（surrogate pair）组成的补充平面字符")
    func keyDecodesUnicodeEscapeAndSurrogatePair() throws {
        // fixture 原文中含字面转义序列 H（= "H"），key(at:) 须解码
        let bmpText = #"{"Hello": 1}"#
        let bmpIndex = JSONTreeIndex.build(text: bmpText, kind: .json)
        let bmpRoot = try #require(bmpIndex.rootIndices.at(0))
        let bmpMember = try #require(bmpIndex.children(of: bmpRoot).at(0))
        #expect(bmpIndex.key(at: bmpMember, in: bmpText) == "Hello")

        // 代理对 😀 = 😀（补充平面字符须组对解码）
        let emojiText = #"{"😀": 1}"#
        let emojiIndex = JSONTreeIndex.build(text: emojiText, kind: .json)
        let emojiRoot = try #require(emojiIndex.rootIndices.at(0))
        let emojiMember = try #require(emojiIndex.children(of: emojiRoot).at(0))
        #expect(emojiIndex.key(at: emojiMember, in: emojiText) == "😀")

        // 非转义的字面 Unicode key 原样返回
        let literalText = #"{"你好😀": 1}"#
        let literalIndex = JSONTreeIndex.build(text: literalText, kind: .json)
        let literalRoot = try #require(literalIndex.rootIndices.at(0))
        let literalMember = try #require(literalIndex.children(of: literalRoot).at(0))
        #expect(literalIndex.key(at: literalMember, in: literalText) == "你好😀")
    }

    // MARK: - rawValue(at:in:)

    @Test("rawValue(at:in:)：字符串值返回含引号的原文，转义序列不解码")
    func rawValueStringReturnsQuotedUndecodedText() throws {
        let text = #"{"greeting": "hi\tthere\n"}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let member = try #require(index.children(of: root).at(0))

        #expect(index.rawValue(at: member, in: text) == #""hi\tthere\n""#)
    }

    @Test("rawValue(at:in:)：容器节点返回含括号的整段原文")
    func rawValueContainerReturnsBracketedSubstring() throws {
        let text = #"{"nested": {"x": 1, "y": [2, 3]}}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let nestedMember = try #require(index.children(of: root).at(0))

        #expect(index.rawValue(at: nestedMember, in: text) == #"{"x": 1, "y": [2, 3]}"#)

        let yMember = try #require(index.children(of: nestedMember).at(1))
        #expect(index.rawValue(at: yMember, in: text) == "[2, 3]")
    }

    @Test("rawValue(at:in:)：number/bool/null 均返回原始字面 token")
    func rawValueNumberBoolNullReturnLiteralTokens() throws {
        let text = #"{"n": -12.5e3, "t": true, "f": false, "z": null}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let members = index.children(of: root)
        try #require(members.count == 4)

        #expect(index.rawValue(at: members[0], in: text) == "-12.5e3")
        #expect(index.rawValue(at: members[1], in: text) == "true")
        #expect(index.rawValue(at: members[2], in: text) == "false")
        #expect(index.rawValue(at: members[3], in: text) == "null")
    }

    @Test("rawValue(at:in:)：JSONL 坏行节点返回整行原文")
    func rawValueInvalidJsonlLineReturnsRawLineText() throws {
        let text = "garbage-line\n{\"ok\":1}\n"
        let index = JSONTreeIndex.build(text: text, kind: .jsonl)
        let badNode = try #require(index.rootIndices.at(0))

        #expect(index.rawValue(at: badNode, in: text) == "garbage-line")
    }

    @Test("rawValue(at:in:)：字符串中的非转义 Unicode 字符（中文/emoji）原样保留")
    func rawValuePreservesUnicodeCharactersWithoutEscaping() throws {
        let text = #"{"greeting": "你好😀"}"#
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let root = try #require(index.rootIndices.at(0))
        let member = try #require(index.children(of: root).at(0))

        #expect(index.key(at: member, in: text) == "greeting")
        #expect(index.rawValue(at: member, in: text) == #""你好😀""#)
    }
}
