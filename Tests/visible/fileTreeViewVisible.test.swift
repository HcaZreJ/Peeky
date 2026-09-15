import Testing
import AppKit
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// 每个用例在系统临时目录下自建一棵目录树，用 `defer` 删除，用例之间不共享状态。
// FileTreeView 不进窗口也能跑：这里只驱动它的数据源与展开态，不做绘制。

@MainActor
private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("fileTreeViewVisibleTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func removeFixture(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

@discardableResult
private func makeDir(_ root: URL, _ name: String) throws -> URL {
    let url = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func makeFile(_ dir: URL, _ name: String) throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try "marker".write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// 当前显示出来的每一行的名字，按行序。
@MainActor
private func visibleNames(_ tree: FileTreeView) -> [String] {
    let outline = tree.outlineViewForTesting
    return (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? FileTreeNode)?.name }
}

@Suite("Visible_fileTreeView")
@MainActor
struct Visible_fileTreeView {

    @Test("打开之后新建的文件，刷新一次就出现在树里")
    func refreshSurfacesFilesCreatedAfterOpening() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, "R11.md")

        let tree = FileTreeView()
        tree.reload(root: root)
        #expect(visibleNames(tree) == [root.lastPathComponent, "R11.md"])

        try makeFile(root, "R12.md")
        tree.refreshAll()

        #expect(visibleNames(tree) == [root.lastPathComponent, "R11.md", "R12.md"])
    }

    @Test("刷新之后展开态原样保留，不会折回只剩根")
    func refreshKeepsExpandedSubtrees() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let traces = try makeDir(root, "traces")
        try makeFile(traces, "P4.md")

        let tree = FileTreeView()
        tree.reload(root: root)
        tree.revealAndSelect(fileURL: traces.appendingPathComponent("P4.md"))
        #expect(visibleNames(tree) == [root.lastPathComponent, "traces", "P4.md"])

        try makeFile(traces, "P5.md")
        tree.refreshAll()

        #expect(visibleNames(tree) == [root.lastPathComponent, "traces", "P4.md", "P5.md"])
    }

    @Test("已展开的目录进得了 loadedDirectoryURLs，没展开的不进")
    func loadedDirectoriesCoverOnlyWhatWasExpanded() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let opened = try makeDir(root, "opened")
        try makeDir(root, "untouched")
        try makeFile(opened, "a.md")

        let tree = FileTreeView()
        tree.reload(root: root)
        tree.revealAndSelect(fileURL: opened.appendingPathComponent("a.md"))

        let loaded = tree.loadedDirectoryURLs.map(\.lastPathComponent)
        #expect(loaded.contains(root.lastPathComponent))
        #expect(loaded.contains("opened"))
        #expect(loaded.contains("untouched") == false)
    }

    @Test("只重列指定目录时，其余目录不受影响")
    func refreshingOneDirectoryLeavesOthersAlone() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let left = try makeDir(root, "left")
        let right = try makeDir(root, "right")
        try makeFile(left, "l1.md")
        try makeFile(right, "r1.md")

        let tree = FileTreeView()
        tree.reload(root: root)
        tree.revealAndSelect(fileURL: left.appendingPathComponent("l1.md"))
        tree.revealAndSelect(fileURL: right.appendingPathComponent("r1.md"))

        try makeFile(left, "l2.md")
        try makeFile(right, "r2.md")
        tree.refresh(directories: [left])

        // left 重列过，l2 出现；right 没重列，r2 还没进来。
        #expect(visibleNames(tree) == [root.lastPathComponent, "left", "l1.md", "l2.md", "right", "r1.md"])
    }

    @Test("折叠再展开就是一次刷新：折叠期间新增的文件在重新展开时出现")
    func collapsingAndExpandingRelistsFromDisk() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let traces = try makeDir(root, "traces")
        try makeFile(traces, "a.md")

        let tree = FileTreeView()
        tree.reload(root: root)

        let outline = tree.outlineViewForTesting
        let node = try #require(outline.item(atRow: 1) as? FileTreeNode)
        outline.expandItem(node)
        #expect(visibleNames(tree) == [root.lastPathComponent, "traces", "a.md"])

        outline.collapseItem(node)
        #expect(visibleNames(tree) == [root.lastPathComponent, "traces"])

        try makeFile(traces, "b.md")
        try makeFile(traces, "c.md")
        outline.expandItem(node)

        #expect(visibleNames(tree) == [root.lastPathComponent, "traces", "a.md", "b.md", "c.md"])
    }

    @Test("目标文件是打开之后才出现的，revealAndSelect 也能定位到它")
    func revealFindsFilesCreatedAfterTheSnapshot() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let traces = try makeDir(root, "traces")
        try makeFile(traces, "old.md")

        let tree = FileTreeView()
        tree.reload(root: root)
        tree.revealAndSelect(fileURL: traces.appendingPathComponent("old.md"))

        // 树已经把 traces 的子项缓存下来了；此后磁盘上多出一个文件。
        let fresh = try makeFile(traces, "R12.md")
        tree.revealAndSelect(fileURL: fresh)

        #expect(visibleNames(tree).contains("R12.md"))
    }
}
