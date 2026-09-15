import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers

private let repo = URL(fileURLWithPath: "/Users/dev/repo", isDirectory: true)
private let srcDir = repo.appendingPathComponent("src", isDirectory: true)
private let docsDir = repo.appendingPathComponent("docs", isDirectory: true)
private let deepDir = srcDir.appendingPathComponent("deep", isDirectory: true)
private let activeFile = srcDir.appendingPathComponent("main.swift", isDirectory: false)

@Suite("Hidden_fileTreeRefresh")
struct Hidden_fileTreeRefresh {

    @Test("/var 与 /private/var 归一化后视为同一个目录")
    func symlinkedSystemPathsMatch() {
        let watched = URL(fileURLWithPath: "/var/folders/peeky-fixture", isDirectory: true)
        let scope = FileTreeRefresh.scope(
            changedPaths: ["/private/var/folders/peeky-fixture"],
            mustScanSubDirectories: false,
            loadedDirectories: [watched],
            activeFileURL: nil
        )

        #expect(scope.directoriesToReload == [watched])
    }

    @Test("FSEvents 路径带尾斜杠时同样命中")
    func trailingSlashIsNormalized() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [docsDir.path + "/"],
            mustScanSubDirectories: false,
            loadedDirectories: [docsDir],
            activeFileURL: nil
        )

        #expect(scope.directoriesToReload == [docsDir])
    }

    @Test("没有最前文件时不会标记文件变化")
    func noActiveFileNeverTouchesActiveFile() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [srcDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [],
            activeFileURL: nil
        )

        #expect(scope.touchesActiveFile == false)
        #expect(scope.isEmpty)
    }

    @Test("同一个目录在事件里出现多次也只重列一次")
    func duplicateChangedPathsCollapse() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [docsDir.path, docsDir.path + "/", docsDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [docsDir],
            activeFileURL: nil
        )

        #expect(scope.directoriesToReload == [docsDir])
    }

    @Test("重列次序跟随 loadedDirectories 的传入次序，与事件到达次序无关")
    func reloadOrderFollowsLoadedDirectories() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [docsDir.path, repo.path, srcDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir, docsDir],
            activeFileURL: nil
        )

        #expect(scope.directoriesToReload == [repo, srcDir, docsDir])
    }

    @Test("没有变化路径且未丢失明细时，范围为空")
    func noChangedPathsYieldsEmptyScope() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir],
            activeFileURL: activeFile
        )

        #expect(scope.isEmpty)
    }

    @Test("丢失明细但既没展开任何目录也没有最前文件时，范围仍为空")
    func mustScanWithNothingLoadedStaysEmpty() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [],
            mustScanSubDirectories: true,
            loadedDirectories: [],
            activeFileURL: nil
        )

        #expect(scope.isEmpty)
    }

    @Test("变化发生在已展开目录的未展开子目录里时，不重列父目录")
    func changeInsideUnexpandedChildDoesNotReloadParent() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [deepDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir],
            activeFileURL: nil
        )

        #expect(scope.isEmpty)
    }
}
