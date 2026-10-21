import Testing
import Foundation
@testable import PeekyKit

// MARK: - Fixture helpers
//
// RecentFiles 是纯运算：磁盘是否存在由调用方以 pathExists 闭包注入，`.git` 文件内容以字符串传入。

private let home = "/Users/me"
private let peekyRoot = "/Users/me/Documents/peeky"
private let coevalRoot = "/Users/me/Documents/coeval"
private let worktreeRoot = "/Users/me/Documents/peeky/.claude/worktrees/fix-scroll"
private let peeky = RecentFiles.Origin.repository(name: "peeky", rootPath: peekyRoot)
private let coeval = RecentFiles.Origin.repository(name: "coeval", rootPath: coevalRoot)
private let fixScroll = RecentFiles.Origin.worktree(repositoryName: "peeky", worktreeName: "fix-scroll", rootPath: worktreeRoot)

private func entry(_ path: String, at seconds: TimeInterval = 1, origin: RecentFiles.Origin = .folder) -> RecentFiles.Entry {
    RecentFiles.Entry(path: path, openedAt: Date(timeIntervalSince1970: seconds), origin: origin)
}

@Suite("Visible_recentFiles")
struct Visible_recentFiles {

    @Test("再次打开已在列表里的文件时，它移到最前、带上新时间，列表里不出现第二条")
    func reopeningMovesEntryToFront() {
        let readme = entry("\(peekyRoot)/README.md", at: 1, origin: peeky)
        let agents = entry("\(peekyRoot)/AGENTS.md", at: 2, origin: peeky)

        let updated = RecentFiles.recording(entry("\(peekyRoot)/README.md", at: 3, origin: peeky), into: [agents, readme])

        #expect(updated == [entry("\(peekyRoot)/README.md", at: 3, origin: peeky), agents])
    }

    @Test("列表满 20 条时记一个新文件，挤掉最早打开的那条")
    func recordingBeyondCapacityDropsOldest() {
        let full = (0..<RecentFiles.capacity).map { entry("/tmp/file\($0).txt", at: TimeInterval(100 - $0)) }

        let updated = RecentFiles.recording(entry("/tmp/new.txt", at: 200), into: full)

        #expect(updated.count == RecentFiles.capacity)
        #expect(updated.first?.path == "/tmp/new.txt")
        #expect(updated.last?.path == "/tmp/file18.txt")
    }

    @Test("可用性：文件在就能开；文件和它的 worktree 都不在是 worktree 已删；其余找不到是文件已不在")
    func availabilityDistinguishesWorktreeRemovalFromMissingFile() {
        let inWorktree = entry("\(worktreeRoot)/Sources/PeekyKit/AppDelegate.swift", origin: fixScroll)
        let plain = entry("\(home)/Downloads/events.jsonl")

        let everything: Set<String> = [inWorktree.path, worktreeRoot, plain.path]
        #expect(RecentFiles.availability(of: inWorktree, pathExists: everything.contains) == .available)
        #expect(RecentFiles.availability(of: plain, pathExists: everything.contains) == .available)

        let nothing: Set<String> = []
        #expect(RecentFiles.availability(of: inWorktree, pathExists: nothing.contains) == .worktreeRemoved)
        #expect(RecentFiles.availability(of: plain, pathExists: nothing.contains) == .missing)

        let worktreeStillThere: Set<String> = [worktreeRoot]
        #expect(RecentFiles.availability(of: inWorktree, pathExists: worktreeStillThere.contains) == .missing)
    }

    @Test("来源：.git 文件指向主仓库的 worktrees/ 时是 worktree；.git 是目录时是主检出；找不到仓库根时不在仓库里")
    func originFromAbsoluteGitdirAndPlainRepository() {
        let worktree = RecentFiles.origin(
            rootPath: worktreeRoot,
            gitFileContents: "gitdir: /Users/me/Documents/peeky/.git/worktrees/fix-scroll\n"
        )
        #expect(worktree == fixScroll)

        #expect(RecentFiles.origin(rootPath: peekyRoot, gitFileContents: nil) == peeky)
        #expect(RecentFiles.origin(rootPath: nil, gitFileContents: nil) == .folder)
    }

    @Test("gitdir 是相对路径或指向裸仓库时，同样认出主仓库名")
    func relativeAndBareGitdirIdentifyRepository() {
        let relative = RecentFiles.origin(
            rootPath: worktreeRoot,
            gitFileContents: "gitdir: ../../../.git/worktrees/fix-scroll"
        )
        #expect(relative == fixScroll)

        let bare = RecentFiles.origin(
            rootPath: "/Users/me/wt/feature",
            gitFileContents: "gitdir: /Users/me/repos/peeky.git/worktrees/feature\n"
        )
        #expect(bare == .worktree(repositoryName: "peeky", worktreeName: "feature", rootPath: "/Users/me/wt/feature"))
    }

    @Test("子模块的 .git 文件与无关内容都不算 worktree，按主检出处理")
    func submoduleAndUnrelatedContentsAreRepositories() {
        let submoduleRoot = "\(peekyRoot)/vendor/lib"
        let submodule = RecentFiles.origin(rootPath: submoduleRoot, gitFileContents: "gitdir: ../../.git/modules/vendor/lib\n")
        #expect(submodule == .repository(name: "lib", rootPath: submoduleRoot))

        #expect(RecentFiles.origin(rootPath: peekyRoot, gitFileContents: "ref: refs/heads/main\n") == peeky)
    }

    @Test("位置：主检出写仓库名，worktree 写「仓库 › worktree 名」，仓库外写 ~ 缩写的父目录；同仓库里同名才补目录")
    func locationNamesRepositoryWorktreeOrFolder() {
        let main = entry("\(peekyRoot)/Sources/PeekyKit/PreviewWindowController.swift", origin: peeky)
        let inWorktree = entry("\(worktreeRoot)/Sources/PeekyKit/PreviewWindowController.swift", origin: fixScroll)
        let loose = entry("\(home)/Downloads/events.jsonl")
        let web = entry("\(coevalRoot)/apps/web/package.json", origin: coeval)
        let api = entry("\(coevalRoot)/apps/api/package.json", origin: coeval)
        let peekyAgents = entry("\(peekyRoot)/AGENTS.md", origin: peeky)
        let coevalAgents = entry("\(coevalRoot)/AGENTS.md", origin: coeval)
        let list = [main, inWorktree, loose, web, api, peekyAgents, coevalAgents]

        func location(_ entry: RecentFiles.Entry) -> String {
            RecentFiles.location(for: entry, in: list, homePath: home)
        }
        #expect(location(main) == "peeky")
        #expect(location(inWorktree) == "peeky › worktree fix-scroll")
        #expect(location(loose) == "~/Downloads")
        #expect(location(web) == "coeval › apps/web")
        #expect(location(api) == "coeval › apps/api")
        #expect(location(peekyAgents) == "peeky")
        #expect(location(coevalAgents) == "coeval")
    }

    @Test("显示条目：只有打不开的才带原因；悬停提示首行是 ~ 缩写的完整路径，次行按状态说明")
    func itemsCarryReasonAndTooltipPerAvailability() throws {
        let openedAt: TimeInterval = 1_000
        let alive = entry("\(peekyRoot)/README.md", at: openedAt, origin: peeky)
        let inWorktree = entry("\(worktreeRoot)/src/scroll.ts", at: openedAt, origin: fixScroll)
        let loose = entry("\(home)/Downloads/events.jsonl", at: openedAt)
        let onDisk: Set<String> = [alive.path]

        let items = RecentFiles.items(
            for: [alive, inWorktree, loose],
            pathExists: onDisk.contains,
            homePath: home,
            now: Date(timeIntervalSince1970: openedAt + 120)
        )
        try #require(items.count == 3)

        #expect(items[0].isOpenable)
        #expect(items[0].reason == nil)
        #expect(items[0].tooltip == "~/Documents/peeky/README.md\nOpened 2 minutes ago")

        #expect(!items[1].isOpenable)
        #expect(items[1].reason == "Worktree deleted")
        #expect(items[1].tooltip == "~/Documents/peeky/.claude/worktrees/fix-scroll/src/scroll.ts\nThe worktree “fix-scroll” is no longer on disk.")

        #expect(!items[2].isOpenable)
        #expect(items[2].reason == "File moved or deleted")
        #expect(items[2].tooltip == "~/Downloads/events.jsonl\nNo file at this path anymore.")
    }
}
