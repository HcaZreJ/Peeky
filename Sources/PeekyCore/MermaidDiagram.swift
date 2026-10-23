import Foundation

/// Markdown 里的 Mermaid 图：app 的 Markdown 预览与终端版共用的识别规则。
package enum MermaidDiagram {
    /// 围栏代码块 info string 的第一个词是 mermaid 时画成图，不分大小写（swift-markdown 的
    /// `CodeBlock.language` 是整段 info string，含后面的附加说明）。
    package static func isDiagram(language: String?) -> Bool {
        guard let firstWord = language?.split(whereSeparator: \.isWhitespace).first else { return false }
        return firstWord.lowercased() == "mermaid"
    }

    /// 从 PeekyCore 资源包读 mermaid.js（11.17.2 单文件构建，加载后是 `globalThis.mermaid`；
    /// 寻径见 `CoreResources`）。找不到时为 nil，Mermaid 块照旧显示成代码。
    package static func loadLibrary() -> String? {
        guard let url = CoreResources.url(forResource: "mermaid.min", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
