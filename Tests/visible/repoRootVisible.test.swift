import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// Each test builds its own isolated directory tree under the system temp
// directory and removes it afterward via `defer`. No state is shared across
// tests.

/// Creates a fresh, uniquely-named directory under the system temp directory
/// to act as the root of a single test's fixture tree.
private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("repoRootVisibleTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func removeFixture(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// Creates (and returns) the directory at `root` + `components`, creating any
/// missing intermediate directories along the way.
private func makeDir(_ root: URL, _ components: String...) throws -> URL {
    let url = components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a small marker file named `name` inside `dir` (used both for
/// VCS "file" markers, e.g. git-worktree `.git` files, and for weak markers
/// such as `package.json`).
@discardableResult
private func makeFile(_ dir: URL, _ name: String, contents: String = "marker") throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func standardizedPath(_ url: URL) -> String {
    url.standardizedFileURL.path
}

@Suite("Visible_repoRoot")
struct Visible_repoRoot {
    @Test("start directory that itself contains .git is returned as-is")
    func startIsRepoRootWithGitDir() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")

        let result = RepoRoot.discover(from: root)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("a file nested several levels inside a repo finds the ancestor root")
    func nestedFileFindsAncestorRoot() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        let deepDir = try makeDir(root, "a", "b", "c")
        let file = try makeFile(deepDir, "notes.txt")

        let result = RepoRoot.discover(from: file)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("no VCS marker anywhere on the path returns nil")
    func noVcsMarkerReturnsNil() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let deepDir = try makeDir(root, "pkg")
        try makeFile(deepDir, "package.json", contents: "{}")

        let result = RepoRoot.discover(from: deepDir)

        #expect(result == nil)
    }
}
