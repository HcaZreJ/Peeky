import Foundation
import PeekyCore

/// 全文搜索：`/` 输入、结果到达后跳转、n / N 前后跳。
///
/// 匹配按「搜索坐标」记行：文本与 JSON 是源行（格式化后文本的行），Markdown 是排版行；
/// 与显示行之间的换算只在 JSON 折叠时不是恒等。
extension TUIReducer {
    static let noQueryToast = "没有搜索词，按 / 搜索"
    static let searchingToast = "正在搜索…"
    static let wrappedToStartToast = "已到结尾，从开头继续"
    static let wrappedToEndToast = "已到开头，从结尾继续"
    /// 匹配超过上限、往后找不到时：后面也许还有，只是没记下
    static let truncatedWrapToast = "只记了前 \(SearchEngine.maximumMatches / 10_000) 万处匹配，从开头继续"

    static func notFoundToast(_ query: String) -> String { "找不到「\(query)」" }

    // MARK: - 输入

    /// `/` 之后：字符累积（含空格），退格删一位（删空即取消），回车搜索（输入为空时重搜上一个词），
    /// Esc / Ctrl-C 取消，其余键忽略。
    static func handleSearchInput(_ press: KeyPress, input: String, state: inout TUIState) -> [TUIEffect] {
        switch (press.key, press.modifiers) {
        case let (.character(character), []):
            state.searchInput = input + String(character)
        case (.backspace, _):
            state.searchInput = input.isEmpty ? nil : String(input.dropLast())
        case (.enter, _):
            state.searchInput = nil
            guard let query = input.isEmpty ? state.search?.query : input, case let .loaded(document) = state.document else { return [] }
            return startSearch(query, state: &state, jumpFrom: searchLine(forDisplayLine: state.viewport.cursor, document: document))
        case (.escape, _), (.character("c"), .control):
            state.searchInput = nil
        default:
            break
        }
        return []
    }

    /// 输入搜索词时粘贴：接在后面，换行去掉。
    static func pasteIntoSearchInput(_ text: String, state: inout TUIState) {
        guard let input = state.searchInput else { return }
        state.searchInput = input + text.filter { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
    }

    // MARK: - 发起与结果

    /// 发起搜索：旧结果作废，结果以 `.searchResults` 分批送回；`jumpFrom` 非 nil 时到达后跳到第一个不早于它的匹配。
    static func startSearch(_ query: String, state: inout TUIState, jumpFrom: Int?) -> [TUIEffect] {
        guard case let .loaded(document) = state.document else { return [] }
        state.searchCount += 1
        state.search = SearchState(query: query, id: state.searchCount, pendingJumpFrom: jumpFrom)
        return [.search(id: state.searchCount, generation: state.generation, query: query, corpus: searchCorpus(document))]
    }

    /// 文档内容或排版变了：用同一个词重搜（不跳转）。
    static func rerunSearch(_ state: inout TUIState) -> [TUIEffect] {
        guard let query = state.search?.query else { return [] }
        return startSearch(query, state: &state, jumpFrom: nil)
    }

    static func searchCorpus(_ document: OpenedDocument) -> SearchCorpus {
        if let rows = document.markdown?.rows { return .markdown(rows) }
        return .lines(document.store)
    }

    /// 显示行在搜索坐标里的行：JSON 换成源行，其余不变。
    static func searchLine(forDisplayLine line: Int, document: OpenedDocument) -> Int {
        document.json?.sourceLine(forDisplayLine: line) ?? line
    }

    /// 一批结果到达：接到已有结果后面；回车后还没跳过去时，跳到第一个不早于光标行的匹配；
    /// 全部到达仍没有这样的匹配时回到第一个匹配，一个都没有时提示找不到。
    static func searchResultsArrived(_ matches: [SearchMatch], id: Int, isComplete: Bool, isTruncated: Bool, state: inout TUIState) -> [TUIEffect] {
        guard var search = state.search, search.id == id else { return [] }
        let firstNew = search.matches.count
        search.matches += matches
        search.isComplete = isComplete
        search.isTruncated = search.isTruncated || isTruncated
        state.search = search
        guard let from = search.pendingJumpFrom else { return [] }
        if let index = search.matches[firstNew...].firstIndex(where: { !$0.isContinuation && $0.line >= from }) {
            return jumpToMatch(index, state: &state)
        }
        guard isComplete else { return [] }
        state.search?.pendingJumpFrom = nil
        guard let first = search.matches.firstIndex(where: { !$0.isContinuation }) else {
            return [showToast(notFoundToast(search.query), state: &state)]
        }
        return jumpToMatch(first, state: &state) + [showToast(search.isTruncated ? truncatedWrapToast : wrappedToStartToast, state: &state)]
    }

    // MARK: - 跳转

    /// n / N：当前匹配在光标行上时跳到它的下一处 / 上一处，否则跳到光标行之后 / 之前最近的一处；
    /// 到头了从另一端继续并提示。
    static func stepSearch(forward: Bool, state: inout TUIState) -> [TUIEffect] {
        guard let search = state.search else { return [showToast(noQueryToast, state: &state)] }
        guard case let .loaded(document) = state.document else { return [] }
        let starts = search.matches.indices.filter { !search.matches[$0].isContinuation }
        guard let first = starts.first, let last = starts.last else {
            return [showToast(search.isComplete ? notFoundToast(search.query) : searchingToast, state: &state)]
        }
        let cursorLine = searchLine(forDisplayLine: state.viewport.cursor, document: document)
        let target: Int?
        if let current = search.current, search.matches[current].line == cursorLine, let position = starts.firstIndex(of: current) {
            target = forward ? starts[safe: position + 1] : starts[safe: position - 1]
        } else if forward {
            target = starts.first { search.matches[$0].line > cursorLine || (search.current == nil && search.matches[$0].line == cursorLine) }
        } else {
            target = starts.last { search.matches[$0].line < cursorLine }
        }
        if let target { return jumpToMatch(target, state: &state) }
        let wrapped = forward ? first : last
        let toast = !forward ? wrappedToEndToast : search.isTruncated ? truncatedWrapToast : wrappedToStartToast
        return jumpToMatch(wrapped, state: &state) + [showToast(toast, state: &state)]
    }

    /// 把光标移到第 `index` 段匹配所在的行：JSON 里先展开包住它的折叠；那一行已在视口里时只移光标，
    /// 否则让它落在视口上部三分之一处；不换行时水平滚到匹配露出来。
    static func jumpToMatch(_ index: Int, state: inout TUIState) -> [TUIEffect] {
        guard var search = state.search, search.matches.indices.contains(index), case var .loaded(document) = state.document else { return [] }
        let match = search.matches[index]
        search.current = index
        search.pendingJumpFrom = nil
        state.search = search
        var displayLine = match.line
        if var json = document.json {
            let topSource = json.sourceLine(forDisplayLine: state.viewport.top.line)
            if json.reveal(sourceLine: match.line, sourceText: document.store.text) {
                document.json = json
                state.document = .loaded(document)
                state.selection = nil
                state.viewport.top = ScrollPosition(line: json.displayLine(forSourceLine: topSource), row: 0)
            }
            displayLine = json.displayLine(forSourceLine: match.line)
        }
        withLayout(&state) { viewport, layout, height in
            let isVisible = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows).contains { $0?.line == displayLine }
            if isVisible {
                viewport.moveCursor(to: displayLine, lineCount: layout.lineCount, height: height, rows: layout.rows)
            } else {
                viewport.jump(to: displayLine, lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
            let visibleColumns = viewport.horizontalOffset..<(viewport.horizontalOffset + layout.contentWidth)
            if !layout.wrapsLines, !visibleColumns.contains(match.columns.lowerBound) || match.columns.upperBound > visibleColumns.upperBound {
                viewport.horizontalOffset = max(match.columns.lowerBound - layout.contentWidth / 4, 0)
            }
        }
        return []
    }

    // MARK: - 按键

    /// `n` / `N`；不是这两个键时返回 nil。
    static func handleSearchKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect]? {
        switch (press.key, press.modifiers) {
        case (.character("n"), []):
            return stepSearch(forward: true, state: &state)
        case (.character("N"), []):
            return stepSearch(forward: false, state: &state)
        default:
            return nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
