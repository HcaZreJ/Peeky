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
///
/// 交互层：单击三角走系统默认 toggle；Option+点击三角递归展开/折叠子树，遇到分桶
/// 边界只揭示桶头行、不递归物化桶内容（`recursiveExpand`）；菜单/右键提供全部展开、
/// 全部折叠、折叠到第 1/2/3 层（分桶层透明不计深度，`expandToDepth`）；空格键对选中
/// 节点弹值预览 popover；底部常驻 path bar 显示选中节点 key path 并可复制。
final class JSONOutlineView: NSView {
    /// 子节点数超过该阈值时按此粒度分桶（Chrome DevTools 风格）。
    private static let bucketSize = 100
    /// 首次装载默认展开阈值：节点总数超过此值时改为展开到第 2 层而非全展开，避免
    /// 超大文档首次呈现就触发大规模物化。
    private static let defaultExpansionNodeThreshold = 20_000
    /// 单元格值文本的物化上限（字符数）：避免某个值本身是几百 KB/MB 的字符串时，
    /// 仅为显示可视的几十个字符就物化 + 布局整段文本。真正的单行省略号截断仍由
    /// NSTextField 的 lineBreakMode 负责，这里只是给"物化多少字符"设一个安全上限。
    private static let maxValueLength = 500
    /// 空格键值预览 popover 的物化上限（字节）：超出截断并注明，避免整段 MB 级字符串
    /// 一次性进 NSTextView。
    private static let popoverMaxBytes = 64 * 1024
    private static let rowHeight: CGFloat = 20
    private static let pathBarHeight: CGFloat = 24
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

    /// 选中/右键节点的 key path 片段：object 成员用真实 key，array 元素用真实下标；
    /// 分桶节点是纯展示层，不产生片段（路径透明）。
    private enum PathSegment {
        case key(String)
        case index(Int)
    }

    private let scrollView = NSScrollView()
    private let outlineView = JSONOutlineTableView()
    private let pathBar = PathBarView()
    private let contextMenu = NSMenu()

    private var treeIndex = JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil)
    private var sourceText = ""
    private var kind: FileKind = .json

    /// 节点下标全局唯一（前序节点表），跨 JSON/JSONL 一套缓存即可。
    private var nodeItemCache: [Int: Item] = [:]
    private var bucketItemCache: [BucketKey: Item] = [:]
    /// 父节点下标 → 物化后的直接子节点下标数组；首次需要时才计算并缓存。
    private var childIndexCache: [Int: [Int]] = [:]

    private var currentPathSegments: [PathSegment] = []
    private var previewPopover: NSPopover?
    private var popoverKeyMonitor: Any?

    private var copyValueMenuItem: NSMenuItem?
    private var copyKeyMenuItem: NSMenuItem?
    private var copyPathMenuItem: NSMenuItem?

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
        outlineView.onOptionClickDisclosure = { [weak self] item in
            self?.handleOptionClickDisclosure(item)
        }
        outlineView.onSpacePressed = { [weak self] in
            self?.handleSpacePressed()
        }

        setupContextMenu()
        outlineView.menu = contextMenu

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = outlineView

        pathBar.translatesAutoresizingMaskIntoConstraints = false
        pathBar.onClick = { [weak self] in
            self?.showPathMenu()
        }

        addSubview(scrollView)
        addSubview(pathBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pathBar.topAnchor),

            pathBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            pathBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            pathBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            pathBar.heightAnchor.constraint(equalToConstant: Self.pathBarHeight)
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
        updatePathBar()
    }

    /// 释放内容（切走 JSON/JSONL tab 时调用），避免大文档的索引/原文常驻在视图缓存里。
    func reset() {
        setContent(index: JSONTreeIndex(nodes: [], rootIndices: [], errorIndex: nil), text: "", kind: .json)
    }

    // MARK: - 折叠命令族

    /// 全部展开：遇到分桶边界只揭示桶头行（[0…99] 摘要），不递归物化桶内容，
    /// 防止十万级数组被一次性展平。
    func expandAll() {
        for position in treeIndex.rootIndices.indices {
            recursiveExpand(rootItem(at: position))
        }
        updatePathBar()
    }

    func collapseAll() {
        outlineView.collapseItem(nil, collapseChildren: true)
        updatePathBar()
    }

    /// 折叠到第 level 层：先全部折叠，再展开到指定深度；分桶层透明，不计入深度
    /// （子项深度 = 父节点深度 + 1，无论中间是否经过桶）。
    func collapseToLevel(_ level: Int) {
        collapseAll()
        for position in treeIndex.rootIndices.indices {
            expandToDepth(rootItem(at: position), currentDepth: 1, maxDepth: level)
        }
        updatePathBar()
    }

    /// 首次装载默认展开：节点总数 ≤ defaultExpansionNodeThreshold 时全展开（分桶边界
    /// 仍停，语义同 expandAll）；超过阈值时展开到第 2 层（语义同 collapseToLevel），
    /// 避免超大文档首次呈现就触发大规模物化。仅供 tab 首次构建出索引时调用一次；
    /// tab 切走再切回、复用已缓存索引的路径不应重复调用，否则会覆盖用户已手动
    /// 调整的展开状态。
    func applyDefaultExpansion() {
        if treeIndex.nodes.count <= Self.defaultExpansionNodeThreshold {
            expandAll()
        } else {
            collapseToLevel(2)
        }
    }

    private func isExpandableItem(_ item: Item) -> Bool {
        switch item.content {
        case .node(let nodeIndex):
            guard treeIndex.nodes.indices.contains(nodeIndex) else { return false }
            return treeIndex.nodes[nodeIndex].childCount > 0
        case .bucket(_, let range):
            return !range.isEmpty
        }
    }

    /// 递归展开：普通层级（子节点数 ≤ bucketSize）逐一递归展开真实子节点；一旦子层
    /// 因子节点数 > bucketSize 而呈现为分桶，则只展开当前节点（露出桶头行）后停止，
    /// 不进一步展开各个桶。直接对某个已可见的桶 item 触发时（用户在桶行本身
    /// option-click），该桶内 ≤bucketSize 个真实子项数量有界，可安全递归展开。
    private func recursiveExpand(_ item: Any) {
        guard let jsonItem = item as? Item, isExpandableItem(jsonItem) else { return }
        outlineView.expandItem(item, expandChildren: false)

        switch jsonItem.content {
        case .node(let nodeIndex):
            guard treeIndex.nodes.indices.contains(nodeIndex) else { return }
            let childCount = treeIndex.nodes[nodeIndex].childCount
            guard childCount <= Self.bucketSize else { return }
            for (position, childNodeIndex) in materializedChildren(of: nodeIndex).enumerated() {
                let childItem = itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: nodeIndex, position: position))
                recursiveExpand(childItem)
            }
        case .bucket(let parent, let range):
            let children = materializedChildren(of: parent)
            for position in range {
                let childNodeIndex = children[position]
                let childItem = itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: parent, position: position))
                recursiveExpand(childItem)
            }
        }
    }

    /// 深度限定展开：分桶层透明——子项深度沿用父节点深度 + 1，不因中间的桶层而
    /// 额外 +1；只有当目标深度确实需要展示桶内内容时才展开各个桶，否则展开父节点
    /// 露出桶头行即止。
    private func expandToDepth(_ item: Any, currentDepth: Int, maxDepth: Int) {
        guard currentDepth <= maxDepth, let jsonItem = item as? Item, isExpandableItem(jsonItem) else { return }
        outlineView.expandItem(item, expandChildren: false)

        guard case .node(let nodeIndex) = jsonItem.content, treeIndex.nodes.indices.contains(nodeIndex) else { return }
        let childCount = treeIndex.nodes[nodeIndex].childCount

        guard childCount > Self.bucketSize else {
            for (position, childNodeIndex) in materializedChildren(of: nodeIndex).enumerated() {
                let childItem = itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: nodeIndex, position: position))
                expandToDepth(childItem, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            }
            return
        }

        guard currentDepth + 1 <= maxDepth else { return }

        let children = materializedChildren(of: nodeIndex)
        let bucketCount = (childCount + Self.bucketSize - 1) / Self.bucketSize
        for bucketIndex in 0..<bucketCount {
            let start = bucketIndex * Self.bucketSize
            let end = min(start + Self.bucketSize, childCount)
            let bucket = bucketItem(parent: nodeIndex, range: start..<end)
            outlineView.expandItem(bucket, expandChildren: false)
            for position in start..<end {
                let childNodeIndex = children[position]
                let childItem = itemForNode(childNodeIndex, displayIndex: arrayDisplayIndex(parent: nodeIndex, position: position))
                expandToDepth(childItem, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            }
        }
    }

    /// Option+点击 disclosure 三角：当前折叠则递归展开（分桶安全），当前展开则
    /// 递归折叠（折叠只影响已物化/已展开的状态，不产生额外物化成本）。
    private func handleOptionClickDisclosure(_ item: Any) {
        guard let jsonItem = item as? Item, isExpandableItem(jsonItem) else { return }

        if outlineView.isItemExpanded(item) {
            outlineView.collapseItem(item, collapseChildren: true)
        } else {
            recursiveExpand(item)
        }
        updatePathBar()
    }

    // MARK: - 空格预览 popover

    private func handleSpacePressed() {
        guard previewPopover == nil else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? Item,
              case .node(let nodeIndex) = item.content,
              treeIndex.nodes.indices.contains(nodeIndex)
        else {
            return
        }
        showPreviewPopover(nodeIndex: nodeIndex, row: row)
    }

    private func showPreviewPopover(nodeIndex: Int, row: Int) {
        let text = popoverText(for: nodeIndex)
        let contentSize = NSSize(width: 480, height: 320)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Self.monospaceFont
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)

        let contentScrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        contentScrollView.hasVerticalScroller = true
        contentScrollView.borderType = .noBorder
        contentScrollView.documentView = textView

        let viewController = NSViewController()
        viewController.view = contentScrollView

        let popover = NSPopover()
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.contentSize = contentSize
        popover.delegate = self

        let rowRect = outlineView.rect(ofRow: row)
        popover.show(relativeTo: rowRect, of: outlineView, preferredEdge: .maxY)
        previewPopover = popover

        popoverKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // keyCode 53 = Esc；空格再按一次同样关闭（吞掉事件，不再转发）。
            if event.keyCode == 53 || event.charactersIgnoringModifiers == " " {
                self.closePreviewPopover()
                return nil
            }
            return event
        }
    }

    private func closePreviewPopover() {
        previewPopover?.close()
    }

    /// 值全文（无行截断），超出 popoverMaxBytes 按 UTF-8 字节边界截断并注明。
    private func popoverText(for nodeIndex: Int) -> String {
        let full = treeIndex.rawValue(at: nodeIndex, in: sourceText)
        let byteLimit = Self.popoverMaxBytes
        guard full.utf8.count > byteLimit else { return full }

        var truncated = ""
        var byteCount = 0
        for scalar in full.unicodeScalars {
            let scalarByteCount = String(scalar).utf8.count
            guard byteCount + scalarByteCount <= byteLimit else { break }
            truncated.unicodeScalars.append(scalar)
            byteCount += scalarByteCount
        }

        let shown = ByteCountFormatter.string(fromByteCount: Int64(byteLimit), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(full.utf8.count), countStyle: .file)
        return truncated + "\n\n\u{2026} truncated (showing first \(shown) of \(total))"
    }

    // MARK: - Path bar / key path

    private func pathSegments(for item: Any) -> [PathSegment] {
        var segments: [PathSegment] = []
        var current: Any? = item

        while let currentItem = current as? Item {
            if let segment = pathSegment(for: currentItem) {
                segments.append(segment)
            }
            current = outlineView.parent(forItem: currentItem)
        }

        return segments.reversed()
    }

    /// 分桶节点是展示层，路径透明，不产生片段。
    private func pathSegment(for item: Item) -> PathSegment? {
        switch item.content {
        case .bucket:
            return nil
        case .node(let nodeIndex):
            if let key = treeIndex.key(at: nodeIndex, in: sourceText) {
                return .key(key)
            }
            if let displayIndex = item.displayIndex {
                return .index(displayIndex)
            }
            return nil
        }
    }

    private func dotPath(_ segments: [PathSegment]) -> String {
        var result = "$"
        appendPath(&result, segments: segments)
        return result
    }

    private func jqPath(_ segments: [PathSegment]) -> String {
        var result = "."
        appendPath(&result, segments: segments)
        return result
    }

    private func appendPath(_ result: inout String, segments: [PathSegment]) {
        for segment in segments {
            switch segment {
            case .key(let key):
                if isValidIdentifier(key) {
                    result += ".\(key)"
                } else {
                    result += "[\"\(escapeForBracket(key))\"]"
                }
            case .index(let index):
                result += "[\(index)]"
            }
        }
    }

    private func isValidIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        guard CharacterSet.letters.contains(first) || first == "_" else { return false }
        return text.unicodeScalars.dropFirst().allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
    }

    private func escapeForBracket(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func updatePathBar() {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) else {
            currentPathSegments = []
            pathBar.titleLabel.stringValue = "$"
            return
        }

        let segments = pathSegments(for: item)
        currentPathSegments = segments
        pathBar.titleLabel.stringValue = dotPath(segments)
    }

    private func showPathMenu() {
        let menu = NSMenu()

        let dotItem = NSMenuItem(
            title: "Copy Path (Dot Notation)",
            action: #selector(copyDotPathAction(_:)),
            keyEquivalent: ""
        )
        dotItem.target = self
        menu.addItem(dotItem)

        let jqItem = NSMenuItem(title: "Copy Path (jq)", action: #selector(copyJQPathAction(_:)), keyEquivalent: "")
        jqItem.target = self
        menu.addItem(jqItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathBar.bounds.height), in: pathBar)
    }

    @objc private func copyDotPathAction(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dotPath(currentPathSegments), forType: .string)
    }

    @objc private func copyJQPathAction(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jqPath(currentPathSegments), forType: .string)
    }

    // MARK: - 右键节点菜单

    private func setupContextMenu() {
        contextMenu.delegate = self

        let copyValue = NSMenuItem(title: "Copy Value", action: #selector(copyValueAction(_:)), keyEquivalent: "")
        copyValue.target = self
        contextMenu.addItem(copyValue)
        copyValueMenuItem = copyValue

        let copyKey = NSMenuItem(title: "Copy Key", action: #selector(copyKeyAction(_:)), keyEquivalent: "")
        copyKey.target = self
        contextMenu.addItem(copyKey)
        copyKeyMenuItem = copyKey

        let copyPath = NSMenuItem(title: "Copy Path", action: #selector(copyPathAction(_:)), keyEquivalent: "")
        copyPath.target = self
        contextMenu.addItem(copyPath)
        copyPathMenuItem = copyPath

        contextMenu.addItem(.separator())

        let expandAllItem = NSMenuItem(title: "Expand All", action: #selector(expandAllMenuAction(_:)), keyEquivalent: "9")
        expandAllItem.keyEquivalentModifierMask = [.command, .shift]
        expandAllItem.target = self
        contextMenu.addItem(expandAllItem)

        let collapseAllItem = NSMenuItem(title: "Collapse All", action: #selector(collapseAllMenuAction(_:)), keyEquivalent: "0")
        collapseAllItem.keyEquivalentModifierMask = [.command, .shift]
        collapseAllItem.target = self
        contextMenu.addItem(collapseAllItem)

        contextMenu.addItem(.separator())

        for level in 1...3 {
            let item = NSMenuItem(
                title: "Collapse to Level \(level)",
                action: #selector(collapseToLevelMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = level
            contextMenu.addItem(item)
        }
    }

    private func clickedRowItem() -> Any? {
        let row = outlineView.clickedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row)
    }

    private func clickedNodeIndex() -> Int? {
        guard let item = clickedRowItem() as? Item, case .node(let nodeIndex) = item.content else { return nil }
        return nodeIndex
    }

    @objc private func copyValueAction(_ sender: Any?) {
        guard let nodeIndex = clickedNodeIndex() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(treeIndex.rawValue(at: nodeIndex, in: sourceText), forType: .string)
    }

    @objc private func copyKeyAction(_ sender: Any?) {
        guard let nodeIndex = clickedNodeIndex(), let key = treeIndex.key(at: nodeIndex, in: sourceText) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
    }

    @objc private func copyPathAction(_ sender: Any?) {
        guard let item = clickedRowItem() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dotPath(pathSegments(for: item)), forType: .string)
    }

    @objc private func expandAllMenuAction(_ sender: Any?) {
        expandAll()
    }

    @objc private func collapseAllMenuAction(_ sender: Any?) {
        collapseAll()
    }

    @objc private func collapseToLevelMenuAction(_ sender: NSMenuItem) {
        collapseToLevel(sender.tag)
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
            return plain("[\(range.lowerBound)\u{2026}\(range.upperBound - 1)]", color: .secondaryLabelColor)
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
        let result = NSMutableAttributedString()

        switch node.type {
        case .object, .array:
            if node.isTruncated || !isExpanded, let prefix = keyPrefix(for: item, nodeIndex: nodeIndex) {
                result.append(prefix)
            }
            if node.isTruncated {
                // 嵌套深度 >512 被截断的容器：childCount 归 0，不可展开
                // （isExpandableItem 已按 childCount>0 把关）。摘要位置显示明确的
                // 截断提示 + 次级警示色，与真正的空容器 "{…} 0 keys" 可区分，
                // 避免用户误以为内容本就为空。
                let bracket = node.type == .object ? "{\u{2026}}" : "[\u{2026}]"
                result.append(plain("\(bracket) depth-truncated", color: .systemOrange))
            } else if isExpanded {
                // 展开后该行只显示 key（或索引）；子内容已由子行呈现。无 key 的根容器
                // 退化显示裸括号，避免完全空白的行。
                if let label = keyLabelOnly(for: item, nodeIndex: nodeIndex) {
                    result.append(label)
                } else {
                    let bracket = node.type == .object ? "{}" : "[]"
                    result.append(plain(bracket, color: .secondaryLabelColor))
                }
            } else {
                let bracket = node.type == .object ? "{\u{2026}}" : "[\u{2026}]"
                let unit = node.type == .object ? "keys" : "items"
                result.append(plain("\(bracket) \(node.childCount) \(unit)", color: .secondaryLabelColor))
            }
        default:
            if let prefix = keyPrefix(for: item, nodeIndex: nodeIndex) {
                result.append(prefix)
            }
            let raw = sanitizeSingleLine(boundedRawValue(at: nodeIndex))
            result.append(plain(raw, color: valueColor(for: node.type)))
        }

        return result
    }

    /// object 成员真实 key（红色、带引号，引号内容按 escapeForBracket 转义避免破坏
    /// 视觉引号配对）或数组元素/JSONL 记录展示序号（灰色、不带引号，结构/元信息
    /// 范畴）；无 key 也无展示序号（如裸根节点）时返回 nil。
    private func keyLabelOnly(for item: Item, nodeIndex: Int) -> NSAttributedString? {
        if let key = treeIndex.key(at: nodeIndex, in: sourceText) {
            return plain("\"\(escapeForBracket(key))\"", color: .systemRed)
        }
        if let displayIndex = item.displayIndex {
            return plain("\(displayIndex)", color: .secondaryLabelColor)
        }
        return nil
    }

    /// keyLabelOnly + 分隔符 " : "（灰色，结构/元信息范畴，与 key/索引本身的着色
    /// 区分开）；无前缀时返回 nil。
    private func keyPrefix(for item: Item, nodeIndex: Int) -> NSAttributedString? {
        guard let label = keyLabelOnly(for: item, nodeIndex: nodeIndex) else { return nil }
        let result = NSMutableAttributedString(attributedString: label)
        result.append(plain(" : ", color: .secondaryLabelColor))
        return result
    }

    /// JSONLint 风格五色：字符串绿、数字蓝、布尔与 null 紫；容器类型不经此函数
    /// （object/array 走各自的容器摘要着色，invalid 走 invalidRowText 的红色）。
    private func valueColor(for type: JSONTreeIndex.NodeType) -> NSColor {
        switch type {
        case .string:
            return .systemGreen
        case .number:
            return .systemBlue
        case .bool, .null:
            return .systemPurple
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

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updatePathBar()
    }
}

extension JSONOutlineView: NSMenuDelegate {
    /// 右键菜单弹出前按点击行内容调整可用性：分桶行/空白区域禁用节点专属三项；
    /// 无 key 的节点（数组元素）禁用 Copy Key。全部展开/全部折叠/折叠到第 N 层
    /// 与点击目标无关，始终可用。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === contextMenu else { return }

        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? Item else {
            copyValueMenuItem?.isEnabled = false
            copyKeyMenuItem?.isEnabled = false
            copyPathMenuItem?.isEnabled = false
            return
        }

        switch item.content {
        case .bucket:
            copyValueMenuItem?.isEnabled = false
            copyKeyMenuItem?.isEnabled = false
            copyPathMenuItem?.isEnabled = false
        case .node(let nodeIndex):
            copyValueMenuItem?.isEnabled = true
            copyKeyMenuItem?.isEnabled = treeIndex.key(at: nodeIndex, in: sourceText) != nil
            copyPathMenuItem?.isEnabled = true
        }
    }
}

extension JSONOutlineView: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        previewPopover = nil
        if let monitor = popoverKeyMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyMonitor = nil
        }
    }
}

/// 树内部专用 NSOutlineView 子类：拦截 Option+点击 disclosure 三角做递归展开/折叠，
/// 拦截空格键做值预览；其余点击/键盘交由系统默认处理——单击三角 toggle、←→ 折叠/
/// 展开选中节点、↑↓ 移动选中均为 NSOutlineView 原生行为，此处不覆写。
private final class JSONOutlineTableView: NSOutlineView {
    var onOptionClickDisclosure: ((Any) -> Void)?
    var onSpacePressed: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.option) else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else {
            super.mouseDown(with: event)
            return
        }

        let disclosureRect = frameOfOutlineCell(atRow: clickedRow)
        guard !disclosureRect.isEmpty, disclosureRect.contains(point), let clickedItem = item(atRow: clickedRow) else {
            super.mouseDown(with: event)
            return
        }

        onOptionClickDisclosure?(clickedItem)
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        onSpacePressed?()
    }
}

/// 树底部常驻 path bar：显示选中节点 key path（点语法），点击弹复制菜单
/// （点语法 / jq 两种）。
private final class PathBarView: NSControl {
    var onClick: (() -> Void)?
    let titleLabel = NSTextField(labelWithString: "$")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingHead
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
