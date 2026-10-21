import AppKit

/// File ▸ Open Recent 子菜单的条目构建。条目文字与空白窗口里的行出自同一份 `RecentFiles.Item`，两处一字不差。
enum RecentFilesMenu {
    /// 条目文字：文件名用菜单字号在前，位置与原因小两号跟在后面。
    ///
    /// 文件名与位置不设前景色——启用 / 禁用 / 高亮三种着色交给系统，层级只靠字号承载，
    /// 三种状态下都成立。唯一的例外是不可打开条目的原因：它点不动、永远不会被高亮，
    /// 显式给 secondaryLabelColor，让它比系统置灰的文件名亮一档，原因读得出来。
    static func attributedTitle(for item: RecentFiles.Item) -> NSAttributedString {
        let nameFont = NSFont.menuFont(ofSize: 0)
        let detailFont = NSFont.menuFont(ofSize: nameFont.pointSize - 2)
        let title = NSMutableAttributedString(string: item.name, attributes: [.font: nameFont])
        title.append(NSAttributedString(string: "   " + item.location, attributes: [.font: detailFont]))
        if let reason = item.reason {
            title.append(NSAttributedString(string: "  ·  ", attributes: [.font: detailFont]))
            title.append(NSAttributedString(string: reason, attributes: [
                .font: detailFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        return title
    }

    /// 重建子菜单。条目可打开时挂 `openAction`（representedObject 是路径），
    /// 不可打开时 action 为 nil——autoenablesItems 下系统自动把它置灰、点不动。
    /// 没有记录时只剩一条置灰的 Clear Menu，与 macOS 原生空态一致。
    @MainActor
    static func populate(
        _ menu: NSMenu,
        with items: [RecentFiles.Item],
        target: AnyObject,
        openAction: Selector,
        clearAction: Selector
    ) {
        menu.removeAllItems()
        for item in items {
            let menuItem = NSMenuItem(title: item.name, action: item.isOpenable ? openAction : nil, keyEquivalent: "")
            menuItem.attributedTitle = attributedTitle(for: item)
            menuItem.toolTip = item.tooltip
            menuItem.representedObject = item.path
            menuItem.target = item.isOpenable ? target : nil
            menu.addItem(menuItem)
        }
        if !items.isEmpty {
            menu.addItem(.separator())
        }
        let clear = NSMenuItem(title: "Clear Menu", action: items.isEmpty ? nil : clearAction, keyEquivalent: "")
        clear.target = items.isEmpty ? nil : target
        menu.addItem(clear)
    }
}
