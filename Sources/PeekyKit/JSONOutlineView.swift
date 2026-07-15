import AppKit
import Foundation

/// JSON/JSONL 树视图：view-based NSOutlineView 封装（自带 NSScrollView 容器）。
/// 数据源 = JSONTreeIndex（节点表）+ 原文 String，item 惰性物化：
/// - 节点下标 <100 个子节点：每个子节点各自一个 item，展开时才用
///   `JSONTreeIndex.children(of:)` 物化（O(childCount)，只在首次展开该节点时付一次代价）。
/// - 节点下标 >100 个子节点：子层先呈现虚拟桶节点 `[0…99]` / `[100…199]` ...
///   （桶边界只需 childCount，O(1) 即可定义，不触碰 children(of:)）；桶本身展开才
///   物化桶内的真实子项，保证展开万级/百万级数组恒定成本，不会一次性拉平全部子节点。
/// item 按节点下标/桶键缓存复用（同一节点或同一桶重复请求返回同一 AnyObject 实例），
/// 满足 NSOutlineView 展开态追踪对身份稳定性的依赖（对齐 FileTreeView.Node 的既有写法）。
///
/// 层级仅由系统缩进 + disclosure 三角表达，不额外绘制缩进竖线。
final class JSONOutlineView: NSView {
    /// 子节点数超过该阈值时按此粒度分桶（Chrome DevTools 风格）。
    private static let bucketSize = 100
    /// 单元格值文本的物化上限（字符数）：避免某个值本身是几百 KB/MB 的字符串时，
    /// 仅为显示可视的几十个字符就物化 + 布局整段文本。真正的单行省略号截断仍由
    /// NSTextField 的 lineBreakMode 负责，这里只是给"物化多少字符"设一个安全上限。
    private static let maxValueLength = 500
    private static let rowHeight: CGFloat = 20
    private static let monospaceFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("JSONOutlineRow")

    /// item 内容：真实节点，或某个父节点子层里的一段虚拟分桶范围。
    private final class Item {
        enum Content {
            case node(Int)
            case bucket(parent: Int, range: Range<Int>)
        }

        let content: Content
        /// 数组元素 / JSONL 顶层记录的展示序号（无 key 时用作行前缀）；
        /// object 成员或已知有 keyRange 的节点不使用此字段。
        var displayIndex: Int?

        init(_ content: Content) {
            self.content = content
        }
    }

    private struct BucketKey: Hashable {
        let parent: Int
        let start: Int
    }

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()

    private var treeIndex = JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil)
    private var sourceText = ""
    private var kind: FileKind = .json

    /// 节点下标全局唯一（前序节点表），跨 JSON/JSONL 一套缓存即可。
    private var nodeItemCache: [Int: Item] = [:]
    private var bucketItemCache: [BucketKey: Item] = [:]
    /// 父节点下标 → 物化后的直接子节点下标数组；首次需要时才计算并缓存。
    private var childIndexCache: [Int: [Int]] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = Self.rowHeight
        outlineView.intercellSpacing = NSSize(width: 4, height: 0)
        outlineView.indentationPerLevel = 14
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.backgroundColor = .textBackgroundColor
        outlineView.gridStyleMask = []
        outlineView.focusRingType = .none
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = outlineView

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - 公开接口

    /// 加载新内容：重置展开态与全部 item/子节点缓存，从根节点重新呈现。
    func setContent(index: JSONTreeIndex, text: String, kind: FileKind) {
        treeIndex = index
        sourceText = text
        self.kind = kind
        nodeItemCache.removeAll()
        bucketItemCache.removeAll()
        childIndexCache.removeAll()
        outlineView.reloadData()
    }

    /// 释放内容（切走 JSON/JSONL tab 时调用），避免大文档的索引/原文常驻在视图缓存里。
    func reset() {
        setContent(index: JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil), text: "", kind: .json)
    }

    // MARK: - 子节点物化

    private func materializedChildren(of nodeIndex: Int) -> [Int] {
        if let cached = childIndexCache[nodeIndex] {
            return cached
        }
        let children = treeIndex.children(of: nodeIndex)
        childIndexCache[nodeIndex] = children
        return children
    }

    private func itemForNode(_ nodeIndex: Int, displayIndex: Int? = nil) -> Item {
        if let cached = nodeItemCache[nodeIndex] {
            return cached
        }
        let item = Item(.node(nodeIndex))
        item.displayIndex = displayIndex
        nodeItemCache[nodeIndex] = item
        return item
    }

    private func bucketItem(parent: Int, range: Range<Int>) -> Item {
        let key = BucketKey(parent: parent, start: range.lowerBound)
        if let cached = bucketItemCache[key] {
            return cached
        }
        let item = Item(.bucket(parent: parent, range: range))
        bucketItemCache[key] = item
        return item
    }

    private func rootItem(at position: Int) -> Item {
        let nodeIndex = treeIndex.rootIndices[position]
        // JSON 单文档只有一个根，不需要编号；JSONL 每行一条记录，用行位置编号。
        return itemForNode(nodeIndex, displayIndex: kind == .jsonl ? position : nil)
    }

    /// 数组元素在父节点子层里的位置，用作无 key 时的展示序号；object 成员一律走
    /// keyRange 解出的真实 key，不使用位置编号。
    private func arrayDisplayIndex(parent: Int, position: Int) -> Int? {
        guard treeIndex.nodes.indices.contains(parent) else { return nil }
        return treeIndex.nodes[parent].type == .array ? position : nil
    }

    // MARK: - 文本呈现

    private func rowText(for item: Item, isExpanded: Bool) -> NSAttributedString {
        switch item.content {
        case .bucket(_, let range):
            return plain("[\(range.lowerBound)\u{2026}\(range.upperBound - 1)]", color: .tertiaryLabelColor)
        case .node(let nodeIndex):
            guard treeIndex.nodes.indices.contains(nodeIndex) else {
                return NSAttributedString(string: "")
            }
            let node = treeIndex.nodes[nodeIndex]
            if node.isInvalid {
                return invalidRowText(item: item, nodeIndex: nodeIndex)
            }
            return validRowText(item: item, nodeIndex: nodeIndex, node: node, isExpanded: isExpanded)
        }
    }

    /// JSONL 坏行：整行红系色 + 原文摘要（截断），前缀带记录序号方便对照原始行。
    private func invalidRowText(item: Item, nodeIndex: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let displayIndex = item.displayIndex {
            result.append(plain("\(displayIndex): ", color: .systemRed))
        }
        let raw = sanitizeSingleLine(boundedRawValue(at: nodeIndex))
        result.append(plain(raw, color: .systemRed))
        return result
    }

    private func validRowText(item: Item, nodeIndex: Int, node: JSONTreeIndex.Node, isExpanded: Bool) -> NSAttributedString {
        let key = keyLabel(for: item, nodeIndex: nodeIndex)
        let result = NSMutableAttributedString()

        switch node.type {
        case .object, .array:
            if isExpanded {
                // 展开后该行只显示 key（或索引）；子内容已由子行呈现。无 key 的根容器
                // 退化显示裸括号，避免完全空白的行。
                let label = key ?? (node.type == .object ? "{}" : "[]")
                result.append(plain(label, color: .secondaryLabelColor))
            } else {
                if let key {
                    result.append(plain("\(key): ", color: .secondaryLabelColor))
                }
                let bracket = node.type == .object ? "{\u{2026}}" : "[\u{2026}]"
                let unit = node.type == .object ? "keys" : "items"
                result.append(plain("\(bracket) \(node.childCount) \(unit)", color: .tertiaryLabelColor))
            }
        default:
            if let key {
                result.append(plain("\(key): ", color: .secondaryLabelColor))
            }
            let raw = sanitizeSingleLine(boundedRawValue(at: nodeIndex))
            result.append(plain(raw, color: valueColor(for: node.type)))
        }

        return result
    }

    private func keyLabel(for item: Item, nodeIndex: Int) -> String? {
        if let key = treeIndex.key(at: nodeIndex, in: sourceText) {
            return key
        }
        if let displayIndex = item.displayIndex {
            return String(displayIndex)
        }
        return nil
    }

    private func valueColor(for type: JSONTreeIndex.NodeType) -> NSColor {
        switch type {
        case .string:
            return .systemGreen
        case .number:
            return .systemMint
        case .bool:
            return .systemBlue
        case .null:
            return .systemIndigo
        case .object, .array, .invalid:
            return .labelColor
        }
    }

    private func plain(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Self.monospaceFont,
            .foregroundColor: color
        ])
    }

    /// 从原文按节点的 valueRange 取值，物化长度上限为 maxValueLength：直接在原文
    /// String.Index 上做有界前移（O(maxValueLength)），不对整段 valueRange 做
    /// 无界 substring（避免某个值本身是几百 KB/MB 字符串时的整段拷贝）。
    private func boundedRawValue(at nodeIndex: Int) -> String {
        guard treeIndex.nodes.indices.contains(nodeIndex) else { return "" }
        let range = treeIndex.nodes[nodeIndex].valueRange

        guard
            let cutIndex = sourceText.index(range.lowerBound, offsetBy: Self.maxValueLength, limitedBy: range.upperBound),
            cutIndex < range.upperBound
        else {
            return String(sourceText[range])
        }
        return String(sourceText[range.lowerBound..<cutIndex]) + "\u{2026}"
    }

    /// 把已物化的短文本里的真实换行/回车/制表符转成可见转义，保证 cell 恒为单行
    /// （lineBreakMode = .byTruncatingTail 只处理超宽截断，真实控制字符仍会强制断行）。
    private func sanitizeSingleLine(_ text: String) -> String {
        guard text.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) else {
            return text
        }

        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

extension JSONOutlineView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else {
            return treeIndex.rootIndices.count
        }
        guard let jsonItem = item as? Item else { return 0 }

        switch jsonItem.content {
        case .node(let nodeIndex):
            guard treeIndex.nodes.indices.contains(nodeIndex) else { return 0 }
            let childCount = treeIndex.nodes[nodeIndex].childCount
            guard childCount > 0 else { return 0 }
            guard childCount > Self.bucketSize else { return childCount }
            return (childCount + Self.bucketSize - 1) / Self.bucketSize
        case .bucket(_, let range):
            return range.count
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else {
            return rootItem(at: index)
        }
        guard let jsonItem = item as? Item else {
            return Item(.node(-1))
        }

        switch jsonItem.content {
        case .node(let nodeIndex):
            let childCount = treeIndex.nodes.indices.contains(nodeIndex) ? treeIndex.nodes[nodeIndex].childCount : 0
            if childCount > Self.bucketSize {
                let start = index * Self.bucketSize
                let end = min(start + Self.bucketSize, childCount)
                return bucketItem(parent: nodeIndex, range: start..<end)
            }
            let children = materializedChildren(of: nodeIndex)
            let childNodeIndex = children[index]
            return itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: nodeIndex, position: index))
        case .bucket(let parent, let range):
            let children = materializedChildren(of: parent)
            let position = range.lowerBound + index
            let childNodeIndex = children[position]
            return itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: parent, position: position))
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let jsonItem = item as? Item else { return false }

        switch jsonItem.content {
        case .node(let nodeIndex):
            guard treeIndex.nodes.indices.contains(nodeIndex) else { return false }
            return treeIndex.nodes[nodeIndex].childCount > 0
        case .bucket(_, let range):
            return !range.isEmpty
        }
    }
}

extension JSONOutlineView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let jsonItem = item as? Item else { return nil }

        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = Self.cellIdentifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.attributedStringValue = rowText(for: jsonItem, isExpanded: outlineView.isItemExpanded(item))
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        true
    }

    /// 容器行展开/折叠后自身呈现会变（"key: {…} N keys" ⇄ "key"），显式刷新该行；
    /// 子行的增删由展开/折叠操作本身负责，这里不重载 children。
    func outlineViewItemDidExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] {
            outlineView.reloadItem(item)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] {
            outlineView.reloadItem(item)
        }
    }
}
