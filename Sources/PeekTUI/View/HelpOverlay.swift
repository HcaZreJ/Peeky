import PeekyCore

/// 帮助浮层里的一行：按键与它做的事。
package struct KeymapEntry: Equatable, Sendable {
    package let keys: String
    package let action: String
}

/// 按键一览（纯数据，帮助浮层按它画）。
package enum Keymap {
    package static let entries: [KeymapEntry] = [
        KeymapEntry(keys: "j / k  ↓ / ↑", action: "上下移动一行"),
        KeymapEntry(keys: "空格 / b", action: "下 / 上翻一页"),
        KeymapEntry(keys: "Ctrl-D / Ctrl-U", action: "下 / 上翻半页"),
        KeymapEntry(keys: "g / G", action: "到开头 / 结尾"),
        KeymapEntry(keys: ":行号 回车", action: "跳到第几行"),
        KeymapEntry(keys: "/词 回车", action: "搜索（不区分英文大小写）"),
        KeymapEntry(keys: "n / N", action: "下一个 / 上一个匹配"),
        KeymapEntry(keys: "w", action: "自动换行开关"),
        KeymapEntry(keys: "h / l  ← / →", action: "不换行时左右滚动；侧栏里收起 / 展开目录"),
        KeymapEntry(keys: "回车", action: "折叠 JSON、打开链接；侧栏里打开"),
        KeymapEntry(keys: "M / R", action: "JSON 全部折叠 / 全部展开"),
        KeymapEntry(keys: "J / D", action: "复制 jq 路径 / 点分路径"),
        KeymapEntry(keys: "拖动 / 双击 / 三击", action: "选中文字 / 一个词 / 整行"),
        KeymapEntry(keys: "y  ⌘C", action: "复制选中内容（没有选中时复制当前行）"),
        KeymapEntry(keys: "Y", action: "复制全文"),
        KeymapEntry(keys: "F / p / P", action: "复制文件名 / 绝对路径 / 仓库内相对路径"),
        KeymapEntry(keys: "L", action: "复制「路径:行号」（选中的首行或当前行）"),
        KeymapEntry(keys: "o / e", action: "在 Finder 中显示 / 用默认编辑器打开"),
        KeymapEntry(keys: "r", action: "从磁盘重读"),
        KeymapEntry(keys: "[ / ]", action: "上一个 / 下一个打开的文件"),
        KeymapEntry(keys: "x", action: "关掉当前文件（侧栏 Open 里关掉选中的）"),
        KeymapEntry(keys: "Tab / s", action: "切换焦点 / 显示或收起侧栏"),
        KeymapEntry(keys: "1 / 2 / 3", action: "侧栏切到 Open / Files / Contents"),
        KeymapEntry(keys: "Esc", action: "取消选中、清除搜索高亮；侧栏里回到正文"),
        KeymapEntry(keys: "q", action: "退出"),
    ]
}

/// 纯函数：在画面中央画出按键一览；放不下的行省略并在末行写「…」。
enum HelpOverlay {
    static let title = " 按键（按任意键关闭） "

    static func draw(_ frame: inout CellBuffer, appearance: PeekyPalette.Appearance) {
        let keysWidth = Keymap.entries.map { TextWidth.width(of: $0.keys) }.max() ?? 0
        let actionWidth = Keymap.entries.map { TextWidth.width(of: $0.action) }.max() ?? 0
        let width = min(keysWidth + actionWidth + 7, frame.columns - 2)
        let availableRows = frame.rows - 2
        guard width > 10, availableRows >= 3 else { return }
        let shown = min(Keymap.entries.count, availableRows - 2)
        let height = shown + 2
        let left = (frame.columns - width) / 2
        let top = max((frame.rows - height) / 2, 0)
        let box = CellStyle(background: TerminalPalette.color(.statusBarBackground, appearance: appearance))
        let border = CellStyle(foreground: TerminalPalette.color(.treeIndentGuide, appearance: appearance), background: box.background)

        for row in top..<(top + height) {
            frame.fill(row: row, from: left, to: left + width, style: box)
        }
        frame.write("╭" + String(repeating: "─", count: width - 2) + "╮", row: top, column: left, style: border)
        frame.write(title, row: top, column: left + 2, style: CellStyle(background: box.background, bold: true), limit: left + width - 1)
        for index in 0..<shown {
            let row = top + 1 + index
            frame.write("│", row: row, column: left, style: border)
            frame.write("│", row: row, column: left + width - 1, style: border)
            let entry = Keymap.entries[index]
            let isTruncated = index == shown - 1 && shown < Keymap.entries.count
            let keys = isTruncated ? "…" : entry.keys
            let action = isTruncated ? "" : entry.action
            frame.write(keys, row: row, column: left + 2, style: CellStyle(foreground: ChromeColors.forAppearance(appearance).accent, background: box.background, bold: true), limit: left + width - 2)
            let actionColumn = left + 2 + keysWidth + 2
            frame.write(SidebarRenderer.fitted(action, width: left + width - 2 - actionColumn), row: row, column: actionColumn, style: box, limit: left + width - 2)
        }
        frame.write("╰" + String(repeating: "─", count: width - 2) + "╯", row: top + height - 1, column: left, style: border)
    }
}
