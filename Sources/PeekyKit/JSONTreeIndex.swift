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
        if kind == .jsonl {
            return buildJSONL(text: text)
        }
        return buildJSONDocument(text: text)
    }

    /// 直接子节点下标（按文档顺序）；标量节点为空数组
    func children(of nodeIndex: Int) -> [Int] {
        guard nodes.indices.contains(nodeIndex) else { return [] }

        var result: [Int] = []
        var current = nodes[nodeIndex].firstChild
        while let index = current {
            result.append(index)
            current = nodes[index].nextSibling
        }
        return result
    }

    /// 解码后的成员 key（去引号、解 JSON 转义）；无 key 的节点返回 nil
    func key(at nodeIndex: Int, in text: String) -> String? {
        guard nodes.indices.contains(nodeIndex), let range = nodes[nodeIndex].keyRange else {
            return nil
        }
        return JSONTreeIndex.decodeJSONStringLiteral(text[range])
    }

    /// 值的原文切片（string 含引号，容器含括号，invalid 行为整行原文）
    func rawValue(at nodeIndex: Int, in text: String) -> String {
        guard nodes.indices.contains(nodeIndex) else { return "" }
        return String(text[nodes[nodeIndex].valueRange])
    }

    // MARK: - JSON 单文档扫描

    private static func buildJSONDocument(text: String) -> JSONTreeIndex {
        var idx = text.startIndex
        var scanner = JSONScanner(text: text)
        scanner.skipWhitespace(&idx)

        guard idx < text.utf8.endIndex else {
            return JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil)
        }

        guard let (rootIndex, afterValue) = scanner.parseValue(at: idx, depth: 1) else {
            return JSONTreeIndex(
                nodes: scanner.nodes,
                rootIndices: scanner.nodes.isEmpty ? [] : [0],
                errorIndex: scanner.errorIndex ?? idx
            )
        }

        var trailingIdx = afterValue
        scanner.skipWhitespace(&trailingIdx)

        if trailingIdx != text.utf8.endIndex {
            return JSONTreeIndex(
                nodes: scanner.nodes,
                rootIndices: [rootIndex],
                errorIndex: trailingIdx
            )
        }

        return JSONTreeIndex(nodes: scanner.nodes, rootIndices: [rootIndex], errorIndex: nil)
    }

    // MARK: - JSONL 逐行扫描

    private static func buildJSONL(text: String) -> JSONTreeIndex {
        var nodes: [Node] = []
        var rootIndices: [Int] = []

        var lineStart = text.startIndex
        let end = text.endIndex

        while lineStart < end {
            var lineEnd = lineStart
            while lineEnd < end, text.utf8[lineEnd] != JSONScanner.newline {
                lineEnd = text.utf8.index(after: lineEnd)
            }

            var contentEnd = lineEnd
            if contentEnd > lineStart {
                let beforeEnd = text.utf8.index(before: contentEnd)
                if text.utf8[beforeEnd] == JSONScanner.cr {
                    contentEnd = beforeEnd
                }
            }

            let rawLineRange = lineStart..<contentEnd

            var scanStart = lineStart
            var scanner = JSONScanner(text: text)
            scanner.skipWhitespace(&scanStart)

            var trimmedEnd = contentEnd
            while trimmedEnd > scanStart {
                let beforeEnd = text.utf8.index(before: trimmedEnd)
                let byte = text.utf8[beforeEnd]
                if byte == JSONScanner.space || byte == JSONScanner.tab || byte == JSONScanner.cr {
                    trimmedEnd = beforeEnd
                } else {
                    break
                }
            }

            if scanStart < trimmedEnd {
                if let (nodeIndex, afterValue) = scanner.parseValue(at: scanStart, depth: 1),
                   afterValue == trimmedEnd {
                    let baseOffset = nodes.count
                    for node in scanner.nodes {
                        var adjusted = node
                        if let firstChild = node.firstChild {
                            adjusted.firstChild = firstChild + baseOffset
                        }
                        if let nextSibling = node.nextSibling {
                            adjusted.nextSibling = nextSibling + baseOffset
                        }
                        nodes.append(adjusted)
                    }
                    rootIndices.append(baseOffset + nodeIndex)
                } else {
                    nodes.append(
                        Node(
                            type: .invalid,
                            keyRange: nil,
                            valueRange: rawLineRange,
                            childCount: 0,
                            firstChild: nil,
                            nextSibling: nil,
                            isInvalid: true,
                            isTruncated: false
                        )
                    )
                    rootIndices.append(nodes.count - 1)
                }
            }

            lineStart = lineEnd < end ? text.utf8.index(after: lineEnd) : end
        }

        return JSONTreeIndex(nodes: nodes, rootIndices: rootIndices, errorIndex: nil)
    }

    // MARK: - key 转义解码

    private static func decodeJSONStringLiteral(_ raw: Substring) -> String {
        let scalars = Array(raw.unicodeScalars)
        guard scalars.count >= 2 else { return "" }

        var result = ""
        result.reserveCapacity(scalars.count)

        var i = 1
        let end = scalars.count - 1

        while i < end {
            let scalar = scalars[i]
            if scalar == "\\", i + 1 < end {
                let next = scalars[i + 1]
                switch next {
                case "\"":
                    result.unicodeScalars.append("\"")
                    i += 2
                case "\\":
                    result.unicodeScalars.append("\\")
                    i += 2
                case "/":
                    result.unicodeScalars.append("/")
                    i += 2
                case "b":
                    result.unicodeScalars.append(Unicode.Scalar(0x08))
                    i += 2
                case "f":
                    result.unicodeScalars.append(Unicode.Scalar(0x0C))
                    i += 2
                case "n":
                    result.unicodeScalars.append("\n")
                    i += 2
                case "r":
                    result.unicodeScalars.append("\r")
                    i += 2
                case "t":
                    result.unicodeScalars.append("\t")
                    i += 2
                case "u":
                    if let (decoded, consumed) = decodeUnicodeEscape(scalars, at: i + 2, end: end) {
                        result.unicodeScalars.append(decoded)
                        i += 2 + consumed
                    } else {
                        result.unicodeScalars.append(scalar)
                        i += 1
                    }
                default:
                    result.unicodeScalars.append(next)
                    i += 2
                }
            } else {
                result.unicodeScalars.append(scalar)
                i += 1
            }
        }

        return result
    }

    private static func decodeUnicodeEscape(
        _ scalars: [Unicode.Scalar],
        at start: Int,
        end: Int
    ) -> (Unicode.Scalar, Int)? {
        guard let first = readHex4(scalars, at: start, end: end) else { return nil }

        if first >= 0xD800, first <= 0xDBFF {
            let nextEscapeStart = start + 4
            if nextEscapeStart + 1 < end,
               scalars[nextEscapeStart] == "\\", scalars[nextEscapeStart + 1] == "u",
               let second = readHex4(scalars, at: nextEscapeStart + 2, end: end),
               second >= 0xDC00, second <= 0xDFFF {
                let combined = 0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00)
                if let scalar = Unicode.Scalar(combined) {
                    return (scalar, 4 + 6)
                }
            }
            return (Unicode.Scalar(0xFFFD)!, 4)
        }

        if first >= 0xDC00, first <= 0xDFFF {
            return (Unicode.Scalar(0xFFFD)!, 4)
        }

        guard let scalar = Unicode.Scalar(first) else {
            return (Unicode.Scalar(0xFFFD)!, 4)
        }
        return (scalar, 4)
    }

    private static func readHex4(_ scalars: [Unicode.Scalar], at start: Int, end: Int) -> UInt32? {
        guard start >= 0, start + 4 <= end else { return nil }

        var value: UInt32 = 0
        for offset in 0..<4 {
            guard let digit = hexDigitValue(scalars[start + offset]) else { return nil }
            value = (value << 4) | digit
        }
        return value
    }

    private static func hexDigitValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39:
            return scalar.value - 0x30
        case 0x41...0x46:
            return scalar.value - 0x41 + 10
        case 0x61...0x66:
            return scalar.value - 0x61 + 10
        default:
            return nil
        }
    }

    /// 单遍手写扫描器：不依赖 JSONSerialization，值不物化，仅记录 Range。
    /// 每个实例对应一次独立的顶层值解析（JSON 单文档一次；JSONL 每行一次）。
    private struct JSONScanner {
        static let maxDepth = 512

        static let quote: UInt8 = 0x22
        static let backslash: UInt8 = 0x5C
        static let openBrace: UInt8 = 0x7B
        static let closeBrace: UInt8 = 0x7D
        static let openBracket: UInt8 = 0x5B
        static let closeBracket: UInt8 = 0x5D
        static let colon: UInt8 = 0x3A
        static let comma: UInt8 = 0x2C
        static let space: UInt8 = 0x20
        static let tab: UInt8 = 0x09
        static let newline: UInt8 = 0x0A
        static let cr: UInt8 = 0x0D
        static let minus: UInt8 = 0x2D
        static let plus: UInt8 = 0x2B
        static let dot: UInt8 = 0x2E
        static let zero: UInt8 = 0x30
        static let nine: UInt8 = 0x39
        static let eLower: UInt8 = 0x65
        static let eUpper: UInt8 = 0x45
        static let tChar: UInt8 = 0x74
        static let fChar: UInt8 = 0x66
        static let nChar: UInt8 = 0x6E
        static let trueLiteral: [UInt8] = Array("true".utf8)
        static let falseLiteral: [UInt8] = Array("false".utf8)
        static let nullLiteral: [UInt8] = Array("null".utf8)

        static func isDigit(_ byte: UInt8) -> Bool {
            byte >= zero && byte <= nine
        }

        /// 未闭合容器的解析帧：显式堆栈代替原生递归，避免深嵌套（>512 截断前）
        /// 在受限线程栈（如并发测试执行器）上触发栈溢出。
        private struct Frame {
            var nodeIndex: Int
            var isObject: Bool
            var start: String.Index
            var childCount: Int = 0
            var firstChild: Int?
            var lastChild: Int?
            var pendingKeyRange: Range<String.Index>?
            var needsKey: Bool = false
        }

        let text: String
        var nodes: [Node] = []
        var errorIndex: String.Index?

        init(text: String) {
            self.text = text
        }

        /// 单遍解析一个完整值（容器用显式栈迭代展开，原生调用栈深度恒定）。
        mutating func parseValue(at start: String.Index, depth: Int) -> (index: Int, next: String.Index)? {
            var stack: [Frame] = []
            var idx = start

            while true {
                if !stack.isEmpty, stack[stack.count - 1].isObject, stack[stack.count - 1].needsKey {
                    let topIndex = stack.count - 1
                    skipWhitespace(&idx)

                    guard idx < text.utf8.endIndex, text.utf8[idx] == Self.quote,
                          let keyEnd = skipStringLiteral(from: idx) else {
                        return failStack(&stack, errorAt: idx)
                    }
                    let keyRange = idx..<keyEnd
                    idx = keyEnd
                    skipWhitespace(&idx)
                    guard idx < text.utf8.endIndex, text.utf8[idx] == Self.colon else {
                        return failStack(&stack, errorAt: idx)
                    }
                    idx = text.utf8.index(after: idx)
                    skipWhitespace(&idx)
                    stack[topIndex].pendingKeyRange = keyRange
                    stack[topIndex].needsKey = false
                }

                skipWhitespace(&idx)
                guard idx < text.utf8.endIndex else {
                    return failStack(&stack, errorAt: idx)
                }

                let byte = text.utf8[idx]
                var completedNodeIndex: Int

                switch byte {
                case Self.openBrace, Self.openBracket:
                    let isObject = byte == Self.openBrace
                    let containerStart = idx
                    let nodeIndex = nodes.count
                    nodes.append(
                        Node(
                            type: isObject ? .object : .array, keyRange: nil,
                            valueRange: containerStart..<containerStart, childCount: 0,
                            firstChild: nil, nextSibling: nil, isInvalid: false, isTruncated: false
                        )
                    )
                    idx = text.utf8.index(after: idx)
                    let containerDepth = depth + stack.count

                    if containerDepth > Self.maxDepth {
                        guard let bodyEnd = skipContainerBody(from: idx) else {
                            nodes[nodeIndex].valueRange = containerStart..<idx
                            return failStack(&stack, errorAt: idx)
                        }
                        nodes[nodeIndex].valueRange = containerStart..<bodyEnd
                        nodes[nodeIndex].isTruncated = true
                        idx = bodyEnd
                        completedNodeIndex = nodeIndex
                    } else {
                        skipWhitespace(&idx)
                        let closeByte: UInt8 = isObject ? Self.closeBrace : Self.closeBracket
                        if idx < text.utf8.endIndex, text.utf8[idx] == closeByte {
                            idx = text.utf8.index(after: idx)
                            nodes[nodeIndex].valueRange = containerStart..<idx
                            completedNodeIndex = nodeIndex
                        } else {
                            var frame = Frame(nodeIndex: nodeIndex, isObject: isObject, start: containerStart)
                            frame.needsKey = isObject
                            stack.append(frame)
                            continue
                        }
                    }
                case Self.quote:
                    guard let end = skipStringLiteral(from: idx) else {
                        return failStack(&stack, errorAt: idx)
                    }
                    let nodeIndex = nodes.count
                    nodes.append(
                        Node(
                            type: .string, keyRange: nil, valueRange: idx..<end, childCount: 0,
                            firstChild: nil, nextSibling: nil, isInvalid: false, isTruncated: false
                        )
                    )
                    idx = end
                    completedNodeIndex = nodeIndex
                case Self.minus, Self.zero...Self.nine:
                    guard let end = parseNumberEnd(from: idx) else {
                        return failStack(&stack, errorAt: idx)
                    }
                    let nodeIndex = nodes.count
                    nodes.append(
                        Node(
                            type: .number, keyRange: nil, valueRange: idx..<end, childCount: 0,
                            firstChild: nil, nextSibling: nil, isInvalid: false, isTruncated: false
                        )
                    )
                    idx = end
                    completedNodeIndex = nodeIndex
                case Self.tChar, Self.fChar, Self.nChar:
                    let literal: [UInt8]
                    let type: NodeType
                    if byte == Self.tChar {
                        literal = Self.trueLiteral
                        type = .bool
                    } else if byte == Self.fChar {
                        literal = Self.falseLiteral
                        type = .bool
                    } else {
                        literal = Self.nullLiteral
                        type = .null
                    }
                    guard let end = matchLiteral(from: idx, literal: literal) else {
                        return failStack(&stack, errorAt: idx)
                    }
                    let nodeIndex = nodes.count
                    nodes.append(
                        Node(
                            type: type, keyRange: nil, valueRange: idx..<end, childCount: 0,
                            firstChild: nil, nextSibling: nil, isInvalid: false, isTruncated: false
                        )
                    )
                    idx = end
                    completedNodeIndex = nodeIndex
                default:
                    return failStack(&stack, errorAt: idx)
                }

                // 把刚完成的值挂到外层容器帧；若挂载后容器随即闭合，
                // 沿栈逐级级联闭合（"]]]" 这类连续收尾），直到需要
                // 继续解析下一个成员/元素，或栈清空（整值解析完毕）。
                while true {
                    guard !stack.isEmpty else {
                        return (completedNodeIndex, idx)
                    }
                    let topIndex = stack.count - 1

                    if stack[topIndex].isObject {
                        nodes[completedNodeIndex].keyRange = stack[topIndex].pendingKeyRange
                        stack[topIndex].pendingKeyRange = nil
                    }
                    if let last = stack[topIndex].lastChild {
                        nodes[last].nextSibling = completedNodeIndex
                    } else {
                        stack[topIndex].firstChild = completedNodeIndex
                    }
                    stack[topIndex].lastChild = completedNodeIndex
                    stack[topIndex].childCount += 1

                    skipWhitespace(&idx)
                    guard idx < text.utf8.endIndex else {
                        return failStack(&stack, errorAt: idx)
                    }

                    let closeByte: UInt8 = stack[topIndex].isObject ? Self.closeBrace : Self.closeBracket
                    if text.utf8[idx] == Self.comma {
                        idx = text.utf8.index(after: idx)
                        if stack[topIndex].isObject {
                            stack[topIndex].needsKey = true
                        }
                        break
                    } else if text.utf8[idx] == closeByte {
                        idx = text.utf8.index(after: idx)
                        let frame = stack.removeLast()
                        nodes[frame.nodeIndex].valueRange = frame.start..<idx
                        nodes[frame.nodeIndex].childCount = frame.childCount
                        nodes[frame.nodeIndex].firstChild = frame.firstChild
                        completedNodeIndex = frame.nodeIndex
                        continue
                    } else {
                        return failStack(&stack, errorAt: idx)
                    }
                }
            }
        }

        private mutating func failStack(_ stack: inout [Frame], errorAt idx: String.Index) -> (index: Int, next: String.Index)? {
            for frame in stack {
                nodes[frame.nodeIndex].valueRange = frame.start..<idx
                nodes[frame.nodeIndex].childCount = frame.childCount
                nodes[frame.nodeIndex].firstChild = frame.firstChild
            }
            recordError(at: idx)
            return nil
        }

        mutating func recordError(at idx: String.Index) {
            if errorIndex == nil {
                errorIndex = idx
            }
        }

        func skipWhitespace(_ idx: inout String.Index) {
            while idx < text.utf8.endIndex {
                let byte = text.utf8[idx]
                if byte == Self.space || byte == Self.tab || byte == Self.newline || byte == Self.cr {
                    idx = text.utf8.index(after: idx)
                } else {
                    break
                }
            }
        }

        func skipStringLiteral(from start: String.Index) -> String.Index? {
            var idx = text.utf8.index(after: start)
            while idx < text.utf8.endIndex {
                let byte = text.utf8[idx]
                if byte == Self.backslash {
                    idx = text.utf8.index(after: idx)
                    guard idx < text.utf8.endIndex else { return nil }
                    idx = text.utf8.index(after: idx)
                    continue
                }
                if byte == Self.quote {
                    return text.utf8.index(after: idx)
                }
                idx = text.utf8.index(after: idx)
            }
            return nil
        }

        func skipContainerBody(from start: String.Index) -> String.Index? {
            var idx = start
            var depth = 1
            while idx < text.utf8.endIndex {
                let byte = text.utf8[idx]
                if byte == Self.quote {
                    guard let after = skipStringLiteral(from: idx) else { return nil }
                    idx = after
                    continue
                }
                if byte == Self.openBrace || byte == Self.openBracket {
                    depth += 1
                    idx = text.utf8.index(after: idx)
                    continue
                }
                if byte == Self.closeBrace || byte == Self.closeBracket {
                    depth -= 1
                    idx = text.utf8.index(after: idx)
                    if depth == 0 { return idx }
                    continue
                }
                idx = text.utf8.index(after: idx)
            }
            return nil
        }

        func parseNumberEnd(from start: String.Index) -> String.Index? {
            var idx = start
            if idx < text.utf8.endIndex, text.utf8[idx] == Self.minus {
                idx = text.utf8.index(after: idx)
            }
            guard idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) else { return nil }
            if text.utf8[idx] == Self.zero {
                idx = text.utf8.index(after: idx)
            } else {
                while idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) {
                    idx = text.utf8.index(after: idx)
                }
            }

            if idx < text.utf8.endIndex, text.utf8[idx] == Self.dot {
                idx = text.utf8.index(after: idx)
                guard idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) else { return nil }
                while idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) {
                    idx = text.utf8.index(after: idx)
                }
            }

            if idx < text.utf8.endIndex, (text.utf8[idx] == Self.eLower || text.utf8[idx] == Self.eUpper) {
                idx = text.utf8.index(after: idx)
                if idx < text.utf8.endIndex, (text.utf8[idx] == Self.plus || text.utf8[idx] == Self.minus) {
                    idx = text.utf8.index(after: idx)
                }
                guard idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) else { return nil }
                while idx < text.utf8.endIndex, Self.isDigit(text.utf8[idx]) {
                    idx = text.utf8.index(after: idx)
                }
            }

            return idx
        }

        func matchLiteral(from start: String.Index, literal: [UInt8]) -> String.Index? {
            var idx = start
            for byte in literal {
                guard idx < text.utf8.endIndex, text.utf8[idx] == byte else { return nil }
                idx = text.utf8.index(after: idx)
            }
            return idx
        }
    }
}
