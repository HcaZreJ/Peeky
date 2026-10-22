import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 全文搜索可见样例
//
// `/` 进入输入（状态栏左侧显示 `/搜索词`），回车开始搜索：不区分英文大小写；文本、源码、XML、JSON
// 按格式化后的文本逐行搜，Markdown 搜排好版的文字（装饰不算，跨软换行的匹配拆成每行一段）。
// 结果分批到达，回车后跳到第一个不早于光标行的匹配；`n` / `N` 前后跳，到头从另一端继续并提示。
// JSON 的匹配在折叠里时展开到那一行。视口里的匹配铺底色，当前匹配颜色更深。Esc 先清选区再清搜索。
// 复制文件名改用 `F`（`n` 给了搜索）。

private func plainState(_ lines: [String], rows: Int = 10, columns: Int = 60) -> TUIState {
    var state = TUIState(size: TerminalSize(columns: columns, rows: rows), document: .loading(path: "notes.txt"))
    state.activeFile = URL(fileURLWithPath: "/repo/notes.txt")
    _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
        header: DocumentHeader(displayPath: "notes.txt", details: ""),
        store: LineStore(lines.joined(separator: "\n")),
        presentation: .plain
    ), generation: state.generation))
    return state
}

private func press(_ state: inout TUIState, _ key: Key, _ modifiers: KeyModifiers = []) -> [TUIEffect] {
    TUIReducer.reduce(&state, .input(.key(KeyPress(key: key, modifiers: modifiers))))
}

/// 输入 `/query` 并回车，取出搜索副作用，用搜索引擎算出结果后分 `batches` 批送回。
@discardableResult
private func search(_ state: inout TUIState, _ query: String, batches: Int = 1) -> [TUIEffect] {
    _ = press(&state, .character("/"))
    for character in query { _ = press(&state, .character(character)) }
    let effects = press(&state, .enter)
    guard let request = effects.compactMap({ effect -> (Int, Int, String, SearchCorpus)? in
        if case let .search(id, generation, query, corpus) = effect { return (id, generation, query, corpus) }
        return nil
    }).first else { return effects }
    let matches = SearchEngine.matches(in: request.3, query: request.2)
    let size = max((matches.count + batches - 1) / batches, 1)
    var all: [TUIEffect] = effects
    for start in stride(from: 0, to: max(matches.count, 1), by: size) {
        let batch = Array(matches[min(start, matches.count)..<min(start + size, matches.count)])
        let isComplete = start + size >= matches.count
        all += TUIReducer.reduce(&state, .searchResults(batch, id: request.0, generation: request.1, isComplete: isComplete, isTruncated: false))
    }
    return all
}

private func statusText(_ state: TUIState) -> String {
    FrameRenderer.render(state).rowText(state.size.rows - 1)
}

@Suite("Visible_search")
struct Visible_search {
    @Test("引擎：不区分英文大小写，一行多处，制表符按视觉列算")
    func engineFindsVisualColumns() {
        let store = LineStore("Foo foo\n\tfoo\nbar\n中文 foo")
        let matches = SearchEngine.matches(in: .lines(store), query: "FOO")
        #expect(matches == [
            SearchMatch(line: 0, columns: 0..<3),
            SearchMatch(line: 0, columns: 4..<7),
            SearchMatch(line: 1, columns: 4..<7),
            SearchMatch(line: 3, columns: 5..<8),
        ])
    }

    @Test("引擎：Markdown 搜排好版的文字，跨软换行的匹配拆成两段，装饰不算")
    func engineSearchesMarkdownRows() {
        let rendering = MarkdownLayout.render("- alpha beta gamma delta", width: 16, theme: .dark)
        let rows = rendering.rows.map { $0.spans.map(\.text).joined() }
        let wrapRow = try! #require(rows.firstIndex { $0.contains("gamma") })
        let matches = SearchEngine.matches(in: .markdown(rendering.rows), query: "beta gamma")
        #expect(matches.count == 2)
        #expect(matches.first?.isContinuation == false)
        #expect(matches.last?.isContinuation == true)
        #expect(matches.last?.line == wrapRow)
        #expect(SearchEngine.matches(in: .markdown(rendering.rows), query: "•").isEmpty)
    }

    @Test("/ 输入显示在状态栏；回车后分批到达的结果里跳到第一个不早于光标行的匹配")
    func enterJumpsToFirstMatchAfterCursor() {
        var current = plainState((0..<30).map { $0 == 2 || $0 == 15 || $0 == 20 ? "has needle \($0)" : "line \($0)" })
        current.viewport.cursor = 10
        _ = press(&current, .character("/"))
        _ = press(&current, .character("n"))
        _ = press(&current, .character("q"))
        #expect(statusText(current).hasPrefix(" /nq"))
        _ = press(&current, .backspace)
        _ = press(&current, .backspace)
        _ = press(&current, .backspace)
        search(&current, "needle", batches: 3)
        #expect(current.viewport.cursor == 15)
        #expect(statusText(current).contains("/needle 2/3"))
    }

    @Test("n / N 前后跳；同一行两处逐个跳；到头从另一端继续并提示")
    func nextAndPrevious() {
        var current = plainState(["a x x", "b", "c x"])
        search(&current, "x")
        #expect(current.search?.current == 0)
        _ = press(&current, .character("n"))
        #expect(current.search?.current == 1)
        #expect(current.viewport.cursor == 0)
        _ = press(&current, .character("n"))
        #expect(current.viewport.cursor == 2)
        _ = press(&current, .character("n"))
        #expect(current.viewport.cursor == 0)
        #expect(current.toast == "已到结尾，从开头继续")
        _ = press(&current, .character("N"))
        #expect(current.viewport.cursor == 2)
        #expect(current.toast == "已到开头，从结尾继续")
    }

    @Test("找不到时提示；没有搜索词时 n 提示按 /；F 复制文件名")
    func notFoundAndFileName() {
        var current = plainState(["alpha", "beta"])
        _ = press(&current, .character("n"))
        #expect(current.toast == "没有搜索词，按 / 搜索")
        search(&current, "zzz")
        #expect(current.toast == "找不到「zzz」")
        let copied = press(&current, .character("F")).contains(.copy(text: "notes.txt", description: "文件名"))
        #expect(copied)
    }

    @Test("JSON：匹配在折叠里时展开到那一行再跳过去")
    func jsonExpandsFoldToMatch() {
        let pretty = "{\n  \"a\": {\n    \"needle\": 1\n  },\n  \"b\": 2\n}"
        var current = TUIState(size: TerminalSize(columns: 60, rows: 10), document: .loading(path: "x.json"))
        _ = TUIReducer.reduce(&current, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "x.json", details: ""),
            store: LineStore(pretty),
            presentation: .json(structureIsValid: true),
            json: JSONView(prettyText: pretty, structureIsValid: true)
        ), generation: current.generation))
        current.viewport.cursor = 1
        _ = press(&current, .enter)
        guard case let .loaded(folded) = current.document else { Issue.record("没有读入"); return }
        #expect(folded.json?.isCollapsed(sourceLine: 1) == true)
        current.viewport.cursor = 0
        search(&current, "needle")
        guard case let .loaded(document) = current.document else { Issue.record("没有读入"); return }
        #expect(document.json?.isCollapsed(sourceLine: 1) == false)
        #expect(current.viewport.cursor == 2)
    }

    @Test("视口里的匹配铺底色，当前匹配颜色不同；Esc 先清选区，再清搜索")
    func highlightsAndEscape() {
        var current = plainState(["foo bar foo"])
        search(&current, "foo")
        let frame = FrameRenderer.render(current)
        let gutter = LineLayout.gutterWidth(lineCount: 1)
        let currentColor = frame[1, gutter].style.background
        let otherColor = frame[1, gutter + 8].style.background
        let plainColor = frame[1, gutter + 4].style.background
        #expect(currentColor != plainColor)
        #expect(otherColor != plainColor)
        #expect(currentColor != otherColor)

        current.selection = TextSelection(anchor: TextPoint(line: 0, column: 0), head: TextPoint(line: 0, column: 2))
        _ = press(&current, .escape)
        #expect(current.selection == nil)
        #expect(current.search != nil)
        _ = press(&current, .escape)
        #expect(current.search == nil)
        #expect(FrameRenderer.render(current)[1, gutter].style.background == plainColor)
    }
}
