import Foundation

/// 文件树刷新的纯决策层：磁盘变化事件 → 需要重做哪些工作；新旧子项列表 → 哪些节点可以复用。
///
/// 刷新范围刻意收窄到"用户此刻看得见的东西"：已经展开过的目录、以及最前 tab 正在预览的
/// 文件。没展开过的目录不在范围内——它们首次展开时本就现列磁盘，天然拿到最新内容。
public enum FileTreeRefresh {
    /// 一次磁盘变化要触发的刷新范围。
    public struct Scope: Equatable {
        /// 需要重新列举的目录，保持传入 `loadedDirectories` 的次序。
        public let directoriesToReload: [URL]
        /// 最前 tab 的文件所在目录被动过，内容可能已变（调用方再用 size/mtime 确认）。
        public let touchesActiveFile: Bool

        public init(directoriesToReload: [URL], touchesActiveFile: Bool) {
            self.directoriesToReload = directoriesToReload
            self.touchesActiveFile = touchesActiveFile
        }

        public var isEmpty: Bool {
            directoriesToReload.isEmpty && !touchesActiveFile
        }
    }

    /// 把 FSEvents 报来的变化路径映射成刷新范围。
    ///
    /// - `changedPaths`：事件携带的目录路径（FSEvents 在目录粒度上报"这个目录的内容变了"）。
    /// - `mustScanSubDirectories`：事件被内核合并到丢失明细（`kFSEventStreamEventFlagMustScanSubDirs`），
    ///   此时无法判断具体哪里变了，全部已展开目录与当前文件一律纳入范围。
    /// - 路径比较前统一 `resolvingSymlinksInPath` + 去尾斜杠，`/var` 与 `/private/var` 视为同一目录。
    public static func scope(
        changedPaths: [String],
        mustScanSubDirectories: Bool,
        loadedDirectories: [URL],
        activeFileURL: URL?
    ) -> Scope {
        if mustScanSubDirectories {
            return Scope(directoriesToReload: loadedDirectories, touchesActiveFile: activeFileURL != nil)
        }

        let changed = Set(changedPaths.map(normalizedPath))
        guard !changed.isEmpty else {
            return Scope(directoriesToReload: [], touchesActiveFile: false)
        }

        let directories = loadedDirectories.filter { changed.contains(normalizedPath($0.path)) }
        let touchesActiveFile = activeFileURL.map {
            changed.contains(normalizedPath($0.deletingLastPathComponent().path))
        } ?? false

        return Scope(directoriesToReload: directories, touchesActiveFile: touchesActiveFile)
    }

    /// 路径比较的统一形态：解析 symlink、剥掉前导 `/private`、去掉尾斜杠。
    ///
    /// FSEvents 报的是内核视角的真实路径（`/private/var/folders/...`），节点 URL 来自用户
    /// 视角（`/var/folders/...`）。`resolvingSymlinksInPath` 只在路径当前存在时才脱 `/private`，
    /// 目录刚被删掉的那一拍两侧形态就会分叉；无条件剥前导 `/private` 让归一化与磁盘状态无关。
    /// macOS 的 `/private` 下只有 etc / tmp / var / tftpboot，四者都从根 symlink 过来，剥掉不歧义。
    private static func normalizedPath(_ path: String) -> String {
        var resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved.hasPrefix("/private/") {
            resolved = String(resolved.dropFirst("/private".count))
        }
        guard resolved.count > 1, resolved.hasSuffix("/") else { return resolved }
        return String(resolved.dropLast())
    }
}
