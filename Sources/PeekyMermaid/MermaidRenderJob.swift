import Foundation
import PeekyCore

/// 辅助程序 `peeky-mermaid` 的命令行：
/// `peeky-mermaid --appearance dark|light <源码文件> <输出.png> [<源码文件> <输出.png> …]`。
/// 终端版在后台用它把文档里的 Mermaid 块画成 PNG。
package struct MermaidRenderJob: Equatable, Sendable {
    package struct Diagram: Equatable, Sendable {
        package var source: URL
        package var output: URL

        package init(source: URL, output: URL) {
            self.source = source
            self.output = output
        }
    }

    package enum ParseError: Error, Equatable, Sendable {
        case missingAppearance
        case invalidAppearance(String)
        case unpairedPath(String)
        case noDiagrams

        package var code: String {
            switch self {
            case .missingAppearance: return "missing_appearance"
            case .invalidAppearance: return "invalid_appearance"
            case .unpairedPath: return "unpaired_path"
            case .noDiagrams: return "no_diagrams"
            }
        }

        package var message: String {
            switch self {
            case .missingAppearance: return "缺少 --appearance dark|light"
            case let .invalidAppearance(value): return "--appearance 只能是 dark 或 light，收到 \(value)"
            case let .unpairedPath(path): return "\(path) 没有对应的输出 PNG 路径"
            case .noDiagrams: return "没有要画的图：在 --appearance 之后成对给出 <源码文件> <输出.png>"
            }
        }
    }

    package var appearance: PeekyPalette.Appearance
    package var diagrams: [Diagram]

    package init(appearance: PeekyPalette.Appearance, diagrams: [Diagram]) {
        self.appearance = appearance
        self.diagrams = diagrams
    }

    /// 命令行（含第 0 个程序路径）→ 渲染任务。
    package static func parse(_ arguments: [String]) -> Result<MermaidRenderJob, ParseError> {
        var rest = Array(arguments.dropFirst())
        guard rest.first == "--appearance", rest.count >= 2 else { return .failure(.missingAppearance) }
        let appearance: PeekyPalette.Appearance
        switch rest[1] {
        case "dark": appearance = .dark
        case "light": appearance = .light
        default: return .failure(.invalidAppearance(rest[1]))
        }
        rest.removeFirst(2)
        guard !rest.isEmpty else { return .failure(.noDiagrams) }
        guard rest.count.isMultiple(of: 2) else { return .failure(.unpairedPath(rest[rest.count - 1])) }
        let diagrams = stride(from: 0, to: rest.count, by: 2).map { index in
            Diagram(source: URL(fileURLWithPath: rest[index]), output: URL(fileURLWithPath: rest[index + 1]))
        }
        return .success(MermaidRenderJob(appearance: appearance, diagrams: diagrams))
    }
}
