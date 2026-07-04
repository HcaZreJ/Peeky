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
        .appendingPathComponent("repoRootHiddenTest-\(UUID().uuidString)", isDirectory: true)
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
/// such as `package.json` / `README.md`).
@discardableResult
private func makeFile(_ dir: URL, _ name: String, contents: String = "marker") throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func standardizedPath(_ url: URL) -> String {
    url.standardizedFileURL.path
}

@Suite("Hidden_repoRoot")
struct Hidden_repoRoot {
    @Test(".git directory marker at start hits immediately")
    func gitDirectoryAtStartHitsImmediately() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let repoDir = try makeDir(root, "project")
        _ = try makeDir(repoDir, ".git")

        let result = RepoRoot.discover(from: repoDir)

        #expect(result?.path == standardizedPath(repoDir))
    }

    @Test(".git as a regular file (git-worktree layout) at start hits immediately")
    func gitFileWorktreeAtStartHitsImmediately() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let repoDir = try makeDir(root, "worktree")
        try makeFile(repoDir, ".git", contents: "gitdir: /elsewhere/.git/worktrees/wt")

        let result = RepoRoot.discover(from: repoDir)

        #expect(result?.path == standardizedPath(repoDir))
    }

    @Test(".hg directory marker hits")
    func hgDirectoryMarkerHits() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let repoDir = try makeDir(root, "hgrepo")
        _ = try makeDir(repoDir, ".hg")

        let result = RepoRoot.discover(from: repoDir)

        #expect(result?.path == standardizedPath(repoDir))
    }

    @Test(".svn directory marker hits")
    func svnDirectoryMarkerHits() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let repoDir = try makeDir(root, "svnrepo")
        _ = try makeDir(repoDir, ".svn")

        let result = RepoRoot.discover(from: repoDir)

        #expect(result?.path == standardizedPath(repoDir))
    }

    @Test("a deeply nested start directory walks all the way up to the repo root")
    func deepNestedDirectoryWalksUpToRepoRoot() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        let deepDir = try makeDir(root, "src", "lib", "internal", "detail")

        let result = RepoRoot.discover(from: deepDir)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("a file directly inside the repo root resolves via its parent directory")
    func fileImmediatelyInsideRepoRootUsesParentDirectory() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        let file = try makeFile(root, "README.md", contents: "# hi")

        let result = RepoRoot.discover(from: file)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("nested repo: the inner root takes priority over the outer one")
    func nestedRepoInnerRootTakesPriorityOverOuter() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let outer = try makeDir(root, "outer")
        _ = try makeDir(outer, ".git")
        let inner = try makeDir(outer, "vendor", "inner")
        _ = try makeDir(inner, ".git")
        let deepInInner = try makeDir(inner, "src")

        let result = RepoRoot.discover(from: deepInInner)

        #expect(result?.path == standardizedPath(inner))
    }

    @Test("no markers anywhere on a deep path returns nil")
    func noMarkersAnywhereDeepPathReturnsNil() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let deepDir = try makeDir(root, "empty", "chain", "of", "dirs")

        let result = RepoRoot.discover(from: deepDir)

        #expect(result == nil)
    }

    @Test("weak markers alone (package.json, README.md, .claude) never pin a root")
    func weakMarkersAloneDoNotPinRoot() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let projectDir = try makeDir(root, "project")
        try makeFile(projectDir, "package.json", contents: "{}")
        try makeFile(projectDir, "README.md", contents: "# readme")
        _ = try makeDir(projectDir, ".claude")

        let result = RepoRoot.discover(from: projectDir)

        #expect(result == nil)
    }

    @Test("weak markers between start and a real VCS ancestor are skipped over")
    func weakMarkersAboveRealMarkerAreSkipped() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        let mid = try makeDir(root, "packages")
        try makeFile(mid, "package.json", contents: "{}")
        let leaf = try makeDir(mid, "app")
        try makeFile(leaf, "README.md", contents: "# app")

        let result = RepoRoot.discover(from: leaf)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("a start path that does not exist returns nil, even when its parent has a VCS marker")
    func startPathDoesNotExistReturnsNilEvenWithVcsAncestor() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        // Intentionally never created on disk.
        let ghost = root.appendingPathComponent("ghost-subdir", isDirectory: true)

        let result = RepoRoot.discover(from: ghost)

        #expect(result == nil)
    }

    @Test("a start URL containing .. segments resolves via the standardized absolute path")
    func relativePathWithDotDotResolvesCorrectly() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        let sibling = try makeDir(root, "sibling")
        _ = try makeDir(root, "target")

        // "sibling/../target" should standardize to "root/target", which
        // walks up to the VCS marker at `root`.
        let messyPath = sibling
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("target", isDirectory: true)

        let result = RepoRoot.discover(from: messyPath)

        #expect(result?.path == standardizedPath(root))
    }

    @Test("a trailing slash on the start directory URL does not affect the result")
    func trailingSlashOnStartDirectoryIsHandled() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let repoDir = try makeDir(root, "trailing")
        _ = try makeDir(repoDir, ".git")

        let trailingURL = URL(fileURLWithPath: repoDir.path + "/", isDirectory: true)

        let result = RepoRoot.discover(from: trailingURL)

        #expect(result?.path == standardizedPath(repoDir))
    }
}
