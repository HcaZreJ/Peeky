import Foundation

/// 最近打开的文件：记一次打开、判定每条此刻能否打开、产出菜单与空白窗口共用的显示文字。
///
/// 纯运算——磁盘是否存在由调用方以 `pathExists` 注入，`.git` 文件内容以字符串传入；
/// 读写 UserDefaults 与探测磁盘都在 `AppDelegate`。
public enum RecentFiles {
    public static let capacity = 20

    /// 一条记录：打开那一刻记下的事实。
    ///
    /// 仓库名与 worktree 名在打开时记下，显示时不再现推——worktree 删掉之后它的 `.git` 文件
    /// 跟着没了，那时已经推不出「这曾是 peeky 的 fix-scroll worktree」。
    public struct Entry: Codable, Equatable, Sendable {
        /// 标准化后的绝对路径；列表按它去重。
        public let path: String
        public let openedAt: Date
        public let origin: Origin

        public init(path: String, openedAt: Date, origin: Origin) {
            self.path = path
            self.openedAt = openedAt
            self.origin = origin
        }

        public var fileName: String {
            (path as NSString).lastPathComponent
        }
    }

    public enum Origin: Codable, Equatable, Sendable {
        /// 不在任何版本库里。
        case folder
        /// 在版本库的主检出里（子模块也算这一类）。`rootPath` 是仓库根。
        case repository(name: String, rootPath: String)
        /// 在 git worktree 里。`rootPath` 是 worktree 根目录——它整个不在了就是「worktree 已删除」。
        case worktree(repositoryName: String, worktreeName: String, rootPath: String)
    }

    public enum Availability: Equatable, Sendable {
        case available
        /// 文件所在的 worktree 目录整个不在了。
        case worktreeRemoved
        /// 其余原因找不到：被删、被移走，或 worktree 还在但文件没了。
        case missing
    }

    /// 一行要显示的全部内容，菜单条目与空白窗口的行都从它画。
    public struct Item: Equatable, Sendable {
        public let path: String
        public let name: String
        public let location: String
        /// 打不开的原因；能打开时为 nil。
        public let reason: String?
        public let tooltip: String
        public let isOpenable: Bool
    }

    /// 记一次打开：这条放到最前，同路径的旧条目去掉，超出容量截掉最早的。
    public static func recording(_ entry: Entry, into entries: [Entry]) -> [Entry] {
        let others = entries.filter { $0.path != entry.path }
        return Array(([entry] + others).prefix(capacity))
    }

    public static func availability(of entry: Entry, pathExists: (String) -> Bool) -> Availability {
        if pathExists(entry.path) {
            return .available
        }
        if case let .worktree(_, _, rootPath) = entry.origin, !pathExists(rootPath) {
            return .worktreeRemoved
        }
        return .missing
    }

    /// 打开那一刻文件的来源。`rootPath` 是 `RepoRoot.discover` 找到的仓库根（找不到为 nil）；
    /// `gitFileContents` 是根下 `.git` 文件的内容——`.git` 是目录或不存在时为 nil。
    ///
    /// worktree 的 `.git` 文件是一行 `gitdir: <主仓库 git 目录>/worktrees/<名>`；子模块的同样是
    /// `gitdir:` 一行，但指向 `modules/` 下，按主检出处理。
    public static func origin(rootPath: String?, gitFileContents: String?) -> Origin {
        guard let rootPath else { return .folder }

        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let repository = Origin.repository(name: root.lastPathComponent, rootPath: rootPath)

        let prefix = "gitdir:"
        guard let line = gitFileContents?.trimmingCharacters(in: .whitespacesAndNewlines),
              line.hasPrefix(prefix) else { return repository }

        let gitdir = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !gitdir.isEmpty else { return repository }

        let gitdirURL = gitdir.hasPrefix("/")
            ? URL(fileURLWithPath: gitdir)
            : URL(fileURLWithPath: gitdir, relativeTo: root)
        let components = gitdirURL.standardizedFileURL.pathComponents
        guard components.count >= 4, components[components.count - 2] == "worktrees" else { return repository }

        // `<主仓库>/.git/worktrees/<名>` 取 `<主仓库>`；裸仓库 `peeky.git/worktrees/<名>` 去掉 `.git` 后缀。
        let gitDirectoryName = components[components.count - 3]
        let repositoryName = gitDirectoryName == ".git"
            ? components[components.count - 4]
            : String(gitDirectoryName.dropLast(gitDirectoryName.hasSuffix(".git") ? 4 : 0))

        return .worktree(repositoryName: repositoryName, worktreeName: root.lastPathComponent, rootPath: rootPath)
    }

    /// 「在哪」：哪个仓库、哪个 worktree。
    ///
    /// - 主检出：`peeky`
    /// - worktree：`peeky › worktree fix-scroll`
    /// - 不在仓库里：父目录，家目录缩成 `~`，如 `~/Downloads`
    /// - 同名文件落在同一个仓库（或同一个 worktree）里时，再补仓库内的目录：`coeval › apps/web`
    public static func location(for entry: Entry, in entries: [Entry], homePath: String) -> String {
        let base = baseLocation(for: entry, homePath: homePath)
        let collides = entries.contains {
            $0.path != entry.path
                && $0.fileName == entry.fileName
                && baseLocation(for: $0, homePath: homePath) == base
        }
        guard collides, let directory = directoryInsideRoot(entry), !directory.isEmpty else {
            return base
        }
        return "\(base) › \(directory)"
    }

    public static func items(
        for entries: [Entry],
        pathExists: (String) -> Bool,
        homePath: String,
        now: Date
    ) -> [Item] {
        entries.map { entry in
            let availability = availability(of: entry, pathExists: pathExists)
            return Item(
                path: entry.path,
                name: entry.fileName,
                location: location(for: entry, in: entries, homePath: homePath),
                reason: reason(for: availability),
                tooltip: tooltip(for: entry, availability: availability, homePath: homePath, now: now),
                isOpenable: availability == .available
            )
        }
    }

    private static func reason(for availability: Availability) -> String? {
        switch availability {
        case .available: return nil
        case .worktreeRemoved: return "Worktree deleted"
        case .missing: return "File moved or deleted"
        }
    }

    /// 悬停提示：完整路径 + 一句说明。路径是核对「到底是哪个文件」的最终依据。
    private static func tooltip(for entry: Entry, availability: Availability, homePath: String, now: Date) -> String {
        let path = tildified(entry.path, homePath: homePath)
        switch availability {
        case .available:
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            // 界面文字一律英文（与 Open... / Close File 一致），不跟系统语言出「2分钟前」。
            formatter.locale = Locale(identifier: "en")
            return "\(path)\nOpened \(formatter.localizedString(for: entry.openedAt, relativeTo: now))"
        case .worktreeRemoved:
            guard case let .worktree(_, worktreeName, _) = entry.origin else { return path }
            return "\(path)\nThe worktree “\(worktreeName)” is no longer on disk."
        case .missing:
            return "\(path)\nNo file at this path anymore."
        }
    }

    private static func tildified(_ path: String, homePath: String) -> String {
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    private static func baseLocation(for entry: Entry, homePath: String) -> String {
        switch entry.origin {
        case .folder:
            return tildified((entry.path as NSString).deletingLastPathComponent, homePath: homePath)
        case let .repository(name, _):
            return name
        case let .worktree(repositoryName, worktreeName, _):
            return "\(repositoryName) › worktree \(worktreeName)"
        }
    }

    /// 文件所在目录相对仓库根（或 worktree 根）的路径；文件就在根下时为空串，不在仓库里为 nil。
    private static func directoryInsideRoot(_ entry: Entry) -> String? {
        let root: String
        switch entry.origin {
        case .folder: return nil
        case let .repository(_, rootPath): root = rootPath
        case let .worktree(_, _, rootPath): root = rootPath
        }
        let parent = (entry.path as NSString).deletingLastPathComponent
        if parent == root { return "" }
        guard parent.hasPrefix(root + "/") else { return nil }
        return String(parent.dropFirst(root.count + 1))
    }
}
