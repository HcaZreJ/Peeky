import Foundation

/// 文件树节点：目录的 children 惰性填充，`childrenLoaded` 记录是否已列过磁盘。
/// 目录不可读时填一条 `isErrorPlaceholder` 子项，该目录仍可展开并呈现「(无法读取)」。
final class FileTreeNode {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isErrorPlaceholder: Bool
    var childrenLoaded = false
    var children: [FileTreeNode] = []

    init(url: URL, name: String, isDirectory: Bool, isErrorPlaceholder: Bool = false) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isErrorPlaceholder = isErrorPlaceholder
    }

    /// 把磁盘最新一级列表对账进已缓存的子项：结果次序完全跟随 `entries`，URL 未变的条目
    /// 复用原节点实例，`entries` 里新出现的 URL 建新节点，只在 `existing` 里的节点丢弃。
    ///
    /// 复用实例是硬要求：NSOutlineView 按实例记展开态与选中态，换实例会把已展开的子树折回去。
    static func reconcile(existing: [FileTreeNode], entries: [DirEntry]) -> [FileTreeNode] {
        var reusable: [URL: FileTreeNode] = [:]
        for node in existing where !node.isErrorPlaceholder {
            reusable[node.url] = node
        }

        return entries.map { entry in
            // removeValue：一个旧节点最多被认领一次，重复 URL 不会共用同一个实例。
            reusable.removeValue(forKey: entry.url)
                ?? FileTreeNode(url: entry.url, name: entry.name, isDirectory: entry.isDirectory)
        }
    }
}
