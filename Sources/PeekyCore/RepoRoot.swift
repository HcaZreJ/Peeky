import Foundation

/// 版本库根发现。仅认 VCS 标记（`.git` / `.hg` / `.svn`，条目为文件或目录均算
/// ——git worktree/submodule 的 `.git` 是文件）；弱标记（package.json、README 等）
/// 一律不钉根。
public enum RepoRoot {
    /// 自起点向上寻找最近的含 VCS 标记的目录。
    ///
    /// - start 为目录：从 start 自身开始（含 start）逐级向上检查；
    ///   start 为文件：从其父目录开始。
    /// - 命中 → 返回该目录 URL（standardized）；到文件系统根检查完仍无 → nil。
    /// - start 路径不存在 → nil（查询语义，不抛错）。
    public static func discover(from start: URL) -> URL? {
        let fm = FileManager.default
        let standardizedStart = start.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: standardizedStart.path, isDirectory: &isDirectory) else {
            return nil
        }

        var current = (isDirectory.boolValue ? standardizedStart : standardizedStart.deletingLastPathComponent())
            .standardizedFileURL

        while true {
            for marker in [".git", ".hg", ".svn"] {
                let markerPath = current.appendingPathComponent(marker).path
                if fm.fileExists(atPath: markerPath) {
                    return current
                }
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}
