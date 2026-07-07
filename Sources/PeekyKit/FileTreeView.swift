import AppKit
import Foundation

/// repo-aware 文件树组件：基于 NSOutlineView 的惰性加载文件树。
///
/// 节点首次展开时才调用 `DirectoryLister.list`，结果缓存在节点上；`reload(root:)`
/// 丢弃旧的节点图（连同其缓存的子项）重建一棵新树。高度由自身管理（随展开/折叠增减），
/// 不内置滚动——整份 sidebar 已有外层滚动区，避免嵌套滚动的交互冲突。
final class FileTreeView: NSView {
    /// 单击文件行时触发，携带该文件的 URL；单击目录行不触发（只展开/折叠）。
    var onFileClick: ((URL) -> Void)?

    /// 树节点：目录节点的 children 惰性填充；DirectoryLister 抛错时填一条不可点占位子项，
    /// 使该目录仍可展开但呈现"(无法读取)"而不崩溃。
    private final class Node {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isErrorPlaceholder: Bool
        var childrenLoaded = false
        var children: [Node] = []

        init(url: URL, name: String, isDirectory: Bool, isErrorPlaceholder: Bool = false) {
            self.url = url
            self.name = name
            self.isDirectory = isDirectory
            self.isErrorPlaceholder = isErrorPlaceholder
        }
    }

    private let outlineView = NSOutlineView()
    private var heightConstraint: NSLayoutConstraint!
    private var rootNode: Node?

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

    // MARK: - 公开接口

    /// 清缓存重建：丢弃旧的节点图，以 root 为新的根节点并展开之。
    func reload(root: URL) {
        let node = Node(url: root, name: root.lastPathComponent, isDirectory: true)
        rootNode = node
        outlineView.reloadData()
        outlineView.expandItem(node)
        updateHeight()
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
            guard let next = current.children.first(where: { $0.name.caseInsensitiveCompare(componentName) == .orderedSame }) else {
                break
            }
            current = next
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

    // MARK: - 惰性加载

    private func loadChildrenIfNeeded(_ node: Node) {
        guard node.isDirectory, !node.childrenLoaded else { return }
        node.childrenLoaded = true

        do {
            let entries = try DirectoryLister.list(dir: node.url)
            node.children = entries.map { Node(url: $0.url, name: $0.name, isDirectory: $0.isDirectory) }
        } catch {
            node.children = [
                Node(
                    url: node.url.appendingPathComponent(".peeky-unreadable"),
                    name: "(无法读取)",
                    isDirectory: false,
                    isErrorPlaceholder: true
                )
            ]
        }
    }

    // MARK: - 高度自管理

    /// 树没有内置滚动，高度必须精确等于当前可见行数，否则会在 sidebar 里裁切或留白。
    private func updateHeight() {
        let rows = outlineView.numberOfRows
        heightConstraint.constant = CGFloat(rows) * outlineView.rowHeight
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard
            row >= 0,
            let node = outlineView.item(atRow: row) as? Node,
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
        guard let node = item as? Node, node.isDirectory else { return 0 }
        loadChildrenIfNeeded(node)
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else { return rootNode! }
        let node = item as! Node
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return node.isDirectory
    }
}

extension FileTreeView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }

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
        cell.textField?.textColor = node.isErrorPlaceholder ? .secondaryLabelColor : .labelColor
        cell.imageView?.image = NSImage(
            systemSymbolName: node.isErrorPlaceholder ? "exclamationmark.triangle" : (node.isDirectory ? "folder" : "doc.text"),
            accessibilityDescription: nil
        )

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        return !node.isErrorPlaceholder
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateHeight()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateHeight()
    }
}
