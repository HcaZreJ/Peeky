import Foundation

/// JSON/JSONL 惰性树索引：单遍扫描建节点表，值按需从原文物化。
/// 节点表为前序（文档顺序）数组，树形由 firstChild/nextSibling 编码。
struct JSONTreeIndex {
    enum NodeType: Equatable {
        case object
        case array
        case string
        case number
        case bool
        case null
        /// JSONL 中无法解析的记录行
        case invalid
    }

    struct Node: Equatable {
        var type: NodeType
        /// object 成员的 key token 范围（含引号）；数组元素与根节点为 nil
        var keyRange: Range<String.Index>?
        /// 值 token 的整体范围（string 含引号，容器含括号，invalid 为整行）
        var valueRange: Range<String.Index>
        /// 直接子节点数（标量与 invalid 为 0）
        var childCount: Int
        /// 首个子节点在节点表中的下标
        var firstChild: Int?
        /// 同层下一兄弟在节点表中的下标
        var nextSibling: Int?
        /// JSONL 坏行记录
        var isInvalid: Bool
        /// 嵌套深度 >512 被截断的容器（childCount 归 0）
        var isTruncated: Bool
    }

    /// 前序节点表
    var nodes: [Node]
    /// 根节点下标：JSON 单根（空文档为空数组）；JSONL 每条非空行记录一根
    var rootIndices: [Int]
    /// JSON 语法错误位置（返回部分索引时非 nil；合法文档为 nil）
    var errorIndex: String.Index?

    /// 单遍扫描构建索引。kind 取 .json / .jsonl，其余 kind 按 .json 处理。
    static func build(text: String, kind: FileKind) -> JSONTreeIndex {
        JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil)
    }

    /// 直接子节点下标（按文档顺序）；标量节点为空数组
    func children(of nodeIndex: Int) -> [Int] {
        []
    }

    /// 解码后的成员 key（去引号、解 JSON 转义）；无 key 的节点返回 nil
    func key(at nodeIndex: Int, in text: String) -> String? {
        nil
    }

    /// 值的原文切片（string 含引号，容器含括号，invalid 行为整行原文）
    func rawValue(at nodeIndex: Int, in text: String) -> String {
        ""
    }
}
