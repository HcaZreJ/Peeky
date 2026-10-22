import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 多个打开的文件可见样例
//
// 从侧栏打开文件时在末尾新开一个（已经开着就切过去），各自保留视口与换行开关；切走的文件迟到的
// 结果丢掉，切回来时没读完的重读。x 关掉当前文件并切到右边的（没有就左边的），全关掉回到空白页；
// [ / ] 前后切换。侧栏第一个页签 Open 列出打开的文件，之后是「Recent」与此刻没打开的最近文件
// （打不开的变淡、不能选）。当前文件不在文件树下时换树根。文件第一次读进来时记进最近打开。

private let root = URL(fileURLWithPath: "/repo")
private let first = URL(fileURLWithPath: "/repo/a.txt")
private let second = URL(fileURLWithPath: "/repo/b.txt")

private func document(_ name: String, lines: Int = 40) -> OpenedDocument {
    OpenedDocument(
        header: DocumentHeader(displayPath: name, details: ""),
        store: LineStore((1...lines).map { "\(name) \($0)" }.joined(separator: "\n")),
        presentation: .plain
    )
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

private func loadEffects(_ effects: [TUIEffect]) -> [(URL, Int)] {
    effects.compactMap { effect in
        if case let .load(url, generation, _, _, _, _) = effect { return (url, generation) }
        return nil
    }
}

/// 启动时打开 a.txt 并读入；树根下有 a.txt、b.txt。
private func launched() -> TUIState {
    var state = TUIState.launching(size: TerminalSize(columns: 100, rows: 12), target: first, isDirectory: false, displayPath: "a.txt", treeRoot: root, targetLine: nil)
    _ = TUIReducer.reduce(&state, .launched)
    _ = TUIReducer.reduce(&state, .directoryListed(root, .entries([
        TreeEntry(name: "a.txt", url: first, isDirectory: false),
        TreeEntry(name: "b.txt", url: second, isDirectory: false),
    ])))
    _ = TUIReducer.reduce(&state, .loaded(document("a"), generation: state.generation))
    return state
}

/// 在正文里打开 b.txt 并读入。
private func openSecond(_ state: inout TUIState) {
    _ = TUIReducer.openFile(second, state: &state)
    _ = TUIReducer.reduce(&state, .loaded(document("b"), generation: state.generation))
}

private func recent(_ path: String, openable: Bool = true) -> RecentFiles.Item {
    let url = URL(fileURLWithPath: path)
    return RecentFiles.Item(path: path, name: url.lastPathComponent, location: "elsewhere", reason: openable ? nil : "File moved or deleted", tooltip: path, isOpenable: openable)
}

@Suite("Visible_tabs")
struct Visible_tabs {
    @Test("打开第二个文件在末尾新开并切过去；再打开已开着的文件只切换不重读；状态栏显示「文件 2/2」")
    func openAddsTab() {
        var state = launched()
        openSecond(&state)
        #expect(state.tabs.map(\.url) == [first, second])
        #expect(state.activeTabIndex == 1)
        #expect(FrameRenderer.render(state).rowText(11).contains("文件 2/2"))
        let effects = TUIReducer.openFile(first, state: &state)
        #expect(state.activeTabIndex == 0)
        #expect(loadEffects(effects).isEmpty)
        #expect(effects.contains(.checkFileStamp(first, generation: state.generation)))
    }

    @Test("切换时各自保留视口与换行开关，选区清掉")
    func tabsKeepTheirViewport() {
        var state = launched()
        state.viewport.cursor = 20
        state.wrapsLines = false
        openSecond(&state)
        #expect(state.viewport.cursor == 0)
        #expect(state.wrapsLines)
        state.selection = TextSelection(anchor: TextPoint(line: 0, column: 0), head: TextPoint(line: 0, column: 3))
        _ = press(&state, .character("["))
        #expect(state.activeFile == first)
        #expect(state.viewport.cursor == 20)
        #expect(!state.wrapsLines)
        #expect(state.selection == nil)
    }

    @Test("切走后迟到的读入结果丢掉，切回来时重新读")
    func lateResultsAreDroppedAndReloaded() {
        var state = launched()
        _ = TUIReducer.openFile(second, state: &state)
        let staleGeneration = state.generation
        _ = TUIReducer.openFile(first, state: &state)
        _ = TUIReducer.reduce(&state, .loaded(document("b"), generation: staleGeneration))
        guard case .loading = state.tabs[1].document else { Issue.record("切走的文件不该收下结果"); return }
        let effects = press(&state, .character("]"))
        let loads = loadEffects(effects)
        #expect(loads.count == 1)
        #expect(loads.first?.0 == second)
        #expect(loads.first.map { $0.1 > staleGeneration } == true)
    }

    @Test("x 关掉当前文件切到右边的（最右一个关掉时切到左边）；全关掉后回到空白页")
    func closeTabs() {
        var state = launched()
        openSecond(&state)
        _ = TUIReducer.openFile(URL(fileURLWithPath: "/repo/c.txt"), state: &state)
        _ = TUIReducer.openFile(second, state: &state)
        _ = press(&state, .character("x"))
        #expect(state.tabs.map(\.url?.lastPathComponent) == ["a.txt", "c.txt"])
        #expect(state.activeFile?.lastPathComponent == "c.txt")
        _ = press(&state, .character("x"))
        #expect(state.activeFile == first)
        _ = press(&state, .character("x"))
        #expect(state.tabs.isEmpty)
        #expect(FrameRenderer.render(state).rowText(1).contains("从左侧选择一个文件"))
    }

    @Test("Open 页：打开的文件（当前的加粗）、Recent 与没打开的最近文件；打不开的不能选；回车打开最近文件")
    func openPageListsTabsAndRecents() {
        var state = launched()
        openSecond(&state)
        _ = TUIReducer.reduce(&state, .recentFilesLoaded([recent(first.path), recent("/other/c.md"), recent("/gone/d.md", openable: false)]))
        _ = press(&state, .character("1"))
        #expect(state.sidebarTab == .open)
        #expect(state.focus == .sidebar)
        let frame = FrameRenderer.render(state)
        #expect(frame.rowText(1).hasPrefix(" Open  Files  Contents"))
        #expect(frame.rowText(2).hasPrefix(" a.txt"))
        #expect(frame.rowText(3).hasPrefix(" b.txt"))
        #expect(frame[3, 1].style.bold)
        #expect(frame.rowText(4).hasPrefix(" Recent"))
        #expect(frame.rowText(5).hasPrefix(" c.md  elsewhere"))
        #expect(frame.rowText(6).hasPrefix(" d.md  File moved"))
        #expect(frame[6, 1].style.dim)

        _ = press(&state, .character("j"))
        _ = press(&state, .character("j"))
        // d.md 打不开、不能选：第二次 j 停在 c.md
        #expect(state.sidebar?.openSelection == 3)
        let effects = press(&state, .enter)
        #expect(state.activeFile?.path == "/other/c.md")
        #expect(state.focus == .content)
        #expect(loadEffects(effects).first?.0.path == "/other/c.md")
    }

    @Test("当前文件不在文件树下：找新树根，找到后重建文件树、展开到它并监听新树根")
    func treeFollowsFileOutsideRoot() {
        var state = launched()
        let outside = URL(fileURLWithPath: "/other/docs/c.md")
        let effects = TUIReducer.openFile(outside, state: &state)
        #expect(effects.contains(.discoverTreeRoot(outside)))
        let otherRoot = URL(fileURLWithPath: "/other")
        let follow = TUIReducer.reduce(&state, .treeRootDiscovered(root: otherRoot, repoRoot: otherRoot, file: outside))
        #expect(state.sidebar?.tree.root == otherRoot)
        #expect(state.sidebar?.selectedPath == outside.path)
        #expect(state.repoRoot == otherRoot)
        #expect(follow.contains(.listDirectory(URL(fileURLWithPath: "/other/docs", isDirectory: true))))
        #expect(follow.contains(.watch(root: otherRoot)))
    }

    @Test("文件第一次读进来时记进最近打开，重读不记")
    func recordsRecentOnFirstLoad() {
        var state = TUIState.launching(size: TerminalSize(columns: 100, rows: 12), target: first, isDirectory: false, displayPath: "a.txt", treeRoot: root, targetLine: nil)
        #expect(TUIReducer.reduce(&state, .launched).contains(.loadRecentFiles))
        #expect(TUIReducer.reduce(&state, .loaded(document("a"), generation: state.generation)).contains(.recordRecentFile(first)))
        _ = press(&state, .character("r"))
        #expect(!TUIReducer.reduce(&state, .loaded(document("a"), generation: state.generation)).contains(.recordRecentFile(first)))
    }
}
