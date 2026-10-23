import Foundation
import Testing
@testable import PeekyCore

// MARK: - Mermaid 配色可见样例
//
// 深色下用 mermaid 的 base 主题加自定配色（mermaid 自带的 dark 主题文字、线条、标签底都是灰色，看不清）：
// 每一对「文字 / 它所在的底色」对比度不低于 7:1（WCAG AAA），线条与边框对页面底色不低于 3:1。
// 页面底色取 app 深色背景 #0d1117 与纯黑（终端版 PNG 是透明底，落在终端自己的深色背景上）。
// 浅色沿用 mermaid 的 default 主题。

/// WCAG 2.x 相对亮度对比度。
private func contrast(_ first: String, _ second: String) throws -> Double {
    func luminance(_ hex: String) throws -> Double {
        let value = try #require(UInt32(hex.dropFirst(), radix: 16))
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { Double($0) / 255 }
        let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
    let (a, b) = (try luminance(first), try luminance(second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@Suite("Visible_mermaidTheme")
struct Visible_mermaidTheme {
    @Test("深色：每对文字与底色对比度 ≥ 7:1")
    func darkTextContrast() throws {
        let colors = MermaidDiagram.darkThemeVariables
        let pairs: [(text: String, background: String)] = [
            ("primaryTextColor", "primaryColor"),
            ("textColor", "background"),
            ("textColor", "edgeLabelBackground"),
            ("actorTextColor", "actorBkg"),
            ("signalTextColor", "background"),
            ("noteTextColor", "noteBkgColor"),
            ("titleColor", "clusterBkg"),
            ("labelTextColor", "labelBoxBkgColor"),
        ] as [(text: String, background: String)]
        for pair in pairs {
            let text = try #require(colors[pair.text], "缺 \(pair.text)")
            let background = try #require(colors[pair.background], "缺 \(pair.background)")
            #expect(try contrast(text, background) >= 7, "\(pair.text) \(text) / \(pair.background) \(background)")
        }
    }

    @Test("深色：分类色（饼图扇区、思维导图 / 时间线色块、git 分支）各不相同，上面的文字对比度 ≥ 7:1")
    func darkCategoricalContrast() throws {
        let colors = MermaidDiagram.darkThemeVariables
        var pairs: [(text: String, background: String)] = []
        for index in 0..<12 {
            pairs.append(("pieSectionTextColor", "pie\(index + 1)"))
            pairs.append(("cScaleLabel\(index)", "cScale\(index)"))
        }
        for index in 0..<8 {
            pairs.append(("gitBranchLabel\(index)", "git\(index)"))
        }
        pairs.append(("pieTitleTextColor", "background"))
        pairs.append(("pieLegendTextColor", "background"))
        pairs.append(("commitLabelColor", "commitLabelBackground"))
        for pair in pairs {
            let text = try #require(colors[pair.text], "缺 \(pair.text)")
            let background = try #require(colors[pair.background], "缺 \(pair.background)")
            #expect(try contrast(text, background) >= 7, "\(pair.text) \(text) / \(pair.background) \(background)")
        }
        let slices = (1...12).compactMap { colors["pie\($0)"] }
        #expect(Set(slices).count == 12)
    }

    @Test("深色：甘特图各种任务条上的文字对比度 ≥ 7:1")
    func darkGanttContrast() throws {
        let colors = MermaidDiagram.darkThemeVariables
        let pairs: [(text: String, background: String)] = [
            ("taskTextColor", "taskBkgColor"),
            ("taskTextDarkColor", "activeTaskBkgColor"),
            ("taskTextDarkColor", "doneTaskBkgColor"),
            ("taskTextDarkColor", "critBkgColor"),
            ("taskTextOutsideColor", "background"),
            ("taskTextDarkColor", "sectionBkgColor"),
            ("taskTextDarkColor", "altSectionBkgColor"),
        ] as [(text: String, background: String)]
        for pair in pairs {
            let text = try #require(colors[pair.text], "缺 \(pair.text)")
            let background = try #require(colors[pair.background], "缺 \(pair.background)")
            #expect(try contrast(text, background) >= 7, "\(pair.text) \(text) / \(pair.background) \(background)")
        }
    }

    @Test("深色：线条与边框对 app 深色背景和纯黑都 ≥ 3:1")
    func darkLineContrast() throws {
        let colors = MermaidDiagram.darkThemeVariables
        // 时间线的连接线用 cScaleLabel 色画在页面底上
        for name in ["lineColor", "primaryBorderColor", "signalColor", "actorBorder", "clusterBorder", "cScaleLabel0"] {
            let color = try #require(colors[name], "缺 \(name)")
            for page in ["#0d1117", "#000000"] {
                #expect(try contrast(color, page) >= 3, "\(name) \(color) / \(page)")
            }
        }
    }

    @Test("初始化参数：深色用 base 主题 + darkMode + 自定配色，浅色用 default；都关掉自动渲染并取严格安全级别")
    func initializeOptions() throws {
        let dark = try #require(JSONSerialization.jsonObject(with: Data(MermaidDiagram.initializeOptionsJSON(appearance: .dark).utf8)) as? [String: Any])
        #expect(dark["theme"] as? String == "base")
        #expect(dark["startOnLoad"] as? Bool == false)
        #expect(dark["securityLevel"] as? String == "strict")
        let variables = try #require(dark["themeVariables"] as? [String: Any])
        #expect(variables["darkMode"] as? Bool == true)
        #expect(variables["primaryTextColor"] as? String == MermaidDiagram.darkThemeVariables["primaryTextColor"])

        let light = try #require(JSONSerialization.jsonObject(with: Data(MermaidDiagram.initializeOptionsJSON(appearance: .light).utf8)) as? [String: Any])
        #expect(light["theme"] as? String == "default")
        #expect(light["themeVariables"] == nil)
        #expect(light["securityLevel"] as? String == "strict")
    }
}
