import Foundation

/// 最近打开的文件存在 UserDefaults 的 `PeekyRecentFiles` 里。终端版打包在 app 里，用的是同一个
/// bundle 的偏好域，两边共用这一份；记一笔之前先读存着的最新列表，一边记的条目不会被另一边盖掉。
extension RecentFiles {
    public static let defaultsKey = "PeekyRecentFiles"

    public static func load(from defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    public static func save(_ entries: [Entry], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// 记一次打开并存回：在存着的最新列表上把这条放到最前。返回新列表。
    @discardableResult
    public static func record(_ url: URL, at date: Date = Date(), in defaults: UserDefaults = .standard) -> [Entry] {
        let entry = Entry(path: url.standardizedFileURL.path, openedAt: date, origin: origin(of: url))
        let entries = recording(entry, into: load(from: defaults))
        save(entries, to: defaults)
        return entries
    }

    /// 打开那一刻文件的来源。仓库根下的 `.git` 是文件（worktree / 子模块）才读得出内容；
    /// 是目录（普通仓库）或用的是 .hg / .svn 时读取失败，按主检出处理。
    public static func origin(of url: URL) -> Origin {
        let root = RepoRoot.discover(from: url)
        let gitFileContents = root.flatMap {
            try? String(contentsOf: $0.appendingPathComponent(".git"), encoding: .utf8)
        }
        return origin(rootPath: root?.path, gitFileContents: gitFileContents)
    }
}
