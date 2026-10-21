import Foundation
import PeekyCore

/// 文件树里的一项：目录列表中的一条。
package struct TreeEntry: Equatable, Sendable {
    package let name: String
    package let url: URL
    package let isDirectory: Bool

    package init(name: String, url: URL, isDirectory: Bool) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
    }

    init(_ entry: DirEntry) {
        self.init(name: entry.name, url: entry.url, isDirectory: entry.isDirectory)
    }

    /// 比较用的路径（没有结尾斜杠）。
    package var path: String { url.standardizedFileURL.path }
}

/// 一个目录的列举结果。
package enum DirectoryListing: Equatable, Sendable {
    case entries([TreeEntry])
    /// 目录读不了：展开后显示一条「(无法读取)」
    case unreadable
}

/// 侧栏文件树的一行。
package struct TreeRow: Equatable, Sendable {
    package enum Content: Equatable, Sendable {
        case entry(TreeEntry, isExpanded: Bool)
        case unreadablePlaceholder
    }

    package let content: Content
    /// 树根的直接子项为 0
    package let depth: Int
    /// 从上到下的各级父目录路径（不含树根），最后一个是直接父目录
    package let ancestors: [String]

    package var entry: TreeEntry? {
        if case let .entry(entry, _) = content { return entry }
        return nil
    }
}

/// 侧栏文件树：按路径记每个列过的目录与展开状态（值类型，展开状态随路径保留，
/// 目录重新列举后不会折回去）。树根本身不占一行，总是展开。
package struct FileTree: Equatable, Sendable {
    package static let unreadableText = "(无法读取)"

    package let root: URL
    private var listings: [String: DirectoryListing] = [:]
    private var expanded: Set<String> = []

    package init(root: URL) {
        self.root = root.standardizedFileURL
    }

    package var rootPath: String { root.path }

    /// 展开且已列过的目录（含树根），供 `FileTreeRefresh.scope` 收窄刷新范围。
    package var loadedDirectories: [URL] {
        ([rootPath] + expanded.sorted())
            .filter { listings[$0] != nil }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    package func isExpanded(_ path: String) -> Bool {
        path == rootPath || expanded.contains(path)
    }

    /// 可见行，深度优先；展开了但还没列到的目录下面暂时没有行。
    package func rows() -> [TreeRow] {
        var result: [TreeRow] = []
        appendRows(of: rootPath, depth: 0, ancestors: [], into: &result)
        return result
    }

    private func appendRows(of directory: String, depth: Int, ancestors: [String], into result: inout [TreeRow]) {
        switch listings[directory] {
        case nil:
            return
        case .unreadable:
            result.append(TreeRow(content: .unreadablePlaceholder, depth: depth, ancestors: ancestors))
        case let .entries(entries):
            for entry in entries {
                let isOpen = entry.isDirectory && expanded.contains(entry.path)
                result.append(TreeRow(content: .entry(entry, isExpanded: isOpen), depth: depth, ancestors: ancestors))
                if isOpen {
                    appendRows(of: entry.path, depth: depth + 1, ancestors: ancestors + [entry.path], into: &result)
                }
            }
        }
    }

    /// 写入一个目录的最新列表；消失了的子目录连同它下面记过的列表与展开状态一起丢掉。
    package mutating func setListing(_ listing: DirectoryListing, for directory: URL) {
        let path = directory.standardizedFileURL.path
        if case let .entries(old) = listings[path] {
            let current: Set<String>
            if case let .entries(entries) = listing { current = Set(entries.map(\.path)) } else { current = [] }
            for gone in old where gone.isDirectory && !current.contains(gone.path) {
                forget(gone.path)
            }
        }
        listings[path] = listing
    }

    private mutating func forget(_ path: String) {
        let prefix = path + "/"
        listings = listings.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
        expanded = expanded.filter { $0 != path && !$0.hasPrefix(prefix) }
    }

    package mutating func setExpanded(_ path: String, _ isExpanded: Bool) {
        if isExpanded {
            expanded.insert(path)
        } else {
            expanded.remove(path)
        }
    }

    /// 展开从树根到 `file` 所在目录的每一级，返回这些目录（含树根，从上到下）；
    /// `file` 不在树根下时只返回树根。
    package mutating func reveal(_ file: URL) -> [URL] {
        let path = file.standardizedFileURL.path
        var directories = [root]
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(rootPrefix) else { return directories }
        let components = path.dropFirst(rootPrefix.count).split(separator: "/").dropLast()
        var current = rootPath
        for component in components {
            current = (current == "/" ? "" : current) + "/" + component
            expanded.insert(current)
            directories.append(URL(fileURLWithPath: current, isDirectory: true))
        }
        return directories
    }
}
