import Foundation

package enum SidebarTab: Equatable, Sendable {
    case files
    case contents
}

/// 键盘输入交给哪一块：正文或侧栏。
package enum FocusArea: Equatable, Sendable {
    case content
    case sidebar
}

/// 侧栏状态：显示与否、页签、文件树、两个列表各自的选中项与滚动位置。
package struct SidebarState: Equatable, Sendable {
    /// 终端至少这么宽时侧栏默认显示。
    package static let autoShowColumns = 80
    /// 页签那一行占掉的高度。
    static let headerRows = 1

    package var isVisible: Bool
    /// 用户最后选的页签；当前文档没有大纲时按 Files 显示，选择保留到下一个有大纲的文档。
    package var preferredTab: SidebarTab = .files
    package var tree: FileTree
    /// 文件树里选中的那一项（路径）；目录重新列举后按路径找回。
    package var selectedPath: String?
    package var treeTop = 0
    package var outlineSelection = 0
    package var outlineTop = 0

    package init(tree: FileTree, isVisible: Bool) {
        self.tree = tree
        self.isVisible = isVisible
    }

    /// 侧栏宽度（不含右侧分隔线）：终端宽的 22%，限制在 24–40 列，且不超过半屏。
    package static func width(forColumns columns: Int) -> Int {
        min(min(max(columns * 22 / 100, 24), 40), max(columns / 2, 1))
    }

    /// 让第 `index` 行落在高 `height` 的列表里时的顶端行。
    static func top(showing index: Int, currentTop: Int, height: Int) -> Int {
        guard height > 0 else { return index }
        if index < currentTop { return index }
        if index >= currentTop + height { return index - height + 1 }
        return currentTop
    }

    /// 选中项所在分支：选中目录时是它自己，选中文件时是它的直接父目录（与 app 的导轨点亮规则一致）。
    static func activeBranch(of row: TreeRow?) -> String? {
        guard let row, let entry = row.entry else { return nil }
        return entry.isDirectory ? entry.path : row.ancestors.last
    }
}
