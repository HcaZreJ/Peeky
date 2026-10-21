import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 重读锚定可见样例
//
// 当前文件所在目录有变化时，运行时查一次文件戳（大小 + 修改时间），与读入时的不同才重读；
// `r` 直接重读。重读后视口顶端与光标留在原来的源行，文件变短时钳到最后一行。
// 文件被删除时正文显示读取失败；文件再出现时自动重读并回到原来的位置。

private let file = URL(fileURLWithPath: "/repo/log.txt")
private let firstStamp = FileStamp(size: 100, modifiedAt: Date(timeIntervalSince1970: 1_000))
private let secondStamp = FileStamp(size: 120, modifiedAt: Date(timeIntervalSince1970: 2_000))

private func document(lines count: Int, stamp: FileStamp?) -> OpenedDocument {
    OpenedDocument(
        header: DocumentHeader(displayPath: "log.txt", details: ""),
        store: LineStore((1...count).map { "line \($0)" }.joined(separator: "\n")),
        presentation: .plain,
        stamp: stamp
    )
}

/// 读入 100 行，视口顶端停在第 40 行，光标在第 45 行。
private func scrolledState() -> TUIState {
    var state = TUIState.launching(
        size: TerminalSize(columns: 60, rows: 12),
        target: file,
        isDirectory: false,
        displayPath: "log.txt",
        treeRoot: URL(fileURLWithPath: "/repo"),
        targetLine: nil
    )
    _ = TUIReducer.reduce(&state, .launched)
    _ = TUIReducer.reduce(&state, .loaded(document(lines: 100, stamp: firstStamp), generation: state.generation))
    state.viewport = Viewport(top: ScrollPosition(line: 40, row: 0), cursor: 45)
    return state
}

private func reloads(_ effects: [TUIEffect]) -> Bool {
    effects.contains { effect in
        if case let .load(url, _, _, isReload, _, _) = effect { return url == file && isReload }
        return false
    }
}

@Suite("Visible_reloadAnchor")
struct Visible_reloadAnchor {
    @Test("文件戳变了就重读，新内容到达后视口顶端与光标留在原来的源行；r 直接重读")
    func reloadKeepsAnchor() {
        var state = scrolledState()
        #expect(reloads(TUIReducer.reduce(&state, .fileStamp(secondStamp, generation: state.generation))))
        _ = TUIReducer.reduce(&state, .loaded(document(lines: 120, stamp: secondStamp), generation: state.generation))
        #expect(state.viewport.top.line == 40)
        #expect(state.viewport.cursor == 45)
        #expect(reloads(TUIReducer.reduce(&state, .input(.key(KeyPress(key: .character("r")))))))
    }

    @Test("文件变短：光标钳到最后一行")
    func shorterFileClampsCursor() {
        var state = scrolledState()
        _ = TUIReducer.reduce(&state, .fileStamp(secondStamp, generation: state.generation))
        _ = TUIReducer.reduce(&state, .loaded(document(lines: 30, stamp: secondStamp), generation: state.generation))
        #expect(state.viewport.cursor == 29)
    }

    @Test("大小和修改时间都没变时不重读")
    func sameStampDoesNothing() {
        var state = scrolledState()
        #expect(TUIReducer.reduce(&state, .fileStamp(firstStamp, generation: state.generation)).isEmpty)
    }

    @Test("文件被删除：正文显示读取失败；文件再出现时重读并回到原来的位置")
    func deletedThenRecreated() {
        var state = scrolledState()
        #expect(reloads(TUIReducer.reduce(&state, .fileStamp(nil, generation: state.generation))))
        _ = TUIReducer.reduce(&state, .loadFailed("读不了 log.txt", generation: state.generation))
        guard case .failed = state.document else { Issue.record("not failed"); return }
        #expect(reloads(TUIReducer.reduce(&state, .fileStamp(secondStamp, generation: state.generation))))
        _ = TUIReducer.reduce(&state, .loaded(document(lines: 100, stamp: secondStamp), generation: state.generation))
        #expect(state.viewport.top.line == 40)
        #expect(state.viewport.cursor == 45)
    }
}
