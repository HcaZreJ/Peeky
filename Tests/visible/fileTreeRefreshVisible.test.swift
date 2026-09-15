import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// scope 是纯路径运算，不碰磁盘；用例直接构造 URL 与路径串，用例之间不共享状态。

private let repo = URL(fileURLWithPath: "/Users/dev/repo", isDirectory: true)
private let srcDir = repo.appendingPathComponent("src", isDirectory: true)
private let docsDir = repo.appendingPathComponent("docs", isDirectory: true)
private let activeFile = srcDir.appendingPathComponent("main.swift", isDirectory: false)

@Suite("Visible_fileTreeRefresh")
struct Visible_fileTreeRefresh {

    @Test("变化路径命中一个已展开目录时，只重列这一个目录")
    func changedLoadedDirectoryIsReloaded() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [docsDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir, docsDir],
            activeFileURL: activeFile
        )

        #expect(scope.directoriesToReload == [docsDir])
        #expect(scope.touchesActiveFile == false)
    }

    @Test("变化落在没展开过的目录里时，这一轮什么都不做")
    func changeInsideUnexpandedDirectoryIsIgnored() {
        let scope = FileTreeRefresh.scope(
            changedPaths: ["/Users/dev/repo/vendor/pkg"],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir],
            activeFileURL: activeFile
        )

        #expect(scope.isEmpty)
    }

    @Test("变化路径是最前 tab 文件所在的目录时，标记该文件可能已变")
    func changeInActiveFileDirectoryTouchesActiveFile() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [srcDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [repo],
            activeFileURL: activeFile
        )

        #expect(scope.touchesActiveFile)
        #expect(scope.directoriesToReload.isEmpty)
    }

    @Test("事件被内核合并到丢失明细时，全部已展开目录与最前文件一律纳入")
    func mustScanSubDirectoriesWidensToEverythingLoaded() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [],
            mustScanSubDirectories: true,
            loadedDirectories: [repo, srcDir, docsDir],
            activeFileURL: activeFile
        )

        #expect(scope.directoriesToReload == [repo, srcDir, docsDir])
        #expect(scope.touchesActiveFile)
    }

    @Test("一次事件同时命中已展开目录和最前文件所在目录时，两者都纳入")
    func directoryAndActiveFileCanBothBeInScope() {
        let scope = FileTreeRefresh.scope(
            changedPaths: [docsDir.path, srcDir.path],
            mustScanSubDirectories: false,
            loadedDirectories: [repo, srcDir, docsDir],
            activeFileURL: activeFile
        )

        #expect(scope.directoriesToReload == [srcDir, docsDir])
        #expect(scope.touchesActiveFile)
    }
}
