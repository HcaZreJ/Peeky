import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// 每个用例在系统临时目录下自建一棵独立的目录树，用 `defer` 删除，用例之间不共享状态。

private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("fileTreeNodeVisibleTest-\(UUID().uuidString)", isDirectory: true)
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
private func makeFile(_ dir: URL, _ name: String, contents: String = "marker") throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// 走真实 DirectoryLister 的一轮对账，保证节点 URL 与列目录产出的 URL 形态一致。
private func reconcileFromDisk(_ existing: [FileTreeNode], dir: URL) throws -> [FileTreeNode] {
    FileTreeNode.reconcile(existing: existing, entries: try DirectoryLister.list(dir: dir))
}

@Suite("Visible_fileTreeNode")
struct Visible_fileTreeNode {

    @Test("第一轮列目录之后新建的文件，第二轮对账即出现在子项里")
    func newFileAppearsOnSecondPass() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, "R11.md")

        let first = try reconcileFromDisk([], dir: root)
        #expect(first.map(\.name) == ["R11.md"])

        try makeFile(root, "R12.md")
        let second = try reconcileFromDisk(first, dir: root)
        #expect(second.map(\.name) == ["R11.md", "R12.md"])
    }

    @Test("磁盘上没变的条目复用原节点实例")
    func unchangedEntriesKeepTheirNodeInstances() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeDir(root, "traces")
        try makeFile(root, "README.md")

        let first = try reconcileFromDisk([], dir: root)
        let tracesNode = try #require(first.first(where: { $0.name == "traces" }))
        let readmeNode = try #require(first.first(where: { $0.name == "README.md" }))

        try makeFile(root, "INDEX.md")
        let second = try reconcileFromDisk(first, dir: root)

        #expect(second.first(where: { $0.name == "traces" }) === tracesNode)
        #expect(second.first(where: { $0.name == "README.md" }) === readmeNode)
    }

    @Test("磁盘上已删除的条目不再出现在子项里")
    func deletedEntriesDisappear() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let doomed = try makeFile(root, "draft.md")
        try makeFile(root, "keep.md")

        let first = try reconcileFromDisk([], dir: root)
        #expect(first.map(\.name) == ["draft.md", "keep.md"])

        try FileManager.default.removeItem(at: doomed)
        let second = try reconcileFromDisk(first, dir: root)
        #expect(second.map(\.name) == ["keep.md"])
    }

    @Test("不可读目录留下的占位子项被真实条目取代")
    func errorPlaceholderIsReplacedByRealEntries() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, "a.md")

        let placeholder = FileTreeNode(
            url: root.appendingPathComponent(".peeky-unreadable"),
            name: "(无法读取)",
            isDirectory: false,
            isErrorPlaceholder: true
        )
        let refreshed = try reconcileFromDisk([placeholder], dir: root)

        #expect(refreshed.map(\.name) == ["a.md"])
        #expect(refreshed.allSatisfy { !$0.isErrorPlaceholder })
    }
}
