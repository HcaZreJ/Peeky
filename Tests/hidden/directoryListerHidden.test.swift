import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// Each test builds its own isolated directory tree under the system temp
// directory and removes it afterward via `defer`. No state is shared across
// tests. The permission-revocation test restores permissions in a `defer`
// declared after the fixture-removal `defer`, so (per LIFO defer ordering)
// permissions are restored before the fixture root is deleted.

private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("directoryListerHiddenTest-\(UUID().uuidString)", isDirectory: true)
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

/// Writes a small file named `name` inside `dir` with the given contents
/// (UTF-8 encoded; callers that need an exact byte count use ASCII-only
/// content so `contents.utf8.count` matches the visible string length).
@discardableResult
private func makeFile(_ dir: URL, _ name: String, contents: String = "marker") throws -> URL {
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// Creates a symbolic link named `name` inside `dir` pointing at `target`.
@discardableResult
private func makeSymlink(_ dir: URL, _ name: String, target: URL) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    return url
}

@Suite("Hidden_directoryLister")
struct Hidden_directoryLister {

    // MARK: Sorting

    @Test("directories sort before files; within each group, names are ordered case-insensitively")
    func dirsBeforeFilesEachGroupSortedCaseInsensitively() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, "Bravo")
        _ = try makeDir(root, "alpha")
        try makeFile(root, "Charlie.txt")
        try makeFile(root, "delta.txt")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["alpha", "Bravo", "Charlie.txt", "delta.txt"])
    }

    @Test("case-insensitive ordering ignores letter case rather than raw byte value")
    func caseInsensitiveOrderingIgnoresLetterCase() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        // Under plain byte/ASCII ordering, uppercase 'Z' (0x5A) sorts before
        // lowercase 'a' (0x61); a correct case-insensitive comparison must
        // still put "apple" first.
        _ = try makeDir(root, "Zebra")
        _ = try makeDir(root, "apple")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["apple", "Zebra"])
    }

    @Test("only direct children are listed; nested content of subdirectories is not flattened in")
    func nonRecursiveListsOnlyDirectChildren() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let sub = try makeDir(root, "sub")
        try makeFile(sub, "deep.txt")
        try makeFile(root, "shallow.txt")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["sub", "shallow.txt"])
    }

    // MARK: Filtering

    @Test(
        "VCS/metadata directory names (.git, .hg, .svn, .DS_Store) never appear in results",
        arguments: [".git", ".hg", ".svn", ".DS_Store"]
    )
    func filteredNameAsDirectoryIsExcluded(name: String) throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, name)
        try makeFile(root, "keep.txt")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["keep.txt"])
    }

    @Test(
        "VCS/metadata names are filtered even when they exist as a regular file (e.g. git-worktree .git file)",
        arguments: [".git", ".hg", ".svn", ".DS_Store"]
    )
    func filteredNameAsFileIsExcluded(name: String) throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, name, contents: "marker")
        try makeFile(root, "keep.txt")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["keep.txt"])
    }

    @Test("other dotfiles (.env) and node_modules are ordinary entries, never filtered")
    func otherDotfilesAndNodeModulesArePreserved() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".claude")
        _ = try makeDir(root, "node_modules")
        try makeFile(root, ".env", contents: "SECRET=1")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == [".claude", "node_modules", ".env"])
    }

    // MARK: Fields — size, isDirectory, mtime, url

    @Test("regular file size reflects the exact byte count; directory size is always zero")
    func fileAndDirectorySizesAreExact() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, "five.txt", contents: "12345")
        _ = try makeDir(root, "adir")

        let entries = try DirectoryLister.list(dir: root)
        let file = try #require(entries.first { $0.name == "five.txt" })
        let dir = try #require(entries.first { $0.name == "adir" })

        #expect(file.size == 5)
        #expect(file.isDirectory == false)
        #expect(dir.size == 0)
        #expect(dir.isDirectory == true)
    }

    @Test("a symlink pointing at a directory resolves isDirectory to true and size to zero")
    func symlinkToDirectoryResolvesAsDirectory() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let targetDir = try makeDir(root, "realdir")
        _ = try makeSymlink(root, "linkToDir", target: targetDir)

        let entries = try DirectoryLister.list(dir: root)
        let link = try #require(entries.first { $0.name == "linkToDir" })

        #expect(link.isDirectory == true)
        #expect(link.size == 0)
    }

    @Test("a symlink pointing at a file resolves isDirectory to false and size to the target's byte count")
    func symlinkToFileResolvesAsFileWithTargetSize() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let targetFile = try makeFile(root, "target.txt", contents: "hello")
        _ = try makeSymlink(root, "linkToFile", target: targetFile)

        let entries = try DirectoryLister.list(dir: root)
        let link = try #require(entries.first { $0.name == "linkToFile" })

        #expect(link.isDirectory == false)
        #expect(link.size == 5)
    }

    @Test("mtime is close to the fixture's creation time (within 60s, to tolerate filesystem timestamp granularity)")
    func mtimeIsCloseToCreationTime() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let before = Date()
        try makeFile(root, "fresh.txt", contents: "hi")

        let entries = try DirectoryLister.list(dir: root)
        let entry = try #require(entries.first { $0.name == "fresh.txt" })

        #expect(abs(entry.mtime.timeIntervalSince(before)) <= 60)
    }

    @Test("the url field identifies the entry itself, nested directly under the listed directory")
    func urlPointsAtEntryItself() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        try makeFile(root, "note.md", contents: "# hi")

        let entries = try DirectoryLister.list(dir: root)
        let entry = try #require(entries.first { $0.name == "note.md" })

        #expect(entry.url.lastPathComponent == "note.md")
        #expect(
            entry.url.standardizedFileURL.deletingLastPathComponent().path
                == root.standardizedFileURL.path
        )
    }

    @Test("an empty directory yields an empty array without throwing")
    func emptyDirectoryReturnsEmptyArray() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.isEmpty)
    }

    // MARK: Error cases

    @Test("listing a path that does not exist on disk throws")
    func nonexistentDirectoryThrows() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        #expect(throws: (any Error).self) {
            try DirectoryLister.list(dir: missing)
        }
    }

    @Test("listing a path that is a regular file, not a directory, throws")
    func fileInsteadOfDirectoryThrows() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let file = try makeFile(root, "plain.txt")

        #expect(throws: (any Error).self) {
            try DirectoryLister.list(dir: file)
        }
    }

    @Test("listing a directory whose permissions have been revoked (chmod 000) throws")
    func unreadableDirectoryThrows() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        let locked = try makeDir(root, "locked")
        try makeFile(locked, "secret.txt")

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }

        #expect(throws: (any Error).self) {
            try DirectoryLister.list(dir: locked)
        }
    }

    // MARK: End-to-end

    @Test("end-to-end: filtering, directory-first case-insensitive sorting, and field population all combine correctly")
    func endToEndListingCombinesFilteringSortingAndFields() throws {
        let root = try makeFixtureRoot()
        defer { removeFixture(root) }
        _ = try makeDir(root, ".git")
        try makeFile(root, ".DS_Store")
        _ = try makeDir(root, "Bravo")
        _ = try makeDir(root, "alpha")
        try makeFile(root, "Charlie.txt", contents: "abc")
        try makeFile(root, "delta.txt", contents: "de")

        let entries = try DirectoryLister.list(dir: root)

        #expect(entries.map(\.name) == ["alpha", "Bravo", "Charlie.txt", "delta.txt"])
        #expect(entries.map(\.isDirectory) == [true, true, false, false])
        #expect(entries.first { $0.name == "Charlie.txt" }?.size == 3)
        #expect(entries.first { $0.name == "delta.txt" }?.size == 2)
        #expect(entries.first { $0.name == "alpha" }?.size == 0)
    }
}
