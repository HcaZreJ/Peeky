import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers

private func entry(_ dir: URL, _ name: String, isDirectory: Bool = false) -> DirEntry {
    DirEntry(
        name: name,
        url: dir.appendingPathComponent(name, isDirectory: isDirectory),
        isDirectory: isDirectory,
        size: isDirectory ? 0 : 7,
        mtime: Date(timeIntervalSince1970: 0)
    )
}

private func node(_ dir: URL, _ name: String, isDirectory: Bool = false) -> FileTreeNode {
    FileTreeNode(
        url: dir.appendingPathComponent(name, isDirectory: isDirectory),
        name: name,
        isDirectory: isDirectory
    )
}

private let fixtureDir = URL(fileURLWithPath: "/tmp/fileTreeNodeHidden", isDirectory: true)

@Suite("Hidden_fileTreeNode")
struct Hidden_fileTreeNode {

    @Test("existing 为空时按 entries 全部新建")
    func emptyExistingBuildsEverything() {
        let result = FileTreeNode.reconcile(
            existing: [],
            entries: [entry(fixtureDir, "src", isDirectory: true), entry(fixtureDir, "a.md")]
        )
        #expect(result.map(\.name) == ["src", "a.md"])
        #expect(result.map(\.isDirectory) == [true, false])
    }

    @Test("entries 为空时结果为空")
    func emptyEntriesClearsChildren() {
        let result = FileTreeNode.reconcile(existing: [node(fixtureDir, "a.md")], entries: [])
        #expect(result.isEmpty)
    }

    @Test("复用的目录节点保留已加载的孙子缓存")
    func reusedDirectoryKeepsItsLoadedSubtree() {
        let src = node(fixtureDir, "src", isDirectory: true)
        src.childrenLoaded = true
        src.children = [node(fixtureDir, "deep.md")]

        let result = FileTreeNode.reconcile(existing: [src], entries: [entry(fixtureDir, "src", isDirectory: true)])

        #expect(result.first === src)
        #expect(result.first?.childrenLoaded == true)
        #expect(result.first?.children.map(\.name) == ["deep.md"])
    }

    @Test("结果次序完全跟随 entries，与 existing 的次序无关")
    func orderFollowsEntries() {
        let existing = [node(fixtureDir, "z.md"), node(fixtureDir, "a.md")]
        let result = FileTreeNode.reconcile(
            existing: existing,
            entries: [entry(fixtureDir, "a.md"), entry(fixtureDir, "m.md"), entry(fixtureDir, "z.md")]
        )
        #expect(result.map(\.name) == ["a.md", "m.md", "z.md"])
    }

    @Test("同名条目从文件变成目录时换成新节点")
    func nameReusedAsDirectoryGetsAFreshNode() {
        let asFile = node(fixtureDir, "notes")
        let result = FileTreeNode.reconcile(
            existing: [asFile],
            entries: [entry(fixtureDir, "notes", isDirectory: true)]
        )
        #expect(result.count == 1)
        #expect(result.first !== asFile)
        #expect(result.first?.isDirectory == true)
    }

    @Test("同一份 entries 连续对账两次，实例保持不变")
    func repeatedReconcileIsIdempotent() {
        let entries = [entry(fixtureDir, "src", isDirectory: true), entry(fixtureDir, "a.md")]
        let first = FileTreeNode.reconcile(existing: [], entries: entries)
        let second = FileTreeNode.reconcile(existing: first, entries: entries)
        #expect(zip(first, second).allSatisfy { $0 === $1 })
    }

    @Test("同一次对账里既丢弃消失的条目又新建出现的条目")
    func oneRoundHandlesBothAddAndRemove() {
        let kept = node(fixtureDir, "keep.md")
        let result = FileTreeNode.reconcile(
            existing: [kept, node(fixtureDir, "gone.md")],
            entries: [entry(fixtureDir, "fresh.md"), entry(fixtureDir, "keep.md")]
        )
        #expect(result.map(\.name) == ["fresh.md", "keep.md"])
        #expect(result.last === kept)
    }

    @Test("existing 里的占位错误节点从不被复用")
    func placeholderNodesAreNeverReused() {
        let placeholder = FileTreeNode(
            url: fixtureDir.appendingPathComponent("ghost.md", isDirectory: false),
            name: "ghost.md",
            isDirectory: false,
            isErrorPlaceholder: true
        )
        let result = FileTreeNode.reconcile(existing: [placeholder], entries: [entry(fixtureDir, "ghost.md")])
        #expect(result.count == 1)
        #expect(result.first !== placeholder)
        #expect(result.first?.isErrorPlaceholder == false)
    }
}
