import Foundation

/// Markdown 里的 Mermaid 图：app 的 Markdown 预览与终端版共用的识别规则。
package enum MermaidDiagram {
    /// 围栏代码块 info string 的第一个词是 mermaid 时画成图，不分大小写（swift-markdown 的
    /// `CodeBlock.language` 是整段 info string，含后面的附加说明）。
    package static func isDiagram(language: String?) -> Bool {
        guard let firstWord = language?.split(whereSeparator: \.isWhitespace).first else { return false }
        return firstWord.lowercased() == "mermaid"
    }

    /// 深色配色：mermaid 自带的 dark 主题文字、线条、连线标签底都是灰色，对比度不够；改用 base 主题配这套
    /// 颜色（取自 github-markdown.css 的深色 Primer 值）。文字接近白、节点边框用强调蓝、标签与节点底用深灰，
    /// 每对文字与底色 ≥ 7:1，线条与边框对深色页面 ≥ 3:1。分类色（饼图扇区、git 分支、思维导图与时间线色块）
    /// base 主题会从节点底色推导、全是近黑色，这里另配两组。
    package static let darkThemeVariables: [String: String] = baseDarkThemeVariables.merging(categoricalDarkThemeVariables) { first, _ in first }

    /// 饼图扇区与 git 分支：亮色，上面的文字用页面深色（≥ 7:1）。
    private static let darkCategoricalColors = [
        "#79c0ff", "#56d364", "#e3b341", "#ffa198", "#d2a8ff", "#ffa657",
        "#56d4dd", "#ff9bce", "#b1bac4", "#a5d6ff", "#7ee787", "#f2cc60",
    ]

    /// 思维导图与时间线色块（cScale）：偏深的饱和色，上面写白字（≥ 7:1）。这两种图的连接线用的是色块上的
    /// 文字色（cScaleLabel），所以文字色必须是浅的，连线才在深色页面上看得见。
    private static let darkSectionColors = [
        "#1d4f91", "#195a2e", "#664d00", "#8e1f24", "#5b3593", "#7a3e12",
        "#13575e", "#83265a", "#454c57", "#20457a", "#2d5a1f", "#5c4a14",
    ]

    private static let categoricalDarkThemeVariables: [String: String] = {
        var variables: [String: String] = [:]
        for (index, color) in darkSectionColors.enumerated() {
            variables["cScale\(index)"] = color
            variables["cScaleLabel\(index)"] = "#f0f6fc"
        }
        for (index, color) in darkCategoricalColors.enumerated() {
            variables["pie\(index + 1)"] = color
            if index < 8 {
                variables["git\(index)"] = color
                variables["gitBranchLabel\(index)"] = "#0d1117"
            }
        }
        return variables
    }()

    private static let baseDarkThemeVariables: [String: String] = [
        "background": "#0d1117",
        "textColor": "#f0f6fc",
        "lineColor": "#9198a1",
        "primaryColor": "#22272e",
        "primaryTextColor": "#f0f6fc",
        "primaryBorderColor": "#4493f8",
        "secondaryColor": "#2d333b",
        "secondaryTextColor": "#f0f6fc",
        "secondaryBorderColor": "#9198a1",
        "tertiaryColor": "#161b22",
        "tertiaryTextColor": "#f0f6fc",
        "tertiaryBorderColor": "#3d444d",
        "edgeLabelBackground": "#2d333b",
        "clusterBkg": "#161b22",
        "clusterBorder": "#656c76",
        "titleColor": "#f0f6fc",
        "noteBkgColor": "#3b2e0b",
        "noteTextColor": "#f0f6fc",
        "noteBorderColor": "#bb8009",
        "actorBkg": "#22272e",
        "actorBorder": "#4493f8",
        "actorTextColor": "#f0f6fc",
        "actorLineColor": "#9198a1",
        "signalColor": "#9198a1",
        "signalTextColor": "#f0f6fc",
        "labelBoxBkgColor": "#22272e",
        "labelBoxBorderColor": "#4493f8",
        "labelTextColor": "#f0f6fc",
        "loopTextColor": "#f0f6fc",
        "activationBkgColor": "#2d333b",
        "activationBorderColor": "#9198a1",
        "sequenceNumberColor": "#0d1117",
        "pieSectionTextColor": "#0d1117",
        "pieTitleTextColor": "#f0f6fc",
        "pieLegendTextColor": "#f0f6fc",
        "pieStrokeColor": "#0d1117",
        "pieOuterStrokeColor": "#3d444d",
        "pieOpacity": "1",
        "commitLabelColor": "#f0f6fc",
        "commitLabelBackground": "#2d333b",
        "tagLabelColor": "#0d1117",
        "tagLabelBackground": "#e3b341",
        "tagLabelBorder": "#bb8009",
        "taskBkgColor": "#1c3d6e",
        "taskBorderColor": "#4493f8",
        "taskTextColor": "#f0f6fc",
        "taskTextLightColor": "#f0f6fc",
        "taskTextDarkColor": "#f0f6fc",
        "taskTextOutsideColor": "#f0f6fc",
        "taskTextClickableColor": "#79c0ff",
        "activeTaskBkgColor": "#2a4a7a",
        "activeTaskBorderColor": "#79c0ff",
        "doneTaskBkgColor": "#30363d",
        "doneTaskBorderColor": "#656c76",
        "critBkgColor": "#67060c",
        "critBorderColor": "#f85149",
        "sectionBkgColor": "#161b22",
        "altSectionBkgColor": "#0d1117",
        "sectionBkgColor2": "#161b22",
        "excludeBkgColor": "#21262d",
        "gridColor": "#3d444d",
        "todayLineColor": "#f85149",
    ]

    /// `mermaid.initialize` 的参数（JSON）：不自动渲染、严格安全级别；浅色用 default 主题，深色用 base 主题
    /// 加 `darkThemeVariables`。app 的 Markdown 预览与 `peeky-mermaid` 共用这一份。
    package static func initializeOptionsJSON(appearance: PeekyPalette.Appearance) -> String {
        var options: [String: Any] = ["startOnLoad": false, "securityLevel": "strict"]
        switch appearance {
        case .light:
            options["theme"] = "default"
        case .dark:
            var variables: [String: Any] = darkThemeVariables
            variables["darkMode"] = true
            options["theme"] = "base"
            options["themeVariables"] = variables
        }
        guard let data = try? JSONSerialization.data(withJSONObject: options, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 从 PeekyCore 资源包读 mermaid.js（11.17.2 单文件构建，加载后是 `globalThis.mermaid`；
    /// 寻径见 `CoreResources`）。找不到时为 nil，Mermaid 块照旧显示成代码。
    package static func loadLibrary() -> String? {
        guard let url = CoreResources.url(forResource: "mermaid.min", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
