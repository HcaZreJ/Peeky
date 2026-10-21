import Foundation
import PeekyCore

/// 标题行内容：路径在代码仓库里时写成「仓库名/仓库内相对路径」，否则同 `DisplayPath`；
/// 详情依次为最后更改时间、类型、大小、note（与 app 顶栏副标题的顺序与分隔一致）。
package enum DocumentHeaderBuilder {
    static let separator = "  |  "

    package static func make(loaded: LoadedText, prepared: PreparedText, modifiedAt: Date?, repoRoot: URL?) -> DocumentHeader {
        var details: [String] = []
        if let modifiedAt {
            details.append(LastModifiedText.format(modifiedAt))
        }
        details.append(loaded.kind.displayName)
        details.append(ByteCountFormatter.string(fromByteCount: loaded.totalBytes, countStyle: .file))
        details.append(prepared.note)
        if loaded.isTruncated {
            details.append("只读入前 \(ByteCountFormatter.string(fromByteCount: Int64(loaded.readBytes), countStyle: .file))")
        }
        return DocumentHeader(displayPath: displayPath(for: loaded.url, repoRoot: repoRoot), details: details.joined(separator: separator))
    }

    package static func displayPath(for url: URL, repoRoot: URL?) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let repoRoot {
            let root = repoRoot.standardizedFileURL.resolvingSymlinksInPath().path
            if path.hasPrefix(root + "/") {
                return repoRoot.lastPathComponent + "/" + path.dropFirst(root.count + 1)
            }
        }
        return DisplayPath.make(for: url)
    }
}

/// 不在代码仓库里时的显示路径：在当前目录下用相对路径，在家目录下用 `~/`，否则用绝对路径。
package enum DisplayPath {
    package static func make(for url: URL, currentDirectory: String = FileManager.default.currentDirectoryPath) -> String {
        let path = url.standardizedFileURL.path
        let base = currentDirectory.hasSuffix("/") ? currentDirectory : currentDirectory + "/"
        if path.hasPrefix(base) {
            return String(path.dropFirst(base.count))
        }
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }
}
