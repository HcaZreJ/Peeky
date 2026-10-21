import Foundation

/// PeekyCore 资源包（shiki-bundle.js、github-markdown.css）的寻径。
///
/// `Bundle.module` 找不到资源时会 fatalError，与「永不崩溃只降级」的约定冲突，
/// 因此手写多候选寻径，依次尝试：
/// 1. 标准 .app 布局：`Contents/Resources/`（`Bundle.main.resourceURL`）
/// 2. 裸可执行文件布局：资源包与二进制同级（swift build / PeekyTests）
/// 3. 可执行文件真实路径（解析 symlink 后）所在目录，以及它的 `../Resources`
///    （app 包内第二个可执行文件 `Contents/MacOS/peek-tui`）
/// 全部落空返回 nil，交由调用方走既有降级路径。
public enum CoreResources {
    static let bundleName = "Peeky_PeekyCore.bundle"

    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        for candidate in candidateBundleURLs() {
            guard let bundle = Bundle(url: candidate) else { continue }
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    static func candidateBundleURLs() -> [URL] {
        var directories: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL)
        }
        directories.append(Bundle.main.bundleURL)
        if let executable = CommandLine.arguments.first, !executable.isEmpty {
            let executableDirectory = URL(fileURLWithPath: executable)
                .resolvingSymlinksInPath()
                .deletingLastPathComponent()
            directories.append(executableDirectory)
            directories.append(executableDirectory.deletingLastPathComponent().appendingPathComponent("Resources"))
        }
        return directories.map { $0.appendingPathComponent(bundleName) }
    }
}
