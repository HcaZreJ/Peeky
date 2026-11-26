import Testing
import AppKit
@testable import PeekyKit
@testable import PeekyCore

// 用真实的 PreviewWindowController 打开纯文本文件，按用户的操作走查找：在搜索框里打字、Enter、Esc。
// 纯文本走 NSTextView 那条路，小文件就地查找，整个流程同步完成，测试里不转 RunLoop。
// Markdown 那条路依赖页面端脚本（异步），由真机冒烟验证。

private func makeFindFixture(lines: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("findBarVisibleTest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("keywords.txt")
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor
private func openFindWindow(_ url: URL, width: CGFloat = 1080) throws -> (PreviewWindowController, NSWindow) {
    _ = NSApplication.shared
    let controller = PreviewWindowController()
    controller.findPasteboard = NSPasteboard.withUniqueName()
    let window = try #require(controller.window)
    window.setContentSize(NSSize(width: width, height: 700))
    controller.open(url: url)
    window.contentView?.layoutSubtreeIfNeeded()
    return (controller, window)
}

@MainActor
private func firstSubview<View: NSView>(of type: View.Type, in window: NSWindow) -> View? {
    func walk(_ view: NSView) -> View? {
        if let match = view as? View { return match }
        for child in view.subviews {
            if let found = walk(child) { return found }
        }
        return nil
    }
    return window.contentView.flatMap(walk)
}

/// 模拟在搜索框里打出 `text`（走搜索框代理的真实路径）。
@MainActor
private func type(_ text: String, into bar: FindBarView) {
    bar.searchField.stringValue = text
    bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.searchField))
}

/// 模拟在搜索框里按下某个键（Enter → insertNewline，Esc → cancelOperation）。
@MainActor
private func press(_ command: Selector, in bar: FindBarView) {
    _ = bar.control(bar.searchField, textView: NSTextView(), doCommandBy: command)
}

private let threeMatches = [
    "先回答：孤儿药是什么？",
    "罕见病药物也叫 orphan drug。",
    "第二处孤儿药。",
    "其他内容。",
    "第三处：孤儿药认定（ODD）。"
]

@Suite("Visible_findBar")
@MainActor
struct Visible_findBar {

    @Test("⌘F 后打字：三处匹配全部高亮，计数从第一处开始")
    func test_findBar_typingHighlightsAllMatches() throws {
        let (controller, window) = try openFindWindow(try makeFindFixture(lines: threeMatches))
        controller.showFindBar()
        #expect(controller.isFindBarShown)
        let bar = try #require(firstSubview(of: FindBarView.self, in: window))
        let textView = try #require(firstSubview(of: DropTextView.self, in: window))

        type("孤儿药", into: bar)

        #expect(controller.findCountText == "1 of 3")
        let highlights = try #require(textView.findHighlights)
        let text = textView.string as NSString
        #expect(highlights.ranges.map { text.substring(with: $0) } == ["孤儿药", "孤儿药", "孤儿药"])
        #expect(highlights.currentIndex == 0)

        type("不存在的词", into: bar)
        #expect(controller.findCountText == "No matches")
        #expect(textView.findHighlights == nil)
    }

    @Test("Enter 下一个、末尾回到第一个；⇧⌘G 上一个；Esc 收起后当前匹配成为选中文字")
    func test_findBar_navigateAndCloseSelectsCurrentMatch() throws {
        let (controller, window) = try openFindWindow(try makeFindFixture(lines: threeMatches))
        controller.showFindBar()
        let bar = try #require(firstSubview(of: FindBarView.self, in: window))
        let textView = try #require(firstSubview(of: DropTextView.self, in: window))
        type("孤儿药", into: bar)

        press(#selector(NSResponder.insertNewline(_:)), in: bar)
        #expect(controller.findCountText == "2 of 3")
        press(#selector(NSResponder.insertNewline(_:)), in: bar)
        #expect(controller.findCountText == "3 of 3")
        press(#selector(NSResponder.insertNewline(_:)), in: bar)
        #expect(controller.findCountText == "1 of 3")
        controller.findPrevious()
        #expect(controller.findCountText == "3 of 3")
        controller.findPrevious()
        #expect(controller.findCountText == "2 of 3")

        press(#selector(NSResponder.cancelOperation(_:)), in: bar)
        #expect(controller.isFindBarShown == false)
        #expect(textView.findHighlights == nil)
        let secondMatch = (textView.string as NSString).range(of: "第二处孤儿药").location + 3
        #expect(textView.selectedRange() == NSRange(location: secondMatch, length: 3))
    }

    @Test("带着上次的搜索词重开：不滚动；第一次 Enter 先滚到视野外的当前匹配，不跳过它")
    func test_findBar_reopenDoesNotScrollAndFirstEnterRevealsCurrent() throws {
        var lines = (1...400).map { "第 \($0) 行" }
        lines[299] = "第 300 行：孤儿药"
        lines[349] = "第 350 行：孤儿药"
        let (controller, window) = try openFindWindow(try makeFindFixture(lines: lines))
        let bar = try #require(firstSubview(of: FindBarView.self, in: window))
        let textView = try #require(firstSubview(of: DropTextView.self, in: window))

        controller.showFindBar()
        type("孤儿药", into: bar)
        press(#selector(NSResponder.cancelOperation(_:)), in: bar)
        textView.scroll(.zero)
        #expect(textView.visibleRect.minY == 0)

        controller.showFindBar()
        #expect(bar.query == "孤儿药")
        #expect(controller.findCountText == "1 of 2")
        #expect(textView.visibleRect.minY == 0)

        press(#selector(NSResponder.insertNewline(_:)), in: bar)
        #expect(controller.findCountText == "1 of 2")
        let firstMatch = (textView.string as NSString).range(of: "孤儿药")
        let glyphs = try #require(textView.layoutManager).glyphRange(forCharacterRange: firstMatch, actualCharacterRange: nil)
        let matchRect = try #require(textView.layoutManager).boundingRect(forGlyphRange: glyphs, in: try #require(textView.textContainer))
        #expect(textView.visibleRect.minY > 0)
        #expect(textView.visibleRect.contains(matchRect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)))

        press(#selector(NSResponder.insertNewline(_:)), in: bar)
        #expect(controller.findCountText == "2 of 2")
    }

    @Test("窗口缩到最窄：查找栏在内容区里收得下，不把窗口撑宽")
    func test_findBar_fitsNarrowestWindow() throws {
        let (controller, window) = try openFindWindow(try makeFindFixture(lines: threeMatches), width: 680)
        controller.showFindBar()
        let bar = try #require(firstSubview(of: FindBarView.self, in: window))
        type("孤儿药", into: bar)
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(window.frame.width == 680)
        // 按钮 frame 含系统边框留白，量对齐框（看得见的按钮外缘）。
        let doneEdge = bar.doneButton.alignmentRect(forFrame: bar.doneButton.frame).maxX
        #expect(doneEdge <= bar.bounds.maxX - 8)
        #expect(bar.searchField.frame.width >= FindBarView.fieldMinimumWidth)
    }
}

