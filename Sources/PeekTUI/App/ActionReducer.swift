import Foundation
import PeekyCore

/// 选区、复制、文件动作、跳行输入与帮助浮层。
extension TUIReducer {
    static let noRepositoryToast = "不在代码仓库里，没有相对路径"

    /// 设一条状态栏提示，并返回 2 秒后让它过期的副作用。
    static func showToast(_ text: String, state: inout TUIState) -> TUIEffect {
        state.toast = text
        state.toastToken += 1
        return .expireToast(state.toastToken)
    }

    // MARK: - 复制与文件动作

    /// 复制与文件动作的按键；不是这些键时返回 nil。
    static func handleActionKey(_ press: KeyPress, state: inout TUIState) -> [TUIEffect]? {
        switch (press.key, press.modifiers) {
        case (.character("y"), []), (.character("c"), .super):
            return copySelectionOrLine(&state)
        case (.character("Y"), []):
            guard let file = state.activeFile else { return [] }
            return [.copyFileText(file), showToast("已复制全文", state: &state)]
        case (.character("F"), []):
            guard let file = state.activeFile else { return [] }
            return [.copy(text: file.lastPathComponent, description: "文件名"), showToast("已复制文件名", state: &state)]
        case (.character("p"), []):
            guard let file = state.activeFile else { return [] }
            return [.copy(text: file.path, description: "绝对路径"), showToast("已复制绝对路径", state: &state)]
        case (.character("P"), []):
            guard let file = state.activeFile else { return [] }
            guard let root = state.repoRoot else { return [showToast(noRepositoryToast, state: &state)] }
            return [.copy(text: relativePath(of: file, root: root), description: "相对路径"), showToast("已复制相对路径", state: &state)]
        case (.character("L"), []):
            guard let reference = lineReference(state) else { return [] }
            return [.copy(text: reference, description: "路径:行号"), showToast("已复制路径:行号", state: &state)]
        case (.character("o"), []):
            return state.activeFile.map { [.reveal($0)] } ?? []
        case (.character("e"), []):
            return state.activeFile.map { [.openInEditor($0)] } ?? []
        default:
            return nil
        }
    }

    /// 「绝对路径:行号」（与 app 的 path:line chip 一致）：行号取选区起点所在的源行，没有选区时取光标行，1 起算。
    static func lineReference(_ state: TUIState) -> String? {
        guard let file = state.activeFile, case let .loaded(document) = state.document else { return nil }
        let line = state.selection.flatMap { $0.isEmpty ? nil : $0.start.line } ?? state.viewport.cursor
        return "\(file.path):\(document.sourceLine(forLine: line) + 1)"
    }

    /// 相对版本库根的路径，不带仓库名（与 app 的「Copy Relative Path」一致）。
    static func relativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents else {
            return url.standardizedFileURL.path
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// y / ⌘C：复制选区；没有选区时复制光标所在行（JSON 折叠行复制展开后的内容）。
    private static func copySelectionOrLine(_ state: inout TUIState) -> [TUIEffect] {
        guard case let .loaded(document) = state.document else { return [] }
        let layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines)
        let cursor = state.viewport.cursor
        let selection = state.selection.flatMap { $0.isEmpty ? nil : $0 }
            ?? TextSelection(anchor: TextPoint(line: cursor, column: 0), head: TextPoint(line: cursor, column: .max))
        let text = SelectionText.text(selection, layout: layout)
        return [.copy(text: text, description: "选中内容"), showToast("已复制 \(text.count) 字符", state: &state)]
    }

    // MARK: - 跳行输入

    /// `:` 之后：数字累积，退格删一位，回车跳到该行，其余键取消。
    static func handleLineInput(_ press: KeyPress, input: String, state: inout TUIState) -> [TUIEffect] {
        switch press.key {
        case let .character(character) where character.isASCII && character.isNumber && press.modifiers.isEmpty:
            state.lineInput = input + String(character)
        case .backspace:
            state.lineInput = input.isEmpty ? nil : String(input.dropLast())
        case .enter:
            state.lineInput = nil
            guard let line = Int(input), line > 0, case let .loaded(document) = state.document else { return [] }
            withLayout(&state) { viewport, layout, height in
                viewport.jump(to: document.line(forSourceLine: line - 1), lineCount: layout.lineCount, height: height, rows: layout.rows)
            }
        default:
            state.lineInput = nil
        }
        return []
    }

    // MARK: - 鼠标选区

    /// 正文区坐标（`mouse` 已换算到正文区）对应的文档位置；点在最后一行之后时落到最后一行行尾。
    static func textPoint(at mouse: MouseEvent, layout: DocumentLayout, viewport: Viewport, height: Int) -> TextPoint? {
        guard layout.lineCount > 0 else { return nil }
        let contentRow = min(max(mouse.row - 1, 0), height - 1)
        let positions = viewport.visibleRows(lineCount: layout.lineCount, height: height, rows: layout.rows)
        guard let position = positions[contentRow] ?? positions.compactMap({ $0 }).last else { return nil }
        if positions[contentRow] == nil {
            return TextPoint(line: position.line, column: layout.lineWidth(position.line))
        }
        return layout.point(atScreenColumn: mouse.column, position: position, horizontalOffset: viewport.horizontalOffset)
    }

    /// 按下：单击记下选区起点；双击选中词，三击选中整行。拖动：移动选区终点，拖出正文上下边缘时滚动。
    /// 松开：没拖出范围的单击不留选区。
    static func updateSelection(_ mouse: MouseEvent, state: inout TUIState) {
        guard case let .loaded(document) = state.document else { return }
        var layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines)
        let height = state.contentHeight
        switch mouse.kind {
        case .press(.left):
            guard let point = textPoint(at: mouse, layout: layout, viewport: state.viewport, height: height) else { return }
            state.isSelecting = true
            switch mouse.clickCount {
            case 2:
                let word = VisualColumns.word(in: layout.selectableText(point.line), at: point.column)
                state.selection = TextSelection(anchor: TextPoint(line: point.line, column: word.lowerBound), head: TextPoint(line: point.line, column: word.upperBound))
            case 3...:
                state.selection = TextSelection(anchor: TextPoint(line: point.line, column: 0), head: TextPoint(line: point.line, column: layout.lineWidth(point.line)))
            default:
                state.selection = TextSelection(anchor: point, head: point)
            }
        case .drag(.left):
            guard state.isSelecting, var selection = state.selection else { return }
            if mouse.row < 1 || mouse.row > height {
                let delta = mouse.row < 1 ? -1 : 1
                withLayout(&state) { viewport, layout, height in
                    viewport.scroll(by: delta, lineCount: layout.lineCount, height: height, rows: layout.rows)
                }
                layout = DocumentLayout(document: document, columns: state.contentColumns, wrapsLines: state.wrapsLines)
            }
            guard let point = textPoint(at: mouse, layout: layout, viewport: state.viewport, height: height) else { return }
            selection.head = point
            state.selection = selection
        case .release(.left):
            state.isSelecting = false
            if state.selection?.isEmpty == true { state.selection = nil }
        default:
            break
        }
    }

    // MARK: - 帮助浮层

    static func handleHelpKey(_ state: inout TUIState) -> [TUIEffect] {
        state.isHelpVisible = false
        return []
    }
}
