import Foundation
import PeekyCore

/// JSON / JSONL 视图的折叠与路径状态：复用 app 的 JSONFoldMap / JSONFoldComposer / JSONPathMap。
///
/// 「显示行」是折叠后屏幕上的行，「源行」是格式化文本里的行；行号、jq 路径、坏行标记都按源行算。
package struct JSONView: Equatable, Sendable {
    package let foldMap: JSONFoldMap
    /// 结构解析失败的 JSON 不建路径索引，不显示推测路径。
    package let pathMap: JSONPathMap?
    package let invalidSourceLines: Set<Int>
    package private(set) var collapsed: Set<Int> = []
    private var composition: FoldComposition?
    /// 有折叠时的显示文本；没有折叠时为 nil（显示行即源行）。
    package private(set) var visibleStore: LineStore?

    package init(prettyText: String, structureIsValid: Bool, invalidSourceLines: Set<Int> = []) {
        self.foldMap = structureIsValid ? JSONFoldMap.build(prettyText: prettyText) : .empty
        self.pathMap = structureIsValid ? JSONPathMap.build(prettyText: prettyText) : nil
        self.invalidSourceLines = invalidSourceLines
    }

    package func sourceLine(forDisplayLine line: Int) -> Int {
        guard let mapping = composition?.visibleLineToSourceLine, !mapping.isEmpty else { return line }
        return mapping[min(max(line, 0), mapping.count - 1)]
    }

    /// 源行所在的显示行：被折叠的源行落到包含它的折叠行上。
    package func displayLine(forSourceLine line: Int) -> Int {
        guard let mapping = composition?.visibleLineToSourceLine, !mapping.isEmpty else { return line }
        var low = 0
        var high = mapping.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if mapping[middle] <= line { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// 以该源行开头的折叠区域（对象或数组）。
    package func region(openingAt sourceLine: Int) -> FoldRegion? {
        foldMap.regions.first { $0.openLine == sourceLine }
    }

    /// 折叠后可见文本里的一段换回源文本：落在折叠占位上的部分展开成被折起来的完整内容。
    package func expandedText(visibleRange: NSRange, sourceText: String) -> String {
        guard let composition else { return (sourceText as NSString).substring(with: visibleRange) }
        let range = JSONFoldComposer.sourceRange(forVisible: visibleRange, in: composition)
        return (sourceText as NSString).substring(with: range)
    }

    package func isCollapsed(sourceLine: Int) -> Bool {
        collapsed.contains(sourceLine)
    }

    /// 切换以该源行开头的区域的折叠状态；该行不是区域开头时返回 false。
    package mutating func toggle(sourceLine: Int, sourceText: String) -> Bool {
        guard region(openingAt: sourceLine) != nil else { return false }
        if collapsed.contains(sourceLine) {
            collapsed.remove(sourceLine)
        } else {
            collapsed.insert(sourceLine)
        }
        recompose(sourceText: sourceText)
        return true
    }

    /// 折叠根以外的全部区域。
    package mutating func collapseAll(sourceText: String) {
        let rootLines = Set(foldMap.regions.filter { region in
            !foldMap.regions.contains { $0.openLine < region.openLine && $0.closeLine > region.closeLine }
        }.map(\.openLine))
        collapsed = Set(foldMap.regions.map(\.openLine)).subtracting(rootLines)
        recompose(sourceText: sourceText)
    }

    package mutating func expandAll() {
        collapsed = []
        composition = nil
        visibleStore = nil
    }

    /// 源行的 jq 表达式与点分路径；没有路径索引时为 nil。
    package func paths(forSourceLine line: Int) -> (jq: String, dot: String)? {
        guard let pathMap else { return nil }
        let path = pathMap.path(line: line)
        return (JSONPathMap.jqExpression(path), JSONPathMap.dotPath(path))
    }

    private mutating func recompose(sourceText: String) {
        guard !collapsed.isEmpty else {
            expandAll()
            return
        }
        let composed = JSONFoldComposer.compose(sourceText: sourceText, foldMap: foldMap, collapsed: collapsed)
        composition = composed
        visibleStore = LineStore(composed.visibleText)
    }
}
