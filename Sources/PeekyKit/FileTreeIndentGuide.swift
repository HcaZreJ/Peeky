import Foundation

/// 侧栏文件树的缩进导轨：每一行为它的每一位祖先画一条竖线，
/// 当前分支所在的那一列用活动色，其余用非活动色。
///
/// 线画在那位祖先**自己的折叠三角那一列**——线正是从点开它的那个三角底下长出来的，
/// 因此永远与本行自己的三角错开整整一个缩进单位。
enum FileTreeIndentGuide {
    struct Column: Equatable {
        let x: CGFloat
        let isActive: Bool
    }

    /// AppKit 在 `style = .plain` 下给 level 0 留的折叠三角槽宽度，实测恒定。
    static let contentOrigin: CGFloat = 18
    /// 三角中心相对内容起点的左偏移，实测恒定。
    static let triangleInset: CGFloat = 10

    /// 深度 depth 那位祖先的导轨列的 x。
    static func columnX(depth: Int, indent: CGFloat) -> CGFloat {
        contentOrigin + indent * CGFloat(depth) - triangleInset
    }

    /// 本行要画的导轨列，按深度从浅到深。
    /// `activeAncestor` 是当前应点亮的那位祖先，不在 `ancestors` 里时本行整行都是非活动色。
    static func columns(
        ancestors: [FileTreeNode],
        activeAncestor: FileTreeNode?,
        indent: CGFloat
    ) -> [Column] {
        ancestors.enumerated().map { depth, ancestor in
            Column(
                x: columnX(depth: depth, indent: indent),
                isActive: ancestor === activeAncestor
            )
        }
    }

    /// 由选中行推出该点亮哪位祖先：选中目录时点亮它自己那一列，选中文件时点亮它的直接父级。
    static func activeAncestor(selected: FileTreeNode?, parent: FileTreeNode?) -> FileTreeNode? {
        guard let selected else { return nil }
        return selected.isDirectory ? selected : parent
    }
}
