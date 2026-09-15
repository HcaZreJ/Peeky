import Testing
import AppKit
@testable import PeekyKit

// MARK: - Fixture helpers
//
// 用真实的 PreviewWindowController 打开真实文件，量顶栏按钮落在哪里。
// 这些数值就是用户看到的版面：6 个图标按钮成组停在右端，组内 8、两小组之间 12。

@MainActor
private func makeLoadedController() throws -> (PreviewWindowController, NSWindow) {
    _ = NSApplication.shared
    let controller = PreviewWindowController()
    let window = try #require(controller.window)
    window.setContentSize(NSSize(width: 1080, height: 700))
    controller.open(url: URL(fileURLWithPath: #filePath))
    window.contentView?.layoutSubtreeIfNeeded()
    return (controller, window)
}

@MainActor
private func headerButtons(_ window: NSWindow) -> [(button: NSButton, frame: NSRect)] {
    guard let content = window.contentView else { return [] }

    var found: [NSButton] = []
    func walk(_ view: NSView) {
        if let button = view as? NSButton { found.append(button) }
        view.subviews.forEach(walk)
    }
    walk(content)

    let headerTitles = ["Copy File Content", "Copy File Name", "Copy Absolute Path",
                        "Copy Relative Path", "Reveal in Finder", "More"]
    return headerTitles.compactMap { title in
        guard
            let button = found.first(where: { $0.toolTip == title }),
            let superview = button.superview
        else {
            return nil
        }
        return (button, superview.convert(button.frame, to: content))
    }
}

@Suite("Visible_headerLayout")
@MainActor
struct Visible_headerLayout {

    @Test("6 个图标按钮成组停在顶栏右端，组内 8、两小组之间 12")
    func iconButtonsPackAtTheTrailingEdge() throws {
        let (_, window) = try makeLoadedController()
        let buttons = headerButtons(window)
        #expect(buttons.count == 6)
        guard buttons.count == 6 else { return }

        let frames = buttons.map(\.frame)
        // 最后一个按钮的右缘落在顶栏右内边距上（headerStack 的 14pt）
        #expect(abs(frames[5].maxX - (1080 - 14)) < 0.6)

        // 复制组组内间距 8
        for index in 0..<3 {
            #expect(abs(frames[index + 1].minX - frames[index].maxX - 8) < 0.6)
        }
        // 复制组与定位组之间 12（大于组内间距，编码两个子类）
        #expect(abs(frames[4].minX - frames[3].maxX - 12) < 0.6)
        // 定位组组内间距 8
        #expect(abs(frames[5].minX - frames[4].maxX - 8) < 0.6)
    }

    @Test("6 个按钮等高等宽、上缘齐平，悬停底不会参差")
    func iconButtonsShareOneBaseline() throws {
        let (_, window) = try makeLoadedController()
        let frames = headerButtons(window).map(\.frame)
        #expect(frames.count == 6)
        guard let first = frames.first else { return }

        #expect(frames.allSatisfy { abs($0.width - 30) < 0.01 })
        #expect(frames.allSatisfy { abs($0.height - 24) < 0.01 })
        #expect(frames.allSatisfy { abs($0.minY - first.minY) < 0.01 })
    }

    @Test("6 个按钮各自带 tooltip，点击落在自己身上")
    func iconButtonsAreLabelledAndHittable() throws {
        let (_, window) = try makeLoadedController()
        let content = try #require(window.contentView)

        for (button, frame) in headerButtons(window) {
            #expect(button.toolTip?.isEmpty == false)
            let hit = content.hitTest(NSPoint(x: frame.midX, y: frame.midY))
            #expect(hit === button || (hit?.isDescendant(of: button) ?? false))
        }
    }

    @Test("在 repo 内的文件，复制相对路径按钮可用")
    func copyRelativePathIsEnabledInsideARepository() throws {
        let (_, window) = try makeLoadedController()
        let relative = headerButtons(window).first { $0.button.toolTip == "Copy Relative Path" }
        #expect(try #require(relative).button.isEnabled)
    }
}
