import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 侧栏可见样例
//
// 侧栏两个页签：Files（文件树）与 Contents（Markdown 1–4 级标题大纲）。树根是版本库根
// （没有就是文件所在目录）；启动时展开当前文件的各级父目录并选中它。目录在前、文件在后，
// 每层缩进 2 列，祖先的导轨画在祖先自己的三角那一列，选中项所在分支那一列加亮；读不了的
// 目录展开后显示「(无法读取)」。侧栏里回车：目录展开 / 收起，文件在正文里打开并把焦点交回正文。
// 终端窄于 80 列时侧栏默认收起，`s` 显示 / 收起，正文随之变宽变窄。非 Markdown 文件选
// Contents 时回退到 Files，选择保留到下一个 Markdown 文件。磁盘变化只重新列举已展开的目录。

private let root = URL(fileURLWithPath: "/repo")
private let activeFile = URL(fileURLWithPath: "/repo/src/app/main.swift")

private func entry(_ path: String, directory: Bool = false) -> TreeEntry {
    let url = URL(fileURLWithPath: path, isDirectory: directory)
    return TreeEntry(name: url.lastPathComponent, url: url, isDirectory: directory)
}

private func listed(_ state: inout TUIState, _ directory: String, _ entries: [TreeEntry]) {
    _ = TUIReducer.reduce(&state, .directoryListed(URL(fileURLWithPath: directory, isDirectory: true), .entries(entries)))
}

private func launchedState(columns: Int = 100, rows: Int = 16) -> TUIState {
    var state = TUIState.launching(
        size: TerminalSize(columns: columns, rows: rows),
        target: activeFile,
        isDirectory: false,
        displayPath: "repo/src/app/main.swift",
        treeRoot: root,
        targetLine: nil
    )
    _ = TUIReducer.reduce(&state, .launched)
    listed(&state, "/repo", [entry("/repo/src", directory: true), entry("/repo/README.md")])
    listed(&state, "/repo/src", [entry("/repo/src/app", directory: true), entry("/repo/src/util.swift")])
    listed(&state, "/repo/src/app", [entry("/repo/src/app/main.swift")])
    return state
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

private func listedPaths(_ effects: [TUIEffect]) -> [String] {
    effects.compactMap { effect in
        if case let .listDirectory(url) = effect { return url.path }
        return nil
    }
}

private func markdownDocument(_ text: String, width: Int) -> OpenedDocument {
    OpenedDocument(
        header: DocumentHeader(displayPath: "notes.md", details: ""),
        store: LineStore(text),
        presentation: .markdown,
        markdown: MarkdownLayout.render(text, width: width, theme: .dark)
    )
}

@Suite("Visible_sidebar")
struct Visible_sidebar {
    @Test("启动时读入文件、列举树根与各级父目录并开始监听；当前文件所在分支展开，导轨画在祖先三角那一列")
    func launchRevealsActiveFile() {
        var state = TUIState.launching(
            size: TerminalSize(columns: 100, rows: 16),
            target: activeFile,
            isDirectory: false,
            displayPath: "repo/src/app/main.swift",
            treeRoot: root,
            targetLine: nil
        )
        let effects = TUIReducer.reduce(&state, .launched)
        #expect(effects.contains(.load(url: activeFile, generation: state.generation, width: state.contentColumns, isReload: false, appearance: .dark)))
        #expect(listedPaths(effects) == ["/repo", "/repo/src", "/repo/src/app"])
        #expect(effects.contains(.watch(root: root)))

        state = launchedState()
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(1).hasPrefix(" Files  Contents"))
        #expect(frame.rowText(2).hasPrefix(" ▾ src"))
        #expect(frame.rowText(3).hasPrefix(" │ ▾ app"))
        #expect(frame.rowText(4).hasPrefix(" │ │   main.swift"))
        #expect(frame.rowText(5).hasPrefix(" │   util.swift"))
        #expect(frame.rowText(6).hasPrefix("   README.md"))
        // 选中的是当前文件，它的直接父目录 app 那一列加亮
        #expect(frame[4, 3].style.foreground == TerminalPalette.color(.gutterDisclosure))
        #expect(frame[4, 1].style.foreground == TerminalPalette.color(.treeIndentGuide))
        #expect(frame[4, 7].style.bold)
    }

    @Test("侧栏里回车：目录收起 / 展开（展开时重新列举），文件在正文里打开、焦点回到正文")
    func enterInSidebar() {
        var state = launchedState()
        _ = press(&state, .tab)
        #expect(state.focus == .sidebar)
        _ = press(&state, .character("k"))
        _ = press(&state, .enter)
        #expect(!FrameRenderer.render(state).rowText(4).contains("main.swift"))
        #expect(listedPaths(press(&state, .enter)) == ["/repo/src/app"])
        #expect(FrameRenderer.render(state).rowText(4).contains("main.swift"))

        _ = press(&state, .character("j"))
        _ = press(&state, .character("j"))
        let generation = state.generation
        let effects = press(&state, .enter)
        let utility = URL(fileURLWithPath: "/repo/src/util.swift")
        #expect(effects.contains(.load(url: utility, generation: generation + 1, width: state.contentColumns, isReload: false, appearance: .dark)))
        #expect(state.activeFile == utility)
        #expect(state.focus == .content)
    }

    @Test("终端窄于 80 列时侧栏默认收起；s 显示后正文变窄，Markdown 按新宽度重排")
    func narrowTerminalHidesSidebar() {
        var state = launchedState(columns: 70)
        #expect(state.sidebar?.isVisible == false)
        #expect(state.contentColumns == 70)
        _ = TUIReducer.reduce(&state, .loaded(markdownDocument("# Title\n\ntext", width: 70), generation: state.generation))
        let effects = press(&state, .character("s"))
        #expect(state.sidebar?.isVisible == true)
        let width = SidebarState.width(forColumns: 70)
        #expect(state.contentColumns == 70 - width - 1)
        #expect(effects.contains { effect in
            if case let .layoutMarkdown(_, _, layoutWidth, _, _, _) = effect { return layoutWidth == state.contentColumns }
            return false
        })
        #expect(FrameRenderer.render(state)[2, width].text == "│")
    }

    @Test("Contents 页签列出 1–4 级标题并按级缩进；回车把标题所在的排版行放到视口顶端")
    func outlineJumpsToHeading() {
        var state = launchedState()
        let paragraphs = Array(repeating: "para", count: 30).joined(separator: "\n\n")
        let text = "# A\n\n## B\n\n" + paragraphs + "\n\n### C\n\n" + paragraphs + "\n\n##### E"
        _ = TUIReducer.reduce(&state, .loaded(markdownDocument(text, width: state.contentColumns), generation: state.generation))
        _ = press(&state, .character("2"))
        #expect(state.focus == .sidebar)
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(2).hasPrefix(" A "))
        #expect(frame.rowText(3).hasPrefix("   B "))
        #expect(frame.rowText(4).hasPrefix("     C "))
        #expect(!frame.rowText(5).contains("E"))

        _ = press(&state, .character("j"))
        _ = press(&state, .character("j"))
        _ = press(&state, .enter)
        guard case let .loaded(document) = state.document, let rows = document.markdown?.rows else {
            Issue.record("not loaded"); return
        }
        let headingRow = rows.firstIndex { $0.anchor == "c" }
        #expect(state.viewport.top.line == headingRow)
        #expect(state.viewport.cursor == headingRow)
        #expect(state.focus == .content)
    }

    @Test("非 Markdown 文件选 Contents 时回退到 Files，选择保留到下一个 Markdown 文件")
    func contentsFallsBackForPlainFiles() {
        var state = launchedState()
        _ = TUIReducer.reduce(&state, .loaded(markdownDocument("# A", width: state.contentColumns), generation: state.generation))
        _ = press(&state, .character("2"))
        #expect(state.sidebarTab == .contents)
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "main.swift", details: ""),
            store: LineStore("let a = 1"),
            presentation: .plain
        ), generation: state.generation))
        #expect(state.sidebarTab == .files)
        #expect(FrameRenderer.render(state).rowText(2).hasPrefix(" ▾ src"))
        _ = TUIReducer.reduce(&state, .loaded(markdownDocument("# B", width: state.contentColumns), generation: state.generation))
        #expect(state.sidebarTab == .contents)
    }

    @Test("磁盘变化只重新列举已展开的目录；新列表到达后展开状态与选中项不变")
    func refreshKeepsExpansionAndSelection() {
        var state = launchedState()
        #expect(listedPaths(TUIReducer.reduce(&state, .filesChanged(paths: ["/repo/src"], mustScanSubDirectories: false))) == ["/repo/src"])
        #expect(TUIReducer.reduce(&state, .filesChanged(paths: ["/repo/docs"], mustScanSubDirectories: false)).isEmpty)
        listed(&state, "/repo/src", [entry("/repo/src/app", directory: true), entry("/repo/src/new.swift"), entry("/repo/src/util.swift")])
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(4).hasPrefix(" │ │   main.swift"))
        #expect(frame.rowText(5).hasPrefix(" │   new.swift"))
        #expect(state.sidebar?.selectedPath == activeFile.path)
        // 当前文件所在目录变了：另外检查文件戳
        let effects = TUIReducer.reduce(&state, .filesChanged(paths: ["/repo/src/app"], mustScanSubDirectories: false))
        #expect(effects.contains(.checkFileStamp(activeFile, generation: state.generation)))
    }

    @Test("打开目录：侧栏显示并获得焦点，正文提示从左侧选择文件；读不了的目录展开后显示（无法读取）")
    func directoryArgument() {
        var state = TUIState.launching(
            size: TerminalSize(columns: 60, rows: 12),
            target: root,
            isDirectory: true,
            displayPath: "repo",
            treeRoot: root,
            targetLine: nil
        )
        let effects = TUIReducer.reduce(&state, .launched)
        #expect(!effects.contains { if case .load = $0 { return true } else { return false } })
        #expect(state.sidebar?.isVisible == true)
        #expect(state.focus == .sidebar)
        listed(&state, "/repo", [entry("/repo/secret", directory: true), entry("/repo/README.md")])
        _ = press(&state, .enter)
        _ = TUIReducer.reduce(&state, .directoryListed(URL(fileURLWithPath: "/repo/secret", isDirectory: true), .unreadable))
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(3).hasPrefix(" │   (无法读取)"))
        #expect(frame.rowText(1).contains("从左侧选择一个文件"))
    }

    @Test("点侧栏里的文件就打开它；点正文把焦点交回正文")
    func mouseInSidebar() {
        var state = launchedState()
        let effects = TUIReducer.reduce(&state, .input(.mouse(MouseEvent(kind: .press(.left), row: 6, column: 4, modifiers: []))))
        let readme = URL(fileURLWithPath: "/repo/README.md")
        #expect(effects.contains(.load(url: readme, generation: state.generation, width: state.contentColumns, isReload: false, appearance: .dark)))
        #expect(state.focus == .sidebar)
        _ = TUIReducer.reduce(&state, .input(.mouse(MouseEvent(kind: .press(.left), row: 3, column: 60, modifiers: []))))
        #expect(state.focus == .content)
    }
}
