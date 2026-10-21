import PeekyCore

/// Markdown 代码块围栏上的语言名 → shiki 语言。既认扩展名写法（`py`、`ts`、`sh`），
/// 也认语言全名（`python`、`typescript`、`shell`）；shiki bundle 没有的语言返回 nil（不上色）。
package enum CodeFenceLanguage {
    static let fullNames: [String: String] = [
        "python": "python",
        "typescript": "typescript",
        "javascript": "javascript",
        "json": "json",
        "yaml": "yaml",
        "toml": "toml",
        "bash": "bash",
        "shell": "bash",
        "console": "bash",
        "swift": "swift",
        "ini": "ini",
        "jsonc": "json",
        "node": "javascript",
    ]

    package static func shikiLanguage(for fence: String?) -> String? {
        guard let fence else { return nil }
        let name = fence.split(separator: " ").first.map { $0.lowercased() } ?? ""
        guard !name.isEmpty else { return nil }
        return HighlightService.language(forExtension: name) ?? fullNames[name]
    }
}
