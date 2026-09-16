import Testing
import AppKit
@testable import PeekyKit

// MARK: - Fixture helpers
//
// `NSView.toolTip` 的浮出由 `NSToolTipManager` 挂在 view 上的一块 tracking area 承载，
// 它与自建的悬停区并列在同一个 `trackingAreas` 数组里。所以「tooltip 会不会浮出」这件事
// 量的是那块 area 在不在，而不是 `toolTip` 这个属性值——属性值一直都在。

@MainActor
private func makeLoadedController() throws -> (PreviewWindowController, NSWindow) {
    _ = NSApplication.shared
    let controller = PreviewWindowController()
    let window = try #require(controller.window)
    window.setContentSize(NSSize(width: 1080, height: 700))
    controller.open(url: URL(fileURLWithPath: #filePath))
    window.contentView?.layoutSubtreeIfNeeded()
    window.contentView?.display()
    return (controller, window)
}

@MainActor
private func headerIconButtons(_ window: NSWindow) -> [NSButton] {
    guard let content = window.contentView else { return [] }

    var found: [NSButton] = []
    func walk(_ view: NSView) {
        if let button = view as? NSButton { found.append(button) }
        view.subviews.forEach(walk)
    }
    walk(content)

    let headerTitles = ["Copy File Content (⌥⌘C)", "Copy File Name",
                        "Copy Absolute Path (⇧⌘C)", "Copy Relative Path (⇧⌥⌘C)",
                        "Reveal in Finder", "View Options"]
    return headerTitles.compactMap { title in
        found.first(where: { $0.toolTip == title })
    }
}

@MainActor
private func toolTipAreaCount(_ view: NSView) -> Int {
    view.trackingAreas.filter { area in
        guard let owner = area.owner else { return false }
        return String(describing: type(of: owner)) == "NSToolTipManager"
    }.count
}

@MainActor
private func ownTrackingAreaCount(_ view: NSView) -> Int {
    view.trackingAreas.filter { $0.owner as? NSView === view }.count
}

@Suite("Visible_hoverTooltip")
@MainActor
struct Visible_hoverTooltip {

    @Test("顶栏 6 个图标按钮在一轮 tracking area 重建之后仍挂着系统的 tooltip 区")
    func toolTipAreaSurvivesOneRebuild() throws {
        let (_, window) = try makeLoadedController()
        let buttons = headerIconButtons(window)
        #expect(buttons.count == 6)

        for button in buttons {
            button.updateTrackingAreas()
            #expect(toolTipAreaCount(button) == 1, "\(button.toolTip ?? "?") 丢了 tooltip 区")
        }
    }

    @Test("反复重建之后 tooltip 区仍是 1 块、自建悬停区也不累积")
    func repeatedRebuildsStaySteady() throws {
        let (_, window) = try makeLoadedController()
        let buttons = headerIconButtons(window)
        #expect(buttons.count == 6)

        for button in buttons {
            for _ in 0..<5 { button.updateTrackingAreas() }
            #expect(toolTipAreaCount(button) == 1, "\(button.toolTip ?? "?") 的 tooltip 区数量不对")
            #expect(ownTrackingAreaCount(button) == 1, "\(button.toolTip ?? "?") 的悬停区累积了")
        }
    }

    @Test("自建的那块区仍在监听进出，悬停反馈照常")
    func hoverAreaStillListensForEnterAndExit() throws {
        let (_, window) = try makeLoadedController()
        let buttons = headerIconButtons(window)
        #expect(buttons.count == 6)

        for button in buttons {
            button.updateTrackingAreas()
            let own = button.trackingAreas.first { $0.owner as? NSView === button }
            let area = try #require(own, "\(button.toolTip ?? "?") 没有自建悬停区")
            #expect(area.options.contains(.mouseEnteredAndExited))
            #expect(area.options.contains(.inVisibleRect))
        }
    }

    @Test("HoverTracking.reinstall 装上自己那块、留下别人那块")
    func reinstallKeepsForeignAreas() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let foreignOwner = NSView()
        view.addTrackingArea(
            NSTrackingArea(rect: view.bounds, options: [.mouseMoved, .activeAlways],
                           owner: foreignOwner, userInfo: nil)
        )

        var mine: NSTrackingArea?
        HoverTracking.reinstall(on: view, previous: &mine)
        HoverTracking.reinstall(on: view, previous: &mine)

        #expect(view.trackingAreas.count == 2)
        #expect(ownTrackingAreaCount(view) == 1)
        #expect(view.trackingAreas.contains { $0.owner as? NSView === foreignOwner })
    }
}
