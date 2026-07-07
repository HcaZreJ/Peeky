import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// Each test builds its own isolated directory tree under the system temp
// directory and removes it afterward via `defer`. No state is shared across
// tests.

private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("directoryListerVisibleTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func removeFixture(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// Creates (and returns) a direct child directory of `root` named `name`.
@discardableResult
private func makeDir(_ root: URL, _ name: String) throws -> URL {
    let url = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a small file named `name` inside `dir` with the given contents.
@discardableResult
private func makeFile(_ dir: URL, _ name: String, contents: String = "marker") throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Suite("Visible_directoryLister")
struct Visible_directoryLister {
    @Test("directories sort before files, each group ordered case-insensitively by name")
    func directoriesBeforeFilesCaseInsensitiveOrder() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, "Bravo")
        _ = try makeDir(root, "alpha")
        try makeFile(root, "Charlie.txt")
        try makeFile(root, "delta.txt")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["alpha", "Bravo", "Charlie.txt", "delta.txt"])
        #expect(entries.map(\.isDirectory) == [true, true, false, false])
    }

    @Test("VCS metadata directories such as .git are filtered out; ordinary files remain")
    func vcsMetadataDirectoryIsFilteredOut() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        try makeFile(root, "README.md")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["README.md"])
    }

    @Test("an empty directory yields an empty array without throwing")
    func emptyDirectoryReturnsEmptyArray() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.isEmpty)
    }
}
