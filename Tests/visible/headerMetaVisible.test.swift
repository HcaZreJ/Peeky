import Testing
import AppKit
@testable import PeekyKit

// MARK: - Fixture helpers
//
// 用真实的 PreviewWindowController 打开一份修改时间钉死的文件，读顶栏标题下面那行副标题。
// Markdown 与其它文件走两条渲染路径（WebView / NSTextView），副标题各拼各的，两条都要验。

private func makeFixtureFile(named name: String, modifiedAt: Date) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("headerMetaVisibleTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try "# Title\n\nbody\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    return url
}

@MainActor
private func openInWindow(_ url: URL, width: CGFloat = 1080) throws -> (PreviewWindowController, NSWindow) {
    _ = NSApplication.shared
    let controller = PreviewWindowController()
    let window = try #require(controller.window)
    window.setContentSize(NSSize(width: width, height: 700))
    controller.open(url: url)
    window.contentView?.layoutSubtreeIfNeeded()
    return (controller, window)
}

@MainActor
private func subviews<View: NSView>(of type: View.Type, in window: NSWindow) -> [View] {
    var found: [View] = []
    func walk(_ view: NSView) {
        if let match = view as? View { found.append(match) }
        view.subviews.forEach(walk)
    }
    window.contentView.map(walk)
    return found
}

/// 顶栏副标题：形如 "最后更改于：…  |  Markdown  |  15 bytes  |  UTF-8" 的那一个 label。
@MainActor
private func headerMetaText(in window: NSWindow) throws -> String {
    try #require(subviews(of: NSTextField.self, in: window).first { $0.stringValue.contains("  |  UTF-8") }).stringValue
}

/// 顶栏最右一颗按钮（More）的右缘。
@MainActor
private func controlsTrailingEdge(in window: NSWindow) throws -> CGFloat {
    let more = try #require(subviews(of: NSButton.self, in: window).first { $0.toolTip == "View Options" })
    return try #require(more.superview).convert(more.frame, to: window.contentView).maxX
}

@Suite("Visible_headerMeta")
@MainActor
struct Visible_headerMeta {
    private let modifiedAt = Date(timeIntervalSince1970: 1_772_672_823)

    // 时间排在副标题最前：这一行放不下时从尾部省略，时间这一段始终完整。

    @Test("Markdown 文件的顶栏副标题以最后更改时间开头")
    func markdownMetaShowsLastModified() throws {
        let url = try makeFixtureFile(named: "notes.md", modifiedAt: modifiedAt)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (_, window) = try openInWindow(url)

        #expect(try headerMetaText(in: window).hasPrefix(LastModifiedText.format(modifiedAt) + "  |  "))
    }

    @Test("源码文件的顶栏副标题以最后更改时间开头")
    func sourceMetaShowsLastModified() throws {
        let url = try makeFixtureFile(named: "script.py", modifiedAt: modifiedAt)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (_, window) = try openInWindow(url)

        #expect(try headerMetaText(in: window).hasPrefix(LastModifiedText.format(modifiedAt) + "  |  "))
    }

    @Test("文件在磁盘上被改写后，从磁盘刷新一次，顶栏换成新的更改时间")
    func metaFollowsDiskRewrite() throws {
        let url = try makeFixtureFile(named: "script.py", modifiedAt: modifiedAt)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (controller, window) = try openInWindow(url)

        let rewrittenAt = modifiedAt.addingTimeInterval(3_725)
        try "print('rewritten')\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: rewrittenAt], ofItemAtPath: url.path)
        // URL 的文件属性缓存到 runloop 转过一轮才清；真实 app 里改写与刷新总隔着几轮，
        // 测试里不转一轮，刷新读到的还是打开时缓存的那个修改时间。
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        controller.refreshFromDisk()

        #expect(try headerMetaText(in: window).hasPrefix(LastModifiedText.format(rewrittenAt) + "  |  "))
    }

    @Test("副标题放不下时只省略自己：窄窗口里按钮组仍贴着窗口右缘")
    func longMetaTruncatesInsteadOfPushingControls() throws {
        // 源码文件的顶栏多一个 Format / Raw 段控件，是标题区最窄的情形；900 宽时副标题必然放不下。
        // 副标题不肯省略时，按钮组会被挤出窗口右缘（真实 app 里表现为窗口被撑宽）。
        let url = try makeFixtureFile(named: "script.py", modifiedAt: modifiedAt)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let (_, window) = try openInWindow(url, width: 900)

        #expect(abs(try controlsTrailingEdge(in: window) - (900 - 14)) < 0.6)
    }
}
