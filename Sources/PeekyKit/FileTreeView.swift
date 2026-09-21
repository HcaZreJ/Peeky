import AppKit
import Foundation

/// repo-aware 文件树组件：基于 NSOutlineView 的惰性加载文件树。
///
/// 节点首次展开时调用 `DirectoryLister.list`，结果缓存在节点上。缓存会在三个时机与磁盘重新对账：
/// 展开某个目录时、`revealAndSelect` 在缓存里找不到目标时、以及外部调用 `refresh(directories:)`
/// / `refreshAll()` 时。对账走 `FileTreeNode.reconcile`，URL 没变的条目复用原节点实例，
/// 于是已展开的子树在刷新后仍然展开。
/// 高度由自身管理（随展开/折叠增减），不内置滚动——整份 sidebar 已有外层滚动区，
/// 避免嵌套滚动的交互冲突。
final class FileTreeView: NSView {
    /// 单击文件行时触发，携带该文件的 URL；单击目录行不触发（只展开/折叠）。
    var onFileClick: ((URL) -> Void)?

    private let outlineView = NSOutlineView()
    private var heightConstraint: NSLayoutConstraint!
    private var rootNode: FileTreeNode?
    /// 恢复展开态的过程中把「展开即对账」这条规则让开：此时的 expandItem 只是在重演
    /// 用户原有的展开状态，磁盘已经在同一轮里列过了。
    private var isRestoringExpansion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupOutlineView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupOutlineView() {
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = ""
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.rowSizeStyle = .small
        outlineView.rowHeight = 20
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.indentationPerLevel = 14
        outlineView.backgroundColor = .clear
        outlineView.focusRingType = .none
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(outlineView)

        let height = outlineView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height

        NSLayoutConstraint.activate([
            outlineView.topAnchor.constraint(equalTo: topAnchor),
            outlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outlineView.bottomAnchor.constraint(equalTo: bottomAnchor),
            height
        ])
    }

    /// 单列表格不进 NSScrollView，column 的自动 tile 时机不可靠；每次 layout 时都
    /// 显式把唯一的 outline column 宽度同步到当前 bounds，避免残留旧宽度导致内容
    /// 溢出/裁切或与实际可视宽度不一致。
    override func layout() {
        super.layout()
        if bounds.width > 0 {
            outlineView.outlineTableColumn?.width = bounds.width
        }
    }

    /// 测试用：让用例可以按行读出树当前显示成什么样。
    var outlineViewForTesting: NSOutlineView { outlineView }

    // MARK: - 公开接口

    /// 清缓存重建：丢弃旧的节点图，以 root 为新的根节点并展开之。
    func reload(root: URL) {
        let node = FileTreeNode(url: root, name: root.lastPathComponent, isDirectory: true)
        rootNode = node
        outlineView.reloadData()
        outlineView.expandItem(node)
        updateHeight()
    }

    /// 已经列过磁盘的目录，按「父在前」的次序给出。磁盘变化事件用它来判断这一轮要重列哪些目录；
    /// 没列过的目录不在其中——它们下次展开时本就现列磁盘。
    var loadedDirectoryURLs: [URL] {
        guard let rootNode else { return [] }

        var result: [URL] = []
        var queue = [rootNode]
        var index = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            guard node.isDirectory, node.childrenLoaded else { continue }
            result.append(node.url)
            queue.append(contentsOf: node.children)
        }
        return result
    }

    /// 重列指定的若干目录并把结果落到界面上；展开态与选中行保持不变。
    ///
    /// 传进来的 URL 取自 `loadedDirectoryURLs`，与节点上的 URL 是同一批值，按值相等匹配即可。
    func refresh(directories: [URL]) {
        guard rootNode != nil, !directories.isEmpty else { return }

        let targets = Set(directories)
        var didRelist = false
        forEachLoadedDirectory { node in
            guard targets.contains(node.url) else { return }
            refreshChildren(node)
            didRelist = true
        }

        guard didRelist else { return }
        reapplyNodeGraph()
    }

    /// 重列当前所有已展开目录（⌘R / 刷新按钮的落点）。
    func refreshAll() {
        guard rootNode != nil else { return }
        forEachLoadedDirectory { refreshChildren($0) }
        reapplyNodeGraph()
    }

    /// 逐级展开到 fileURL 并选中滚动可见；fileURL 不在当前根内则不做任何事。
    func revealAndSelect(fileURL: URL) {
        guard let rootNode else { return }

        let standardizedTarget = fileURL.standardizedFileURL
        let rootComponents = rootNode.url.standardizedFileURL.pathComponents
        let targetComponents = standardizedTarget.pathComponents
        let prefixMatches = Array(targetComponents.prefix(rootComponents.count)).elementsEqual(
            rootComponents,
            by: { lhs, rhs in lhs.caseInsensitiveCompare(rhs) == .orderedSame }
        )
        guard targetComponents.count >= rootComponents.count, prefixMatches else {
            return
        }

        var current = rootNode
        outlineView.expandItem(current)

        for index in rootComponents.count..<targetComponents.count {
            loadChildrenIfNeeded(current)
            let componentName = targetComponents[index]

            var next = child(of: current, named: componentName)
            if next == nil {
                // 缓存是上次展开时的快照，目标可能是之后才落到磁盘上的（已展开的目录
                // 不会触发 itemWillExpand，拿不到那条对账时机）：现列一次再找一遍。
                refreshChildren(current)
                outlineView.reloadItem(current, reloadChildren: true)
                next = child(of: current, named: componentName)
            }

            guard let found = next else { break }
            current = found
            if current.isDirectory {
                outlineView.expandItem(current)
            }
        }

        updateHeight()

        let row = outlineView.row(forItem: current)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    // MARK: - 与磁盘对账

    /// 无条件重列该目录并与已缓存的子项对账。目录不可读时填一条不可点占位子项，
    /// 使该目录仍可展开而呈现「(无法读取)」。
    private func refreshChildren(_ node: FileTreeNode) {
        guard node.isDirectory else { return }
        node.childrenLoaded = true

        do {
            let entries = try DirectoryLister.list(dir: node.url)
            node.children = FileTreeNode.reconcile(existing: node.children, entries: entries)
        } catch {
            node.children = [
                FileTreeNode(
                    url: node.url.appendingPathComponent(".peeky-unreadable"),
                    name: "(无法读取)",
                    isDirectory: false,
                    isErrorPlaceholder: true
                )
            ]
        }
    }

    private func loadChildrenIfNeeded(_ node: FileTreeNode) {
        guard node.isDirectory, !node.childrenLoaded else { return }
        refreshChildren(node)
    }

    private func child(of node: FileTreeNode, named name: String) -> FileTreeNode? {
        node.children.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// 遍历所有已列过磁盘的目录节点，父先于子。
    private func forEachLoadedDirectory(_ body: (FileTreeNode) -> Void) {
        guard let rootNode else { return }

        var queue = [rootNode]
        var index = 0
        while index < queue.count {
            let node = queue[index]
            index += 1
            guard node.isDirectory, node.childrenLoaded else { continue }
            body(node)
            queue.append(contentsOf: node.children)
        }
    }

    /// 把重列后的节点图落到 outlineView 上，展开态与选中行原样恢复。
    private func reapplyNodeGraph() {
        let expanded = expandedURLs()
        let selectedURL = (outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode)?.url

        isRestoringExpansion = true
        outlineView.reloadData()
        if let rootNode {
            outlineView.expandItem(rootNode)
            for child in rootNode.children {
                restoreExpansion(expanded, from: child)
            }
        }
        isRestoringExpansion = false

        updateHeight()

        guard let selectedURL, let row = row(forURL: selectedURL) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func expandedURLs() -> Set<URL> {
        var result: Set<URL> = []
        for row in 0..<outlineView.numberOfRows {
            guard
                let node = outlineView.item(atRow: row) as? FileTreeNode,
                outlineView.isItemExpanded(node)
            else {
                continue
            }
            result.insert(node.url)
        }
        return result
    }

    /// 自上而下恢复：父展开之后子节点才在 outlineView 里可寻址。
    private func restoreExpansion(_ urls: Set<URL>, from node: FileTreeNode) {
        guard node.isDirectory, urls.contains(node.url) else { return }
        outlineView.expandItem(node)
        for child in node.children {
            restoreExpansion(urls, from: child)
        }
    }

    private func row(forURL url: URL) -> Int? {
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileTreeNode, node.url == url {
                return row
            }
        }
        return nil
    }

    // MARK: - 高度自管理

    /// 树没有内置滚动，高度必须精确等于当前可见行数，否则会在 sidebar 里裁切或留白。
    private func updateHeight() {
        let rows = outlineView.numberOfRows
        heightConstraint.constant = CGFloat(rows) * outlineView.rowHeight
    }

    private func guideColumns(
        for node: FileTreeNode,
        activeAncestor: FileTreeNode?
    ) -> [FileTreeIndentGuide.Column] {
        FileTreeIndentGuide.columns(
            ancestors: ancestors(of: node),
            activeAncestor: activeAncestor,
            indent: outlineView.indentationPerLevel
        )
    }

    private func ancestors(of node: FileTreeNode) -> [FileTreeNode] {
        var chain: [FileTreeNode] = []
        var cursor = outlineView.parent(forItem: node) as? FileTreeNode
        while let current = cursor {
            chain.append(current)
            cursor = outlineView.parent(forItem: current) as? FileTreeNode
        }
        return chain.reversed()
    }

    private func activeGuideAncestor() -> FileTreeNode? {
        let row = outlineView.selectedRow
        guard row >= 0, let selected = outlineView.item(atRow: row) as? FileTreeNode else { return nil }
        return FileTreeIndentGuide.activeAncestor(
            selected: selected,
            parent: outlineView.parent(forItem: selected) as? FileTreeNode
        )
    }

    /// 选中换行时整屏的活动列都要重算——亮的是哪一列取决于选中行，不取决于行自己。
    private func refreshGuideColumns() {
        let active = activeGuideAncestor()
        for row in 0..<outlineView.numberOfRows {
            guard
                let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? FileTreeRowView,
                let node = outlineView.item(atRow: row) as? FileTreeNode
            else {
                continue
            }
            rowView.guideColumns = guideColumns(for: node, activeAncestor: active)
        }
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard
            row >= 0,
            let node = outlineView.item(atRow: row) as? FileTreeNode,
            !node.isErrorPlaceholder
        else {
            return
        }

        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            onFileClick?(node.url)
        }
    }
}

extension FileTreeView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else {
            return rootNode == nil ? 0 : 1
        }
        guard let node = item as? FileTreeNode, node.isDirectory else { return 0 }
        loadChildrenIfNeeded(node)
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return rootNode! }
        let node = item as! FileTreeNode
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileTreeNode else { return false }
        return node.isDirectory
    }
}

extension FileTreeView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileTreeNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileTreeRow")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown

            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false

            cell.imageView = imageView
            cell.textField = textField
            cell.addSubview(imageView)
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 14),
                imageView.heightAnchor.constraint(equalToConstant: 14),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = node.name
        cell.textField?.font = NSFont.systemFont(ofSize: 12, weight: node.isDirectory ? .medium : .regular)
        cell.textField?.textColor = node.isErrorPlaceholder ? .secondaryLabelColor : .labelColor
        cell.imageView?.image = NSImage(
            systemSymbolName: node.isErrorPlaceholder ? "exclamationmark.triangle" : (node.isDirectory ? "folder.fill" : "doc.text"),
            accessibilityDescription: nil
        )

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let node = item as? FileTreeNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("FileTreeRowView")
        let rowView: FileTreeRowView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileTreeRowView {
            rowView = reused
        } else {
            rowView = FileTreeRowView()
            rowView.identifier = identifier
        }

        rowView.guideColumns = guideColumns(for: node, activeAncestor: activeGuideAncestor())
        return rowView
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshGuideColumns()
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? FileTreeNode else { return false }
        return !node.isErrorPlaceholder
    }

    /// 展开即对账：折叠再展开就是用户手边最近的一次手动刷新。
    func outlineViewItemWillExpand(_ notification: Notification) {
        guard
            !isRestoringExpansion,
            let node = notification.userInfo?["NSObject"] as? FileTreeNode
        else {
            return
        }
        refreshChildren(node)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateHeight()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateHeight()
    }
}

/// 文件树的行：在系统行背景之上画缩进导轨。
/// 选中行整行高亮，其导轨被 `drawSelection` 覆盖——高亮本身已经答了「我在哪」。
final class FileTreeRowView: NSTableRowView {
    private static let lineWidth: CGFloat = 1

    var guideColumns: [FileTreeIndentGuide.Column] = [] {
        didSet {
            guard guideColumns != oldValue else { return }
            needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)

        guard !guideColumns.isEmpty else { return }
        let appearance = PeekyTheme.resolveAppearance(effectiveAppearance)
        let inactive = PeekyTheme.color(.treeIndentGuide, appearance: appearance)
        let active = PeekyTheme.color(.gutterDisclosure, appearance: appearance)

        for column in guideColumns {
            (column.isActive ? active : inactive).setFill()
            NSRect(x: column.x, y: 0, width: Self.lineWidth, height: bounds.height).fill()
        }
    }
}
