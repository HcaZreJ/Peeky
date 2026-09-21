import Testing
import Foundation
@testable import PeekyKit

private func makeNode(_ name: String, isDirectory: Bool = true) -> FileTreeNode {
    FileTreeNode(
        url: URL(fileURLWithPath: "/fixture/\(name)", isDirectory: isDirectory),
        name: name,
        isDirectory: isDirectory
    )
}

@Suite("Visible_fileTreeIndentGuide")
struct Visible_fileTreeIndentGuide {
    /// 三角中心 = 内容起点 − 三角偏移 = 18 − 10 = 8，此后每深一层加一个缩进单位。
    @Test("导轨列的 x 从三角中心起算，逐层加一个缩进单位")
    func columnXStepsByIndent() {
        #expect(FileTreeIndentGuide.columnX(depth: 0, indent: 14) == 8)
        #expect(FileTreeIndentGuide.columnX(depth: 1, indent: 14) == 22)
        #expect(FileTreeIndentGuide.columnX(depth: 3, indent: 14) == 50)
    }

    @Test("根级行没有祖先，不画导轨")
    func rootRowDrawsNothing() {
        let columns = FileTreeIndentGuide.columns(ancestors: [], activeAncestor: nil, indent: 14)
        #expect(columns.isEmpty)
    }

    @Test("每一位祖先各得一列，次序由浅到深")
    func oneColumnPerAncestor() {
        let ancestors = [makeNode("a"), makeNode("b"), makeNode("c")]
        let columns = FileTreeIndentGuide.columns(ancestors: ancestors, activeAncestor: nil, indent: 14)
        #expect(columns.map(\.x) == [8, 22, 36])
    }

    @Test("活动祖先所在的那一列点亮，其余保持非活动")
    func onlyActiveAncestorColumnLights() throws {
        let ancestors = [makeNode("a"), makeNode("b"), makeNode("c")]
        let columns = FileTreeIndentGuide.columns(
            ancestors: ancestors,
            activeAncestor: ancestors[1],
            indent: 14
        )
        #expect(columns.map(\.isActive) == [false, true, false])
    }

    /// 同深度的旁支不能被点亮——归属是节点身份问题，不是深度问题。
    @Test("活动祖先不在本行祖先链上时整行都是非活动色")
    func siblingBranchStaysInactive() {
        let ancestors = [makeNode("a"), makeNode("b")]
        let columns = FileTreeIndentGuide.columns(
            ancestors: ancestors,
            activeAncestor: makeNode("elsewhere"),
            indent: 14
        )
        #expect(columns.allSatisfy { !$0.isActive })
    }

    @Test("没有活动祖先时整行都是非活动色")
    func noActiveAncestorLeavesAllInactive() {
        let ancestors = [makeNode("a"), makeNode("b")]
        let columns = FileTreeIndentGuide.columns(ancestors: ancestors, activeAncestor: nil, indent: 14)
        #expect(columns.allSatisfy { !$0.isActive })
    }

    @Test("选中文件时点亮它的直接父级")
    func selectedFileLightsItsParent() {
        let parent = makeNode("parent")
        let file = makeNode("note.md", isDirectory: false)
        #expect(FileTreeIndentGuide.activeAncestor(selected: file, parent: parent) === parent)
    }

    @Test("选中目录时点亮它自己那一列，未选中时无活动祖先")
    func selectedDirectoryLightsItself() {
        let parent = makeNode("parent")
        let directory = makeNode("skills")
        #expect(FileTreeIndentGuide.activeAncestor(selected: directory, parent: parent) === directory)
        #expect(FileTreeIndentGuide.activeAncestor(selected: nil, parent: parent) == nil)
    }
}
