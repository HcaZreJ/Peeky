import Foundation

/// One step of a JSON node's access path: an object member key or an array index.
enum JSONPathSegment: Equatable, Sendable {
    case key(String)
    case index(Int)
}

/// JSON/JSONL pretty-print 文本的逐行节点路径索引：每一条逻辑行对应它所指节点。
///
/// 存储为父指针树（`nodes` + `lineNode`），避免逐行物化 `[[JSONPathSegment]]`
/// 在大文件上的内存放大（实测 80MB 级 JSON 逐行物化要到 650MB）。
///
/// `build(prettyText:)` 单遍 UTF-16 词法扫描 pretty-print 后的 JSON 文本，
/// 为每一条逻辑行（按 "\n" 切分）求出该行所指节点。任何输入都不抛错、不 trap。
struct JSONPathMap: Equatable, Sendable {
    /// 树节点：一个路径段 + 其父节点在 `nodes` 中的下标（-1 表示父为根）。
    struct Node: Equatable, Sendable {
        let parent: Int32
        let segment: JSONPathSegment
    }

    /// 全部路径段节点，按创建顺序排列。
    let nodes: [Node]
    /// 每逻辑行对应的节点下标；-1 表示该行指向根（路径为空）。
    /// 行数 = 文本按 "\n" 切分的段数（空文本为 1 行、-1）。
    let lineNode: [Int32]

    init(nodes: [Node], lineNode: [Int32]) {
        self.nodes = nodes
        self.lineNode = lineNode
    }

    // MARK: - build

    private enum ContainerKind {
        case object
        case array
    }

    private struct OpenFrame {
        let kind: ContainerKind
        /// 该容器自身在 nodes 中的下标；-1 表示该容器就是根。
        let nodeIndex: Int32
        /// 仅 array 使用：下一个待分配的下标。
        var nextIndex: Int = 0
        /// 仅 array 使用：是否正等待"新元素起始"这个位置。
        var awaitingElementStart: Bool = false
    }

    static func build(prettyText: String) -> JSONPathMap {
        let units = Array(prettyText.utf16)
        let length = units.count

        let newline: UInt16 = 0x0A
        let space: UInt16 = 0x20
        let tab: UInt16 = 0x09
        let cr: UInt16 = 0x0D
        let quote: UInt16 = 0x22
        let backslash: UInt16 = 0x5C
        let openBrace: UInt16 = 0x7B
        let closeBrace: UInt16 = 0x7D
        let openBracket: UInt16 = 0x5B
        let closeBracket: UInt16 = 0x5D
        let comma: UInt16 = 0x2C
        let colon: UInt16 = 0x3A

        var nodes: [Node] = []
        var lineNode: [Int32] = []
        var stack: [OpenFrame] = []

        // 当前行截至目前"确定"的节点下标；nil 表示尚未确定（会在行尾退化为
        // 当时栈顶容器的节点）。一旦确定，同一行内后续字符不会改写它。
        var resolvedNodeForCurrentLine: Int32? = nil
        // 下一个即将出现的"值位置"应挂在哪个节点下（key 冒号之后 / array 元素
        // 起始之后）；只在紧邻的下一个 `{`/`[` 用得上，用完即清空。
        var pendingValueNode: Int32? = nil
        // 当前行已经处理过的字符数（不含终止的换行符本身）；用于判定"空行"。
        var lineLength = 0
        // 最近一个非空白字符（跳过空格/制表/回车/换行）；用于区分"空容器内部
        // 的空行"（紧跟在 `{`/`[` 之后，不是记录分隔符）与"JSONLines 记录分隔符"。
        var lastNonWhitespaceUnit: UInt16 = 0

        var inString = false
        var escapeNext = false
        var stringUnits: [UInt16] = []

        func appendNode(parent: Int32, segment: JSONPathSegment) -> Int32 {
            nodes.append(Node(parent: parent, segment: segment))
            return Int32(nodes.count - 1)
        }

        func hexDigit(_ u: UInt16) -> Int? {
            switch u {
            case 0x30...0x39: return Int(u - 0x30)
            case 0x41...0x46: return Int(u - 0x41 + 10)
            case 0x61...0x66: return Int(u - 0x61 + 10)
            default: return nil
            }
        }

        func hex4(_ start: Int) -> UInt16? {
            var value: UInt16 = 0
            for offset in 0..<4 {
                guard let digit = hexDigit(units[start + offset]) else { return nil }
                value = value * 16 + UInt16(digit)
            }
            return value
        }

        var i = 0
        while i < length {
            let c = units[i]

            // 1) array 元素起始预检（仅在栈顶为 array 且正等待元素起始时生效）。
            if !inString,
               let topIdx = stack.indices.last,
               stack[topIdx].kind == .array,
               stack[topIdx].awaitingElementStart,
               c != space, c != tab, c != cr, c != newline,
               c != closeBrace, c != closeBracket {
                let elementNode = appendNode(
                    parent: stack[topIdx].nodeIndex,
                    segment: .index(stack[topIdx].nextIndex)
                )
                if resolvedNodeForCurrentLine == nil {
                    resolvedNodeForCurrentLine = elementNode
                }
                pendingValueNode = elementNode
                stack[topIdx].awaitingElementStart = false
            }

            // 2) 主分派。
            if inString {
                if escapeNext {
                    escapeNext = false
                    switch c {
                    case quote: stringUnits.append(quote)
                    case backslash: stringUnits.append(backslash)
                    case 0x2F: stringUnits.append(0x2F) // '/'
                    case 0x6E: stringUnits.append(newline) // 'n'
                    case 0x74: stringUnits.append(tab) // 't'
                    case 0x72: stringUnits.append(cr) // 'r'
                    case 0x62: stringUnits.append(0x08) // 'b'
                    case 0x66: stringUnits.append(0x0C) // 'f'
                    case 0x75: // 'u'
                        if i + 4 < length, let value = hex4(i + 1) {
                            stringUnits.append(value)
                            i += 4
                        }
                    default:
                        stringUnits.append(c)
                    }
                } else if c == backslash {
                    escapeNext = true
                } else if c == quote {
                    inString = false
                    let content = String(decoding: stringUnits, as: UTF16.self)
                    stringUnits = []

                    var k = i + 1
                    while k < length, units[k] == space || units[k] == tab {
                        k += 1
                    }
                    if k < length, units[k] == colon {
                        let parentIdx = stack.last?.nodeIndex ?? -1
                        let keyNode = appendNode(parent: parentIdx, segment: .key(content))
                        if resolvedNodeForCurrentLine == nil {
                            resolvedNodeForCurrentLine = keyNode
                        }
                        pendingValueNode = keyNode
                    }
                } else {
                    stringUnits.append(c)
                }
            } else {
                switch c {
                case quote:
                    inString = true
                    stringUnits = []
                case openBrace:
                    let frameNode: Int32 = stack.isEmpty ? -1 : (pendingValueNode ?? stack[stack.count - 1].nodeIndex)
                    pendingValueNode = nil
                    stack.append(OpenFrame(kind: .object, nodeIndex: frameNode))
                case openBracket:
                    let frameNode: Int32 = stack.isEmpty ? -1 : (pendingValueNode ?? stack[stack.count - 1].nodeIndex)
                    pendingValueNode = nil
                    stack.append(OpenFrame(kind: .array, nodeIndex: frameNode, nextIndex: 0, awaitingElementStart: true))
                case closeBrace:
                    if let top = stack.last, top.kind == .object {
                        stack.removeLast()
                        pendingValueNode = nil
                        if resolvedNodeForCurrentLine == nil {
                            resolvedNodeForCurrentLine = top.nodeIndex
                        }
                    }
                case closeBracket:
                    if let top = stack.last, top.kind == .array {
                        stack.removeLast()
                        pendingValueNode = nil
                        if resolvedNodeForCurrentLine == nil {
                            resolvedNodeForCurrentLine = top.nodeIndex
                        }
                    }
                case comma:
                    if let topIdx = stack.indices.last, stack[topIdx].kind == .array {
                        stack[topIdx].nextIndex += 1
                        stack[topIdx].awaitingElementStart = true
                    }
                default:
                    break
                }
            }

            // 3) 行边界（无论是否在字符串内都统一处理，与 JSONFoldMap 一致）。
            if c == newline {
                // 空行硬边界：JSONLines 的记录分隔符是零字符的空行，但空容器
                // （`{\n\n}` / `[\n\n]`）跨行展开时内部同样会出现零字符的空行——
                // 这种情况紧跟在 `{`/`[` 之后，不是记录边界，不能清栈，否则会
                // 丢失该空容器所在的祖先路径前缀。只有当空行之前最近的非空白
                // 字符不是 `{`/`[`（即某条记录的结尾 `}`/`]`，或坏行中断处的
                // 其它字符）时，才判定为真正的记录分隔符并清栈。
                let isEmptyContainerInterior = lastNonWhitespaceUnit == openBrace || lastNonWhitespaceUnit == openBracket
                if lineLength == 0, !stack.isEmpty, !isEmptyContainerInterior {
                    stack.removeAll()
                    pendingValueNode = nil
                }
                lineNode.append(resolvedNodeForCurrentLine ?? (stack.last?.nodeIndex ?? -1))
                resolvedNodeForCurrentLine = nil
                lineLength = 0
            } else {
                lineLength += 1
            }

            if c != space, c != tab, c != cr, c != newline {
                lastNonWhitespaceUnit = c
            }

            i += 1
        }

        // 收尾：文本未以 "\n" 结尾时，最后一行同样需要落地（同一条空容器判据）。
        let isTrailingEmptyContainerInterior = lastNonWhitespaceUnit == openBrace || lastNonWhitespaceUnit == openBracket
        if lineLength == 0, !stack.isEmpty, !isTrailingEmptyContainerInterior {
            stack.removeAll()
        }
        lineNode.append(resolvedNodeForCurrentLine ?? (stack.last?.nodeIndex ?? -1))

        return JSONPathMap(nodes: nodes, lineNode: lineNode)
    }

    // MARK: - path

    /// 0-based 行号查路径：取 lineNode[line]，沿 parent 回溯到 -1，反转得根→叶顺序。
    /// 越界（负数或 >= lineNode.count）返回空数组。
    func path(line: Int) -> [JSONPathSegment] {
        guard line >= 0, line < lineNode.count else { return [] }

        var segments: [JSONPathSegment] = []
        var idx = lineNode[line]
        while idx >= 0 {
            let node = nodes[Int(idx)]
            segments.append(node.segment)
            idx = node.parent
        }
        return segments.reversed()
    }

    // MARK: - jqExpression

    /// 序列化为 jq 可直接执行的路径表达式。key 转义全部走 jq/JSON 自身合法的
    /// 字符串转义（含单引号 → `'`），因此产出的表达式在任何粘贴上下文
    /// （shell 单引号、.jq 脚本文件、双引号）里都是同一份合法字面量，不依赖
    /// shell 拼接技巧；同时不含裸单引号可读性更好，适合直接显示在状态栏上。
    static func jqExpression(_ path: [JSONPathSegment]) -> String {
        guard !path.isEmpty else { return "." }

        var result = ""
        for (offset, segment) in path.enumerated() {
            switch segment {
            case .key(let k):
                result += formatKeySegment(k)
            case .index(let i):
                if offset == 0 {
                    result += ".[\(i)]"
                } else {
                    result += "[\(i)]"
                }
            }
        }
        return result
    }

    private static func formatKeySegment(_ key: String) -> String {
        if isIdentifierKey(key) {
            return "." + key
        }
        return ".\"" + escapeKeyForJQ(key) + "\""
    }

    private static func isIdentifierKey(_ key: String) -> Bool {
        var isFirst = true
        for scalar in key.unicodeScalars {
            let isAlpha = (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
            let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
            let isUnderscore = scalar.value == 0x5F
            if isFirst {
                guard isAlpha || isUnderscore else { return false }
            } else {
                guard isAlpha || isDigit || isUnderscore else { return false }
            }
            isFirst = false
        }
        return !isFirst
    }

    private static func escapeKeyForJQ(_ key: String) -> String {
        var out = ""
        for scalar in key.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "'": out += "\\u0027"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    // MARK: - dotPath

    /// 序列化为点分形态（lodash / 日常记法）。
    static func dotPath(_ path: [JSONPathSegment]) -> String {
        path.map { segment -> String in
            switch segment {
            case .key(let k): return k
            case .index(let i): return String(i)
            }
        }.joined(separator: ".")
    }

    // MARK: - truncatedForDisplay

    /// 状态栏路径文案的中段截断：文本按 `Character`（extended grapheme cluster）计数
    /// 不超过 `limit` 时原样返回；超过时保留首尾各 `(limit - 4) / 2` 个字符、中段替换
    /// 为一个省略号 "…"。切片按 `Character` 而非 UTF-16 code unit 进行——UTF-16 计数
    /// 会把占多个 UTF-16 单元的字形（超出 BMP 的 CJK 扩展字符、emoji 等）从中间切开，
    /// 产生不成对的 surrogate / 断裂字形；`Array(text)` + `Character` 切片永远落在
    /// 字形边界上。limit 过小（保留长度算出 <= 0）时退化为只返回省略号本身。
    static func truncatedForDisplay(_ text: String, limit: Int) -> String {
        let characters = Array(text)
        guard characters.count > limit else { return text }

        let keepEach = max(0, (limit - 4) / 2)
        guard keepEach > 0 else { return "…" }

        let head = String(characters.prefix(keepEach))
        let tail = String(characters.suffix(keepEach))
        return head + "…" + tail
    }
}
