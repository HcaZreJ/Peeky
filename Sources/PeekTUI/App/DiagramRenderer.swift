import Darwin
import Foundation
import PeekyCore

/// 终端版画 Mermaid 图：交给辅助程序 `peeky-mermaid`（终端版不依赖 WebKit，mermaid.js 要靠浏览器排版
/// 量字）。PNG 放在每个进程一个的临时目录里，退出时删掉。
enum DiagramRenderer {
    static let helperName = "peeky-mermaid"

    /// 渲染程序：app 包里的 `Contents/Helpers/peeky-mermaid`，或开发构建里与 peek-tui 同目录的
    /// `peeky-mermaid`（按 peek-tui 的真实路径找）；都没有时为 nil。
    static func executable(nextTo binaryPath: String, isExecutable: (String) -> Bool) -> String? {
        let directory = URL(fileURLWithPath: binaryPath).deletingLastPathComponent()
        let candidates = [
            directory.deletingLastPathComponent().appendingPathComponent("Helpers").appendingPathComponent(helperName).path,
            directory.appendingPathComponent(helperName).path,
        ]
        return candidates.first(where: isExecutable)
    }

    /// 这个进程的 Mermaid PNG 目录。
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("peek-tui-mermaid-\(getpid())", isDirectory: true)

    /// 正在运行的 peek-tui 的真实路径（解析符号链接），据此找 app 包。
    static func runningBinaryPath() -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// 画出这些图：按明暗分组，每组一个渲染进程；本进程已画过的（PNG 还在）直接用。读不到 PNG 的尺寸记
    /// `PixelSize.unreadable`，按代码显示。
    static func render(_ sources: [MarkdownDiagramSource], executable: String) async -> [String: MermaidImage] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var results: [String: MermaidImage] = [:]
        for appearance in [PeekyPalette.Appearance.dark, .light] {
            let group = sources.filter { $0.appearance == appearance }
            let pending = group.filter { !FileManager.default.fileExists(atPath: pngURL($0).path) }
            if !pending.isEmpty {
                var arguments = ["--appearance", appearance == .dark ? "dark" : "light"]
                for source in pending {
                    let input = directory.appendingPathComponent("\(source.key).mmd")
                    try? source.code.write(to: input, atomically: true, encoding: .utf8)
                    arguments += [input.path, pngURL(source).path]
                }
                await run(executable, arguments)
            }
            for source in group {
                let path = pngURL(source).path
                results[source.key] = MermaidImage(path: path, size: ImageRasterizer.pixelSize(ofImageAt: path) ?? .unreadable)
            }
        }
        return results
    }

    /// 删掉这个进程的 Mermaid PNG 目录（退出时）。
    static func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func pngURL(_ source: MarkdownDiagramSource) -> URL {
        directory.appendingPathComponent("\(source.key).png")
    }

    /// 跑渲染进程直到退出。标准输入输出一律不接终端：不读走按键，也不往画面上写字。
    private static func run(_ executable: String, _ arguments: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
    }
}
