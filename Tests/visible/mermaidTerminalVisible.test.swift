import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 终端版 Mermaid 图可见样例
//
// 能显示图片时，mermaid 代码块先按代码显示，同时记下要画的源码（键是「明暗 + 源码」的散列）；
// 运行时请 app 包里的 Peeky 画成 PNG，结果回来后按本地图片的占格规则排成占位符行，复制得到
// Mermaid 源码；画不出来的照旧显示代码。渲染程序是 app 包 Contents/Helpers 里（开发构建里与 peek-tui
// 同目录）的 peeky-mermaid。

private let cell = PixelSize(width: 10, height: 20)
private let base = URL(fileURLWithPath: "/docs", isDirectory: true)
private let code = "graph TD\n  A-->B"
private let source = "intro\n\n```mermaid\n\(code)\n```\n\n```swift\nlet a = 1\n```"

private func rendering(diagrams: [String: MermaidImage] = [:], appearance: PeekyPalette.Appearance = .dark) -> MarkdownRendering {
    MarkdownLayout.render(
        source,
        width: 44,
        theme: .forAppearance(appearance),
        images: MarkdownImageContext(cell: cell, baseDirectory: base, diagrams: diagrams)
    )
}

private func rowText(_ row: MarkdownRow) -> String {
    row.spans.map(\.text).joined()
}

@Suite("Visible_mermaidTerminal")
struct Visible_mermaidTerminal {
    @Test("还没画好：按代码显示，记下要画的 mermaid 源码（只记 mermaid 块）；不能显示图片时不记")
    func pendingDiagramShowsCode() {
        let laidOut = rendering()
        #expect(laidOut.rows.contains { rowText($0).contains("A-->B") })
        #expect(laidOut.diagramSources == [
            MarkdownDiagramSource(key: MarkdownDiagramSource.key(code: code, appearance: .dark), code: code, appearance: .dark),
        ])
        #expect(MarkdownLayout.render(source, width: 44, theme: .dark).diagramSources.isEmpty)
    }

    @Test("键随明暗与源码变化")
    func keyDependsOnAppearanceAndCode() {
        let dark = MarkdownDiagramSource.key(code: code, appearance: .dark)
        #expect(dark == MarkdownDiagramSource.key(code: code, appearance: .dark))
        #expect(dark != MarkdownDiagramSource.key(code: code, appearance: .light))
        #expect(dark != MarkdownDiagramSource.key(code: code + " ", appearance: .dark))
    }

    @Test("画好了：排成占位符行（占格同本地图片），复制得到 Mermaid 源码；后面的代码块照旧")
    func renderedDiagramBecomesImage() throws {
        let key = MarkdownDiagramSource.key(code: code, appearance: .dark)
        let laidOut = rendering(diagrams: [key: MermaidImage(path: "/tmp/d.png", size: PixelSize(width: 200, height: 100))])

        let imageRows = laidOut.rows.filter { $0.image != nil }
        let image = try #require(imageRows.first?.image)
        #expect(image.content == .file(path: "/tmp/d.png"))
        #expect(image.columns == 20 && image.rows == 5)
        #expect(imageRows.count == 5)
        #expect(imageRows.enumerated().allSatisfy { index, row in rowText(row) == "  " + ImagePlaceholder.rowText(row: index, columns: 20) })
        #expect(!laidOut.rows.contains { rowText($0).contains("A-->B") })
        #expect(laidOut.rows.contains { rowText($0).contains("let a = 1") })

        let first = try #require(laidOut.rows.firstIndex { $0.image != nil })
        let selection = TextSelection(anchor: TextPoint(line: first, column: 0), head: TextPoint(line: first + 4, column: 30))
        #expect(SelectionText.markdownText(selection, rows: laidOut.rows) == code)
    }

    @Test("画不出来（尺寸为空）：照旧按代码显示；明暗不同的图不拿来用")
    func unreadableOrOtherAppearanceFallsBackToCode() {
        let key = MarkdownDiagramSource.key(code: code, appearance: .dark)
        let unreadable = rendering(diagrams: [key: MermaidImage(path: "/tmp/d.png", size: .unreadable)])
        #expect(!unreadable.rows.contains { $0.image != nil })
        #expect(unreadable.rows.contains { rowText($0).contains("A-->B") })

        let light = rendering(diagrams: [key: MermaidImage(path: "/tmp/d.png", size: PixelSize(width: 200, height: 100))], appearance: .light)
        #expect(!light.rows.contains { $0.image != nil })
    }

    @Test("reducer：排版里有没画的图就请运行时去画，不重复请求；结果回来后带着图重排；过期结果丢弃")
    func reducerRequestsAndMergesDiagrams() throws {
        var state = TUIState(size: TerminalSize(columns: 60, rows: 20), document: .loading(path: "a.md"))
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "a.md", details: ""),
            store: LineStore(source),
            presentation: .markdown,
            markdown: MarkdownLayout.render(source, width: 60, theme: .dark),
            baseDirectory: base
        ), generation: state.generation))
        _ = TUIReducer.reduce(&state, .input(.terminalName("kitty(0.49.2)")))
        _ = TUIReducer.reduce(&state, .input(.cellPixelSize(width: 10, height: 20)))
        let relayout = TUIReducer.reduce(&state, .input(.graphicsReply(id: TUIReducer.graphicsProbeID, message: "OK")))
        guard case let .layoutMarkdown(_, _, _, _, _, _, images) = relayout.first else { Issue.record("没有重排"); return }

        let laidOut = MarkdownLayout.render(source, width: 60, theme: .dark, images: images)
        let request = TUIReducer.reduce(&state, .markdownLaidOut(laidOut, generation: state.generation))
        #expect(request.contains(.renderDiagrams(laidOut.diagramSources, generation: state.generation)))
        let again = TUIReducer.reduce(&state, .markdownLaidOut(laidOut, generation: state.generation))
        #expect(!again.contains { if case .renderDiagrams = $0 { return true } else { return false } })

        let key = MarkdownDiagramSource.key(code: code, appearance: .dark)
        let rendered = [key: MermaidImage(path: "/tmp/d.png", size: PixelSize(width: 200, height: 100))]
        #expect(TUIReducer.reduce(&state, .diagramsRendered(rendered, generation: state.generation - 1)).isEmpty)
        let withDiagram = TUIReducer.reduce(&state, .diagramsRendered(rendered, generation: state.generation))
        guard case let .layoutMarkdown(_, _, _, _, _, _, withImages) = withDiagram.first else { Issue.record("没有带图重排"); return }
        #expect(withImages?.diagrams == rendered)
    }

    @Test("渲染程序：app 包里找 Contents/Helpers/peeky-mermaid，开发构建里找同目录的；都没有就不画")
    func rendererNextToTerminalBinary() {
        let bundled = "/Applications/Peeky.app/Contents/Helpers/peeky-mermaid"
        #expect(DiagramRenderer.executable(nextTo: "/Applications/Peeky.app/Contents/MacOS/peek-tui", isExecutable: { $0 == bundled }) == bundled)
        let development = "/repo/.build/out/Products/Debug/peeky-mermaid"
        #expect(DiagramRenderer.executable(nextTo: "/repo/.build/out/Products/Debug/peek-tui", isExecutable: { $0 == development }) == development)
        #expect(DiagramRenderer.executable(nextTo: "/repo/.build/out/Products/Debug/peek-tui", isExecutable: { _ in false }) == nil)
    }
}
