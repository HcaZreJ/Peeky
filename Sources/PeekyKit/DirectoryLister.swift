import Foundation

/// 目录的一级子项。
public struct DirEntry: Equatable {
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    /// 文件为字节数；目录为 0。
    public let size: Int64
    public let mtime: Date

    public init(name: String, url: URL, isDirectory: Bool, size: Int64, mtime: Date) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.mtime = mtime
    }
}

/// 目录一级子项枚举（不递归）。
public enum DirectoryLister {
    /// 列举 dir 的直接子项。
    ///
    /// - 排序：目录在前、文件在后，各自按 name 不区分大小写升序
    ///   （大小写不敏感比较相等时按 name 字节序保持稳定次序）。
    /// - 过滤：名为 `.git` / `.hg` / `.svn` / `.DS_Store` 的条目一律不出现；
    ///   其余条目（含其它 dotfile、node_modules）均出现。
    /// - symlink 条目按解析目标判定 isDirectory，不递归展开。
    /// - dir 不存在 / 不是目录 / 不可读 → throws。
    public static func list(dir: URL) throws -> [DirEntry] {
        let fm = FileManager.default
        let excludedNames: Set<String> = [".git", ".hg", ".svn", ".DS_Store"]

        let contents = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])

        var entries: [DirEntry] = []
        entries.reserveCapacity(contents.count)

        for url in contents {
            let name = url.lastPathComponent
            if excludedNames.contains(name) {
                continue
            }

            let ownValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            let mtime = ownValues.contentModificationDate ?? Date()

            var isDirectory = ownValues.isDirectory ?? false
            var size: Int64 = 0

            if ownValues.isSymbolicLink == true {
                let resolved = url.resolvingSymlinksInPath()
                if fm.fileExists(atPath: resolved.path),
                   let targetValues = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) {
                    isDirectory = targetValues.isDirectory ?? false
                    size = isDirectory ? 0 : Int64(targetValues.fileSize ?? 0)
                } else {
                    isDirectory = false
                    size = 0
                }
            } else if !isDirectory {
                let ownFileValues = try url.resourceValues(forKeys: [.fileSizeKey])
                size = Int64(ownFileValues.fileSize ?? 0)
            }

            let entryURL = dir.appendingPathComponent(name, isDirectory: isDirectory)
            entries.append(DirEntry(name: name, url: entryURL, isDirectory: isDirectory, size: size, mtime: mtime))
        }

        entries.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            let cmp = a.name.caseInsensitiveCompare(b.name)
            if cmp == .orderedSame {
                return a.name < b.name
            }
            return cmp == .orderedAscending
        }

        return entries
    }
}
