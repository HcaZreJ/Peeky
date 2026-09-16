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

    let headerTitles = ["Copy File Content (⌥⌘C)", "Copy File Name",
                        "Copy Absolute Path (⇧⌘C)", "Copy Relative Path (⇧⌥⌘C)",
                        "Reveal in Finder", "View Options"]
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

/// 量一张模板图里**墨迹**的外接框（不是 image.size——那里面含留白）。超采样 4 倍再扫 alpha，
/// 描边末端是亚像素的，按 1 倍扫会把末端算丢。
@MainActor
private func inkSize(of image: NSImage) -> NSSize? {
    let sample: CGFloat = 4
    let wide = Int((image.size.width * sample).rounded(.up))
    let high = Int((image.size.height * sample).rounded(.up))
    guard
        wide > 0, high > 0,
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.black.setFill()
    image.draw(in: NSRect(origin: .zero, size: NSSize(width: wide, height: high)))
    NSGraphicsContext.restoreGraphicsState()

    var left = wide, right = -1, top = high, bottom = -1
    for row in 0..<high {
        for column in 0..<wide where (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.08 {
            left = min(left, column)
            right = max(right, column)
            top = min(top, row)
            bottom = max(bottom, row)
        }
    }
    guard bottom >= 0 else { return nil }
    return NSSize(
        width: CGFloat(right - left + 1) / sample,
        height: CGFloat(bottom - top + 1) / sample
    )
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

    @Test("6 个按钮等高、上缘齐平，宽度各自容下自己那行文字")
    func iconButtonsShareOneBaseline() throws {
        let (_, window) = try makeLoadedController()
        let frames = headerButtons(window).map(\.frame)
        #expect(frames.count == 6)
        guard let first = frames.first else { return }

        #expect(frames.allSatisfy { abs($0.height - 36) < 0.01 })
        #expect(frames.allSatisfy { abs($0.minY - first.minY) < 0.01 })
        // 宽度随文字长度变化，下限 34（左右各 6pt 内边距，悬停底不贴字）
        #expect(frames.allSatisfy { $0.width >= 34 })
        // "Full path" 比 "Name" 长，按钮也跟着宽
        #expect(frames[2].width > frames[1].width)

        // 六颗的图标画布同尺寸：画布不统一时 imageAbove 会把文字推到六个不同高度
        let boxes = Set(headerButtons(window).map { "\($0.button.image?.size ?? .zero)" })
        #expect(boxes.count == 1)
    }

    @Test("六颗图标同尺寸：墨迹长边都是 ToolbarIcon.inkSide")
    func iconInkSharesOneBox() throws {
        let (_, window) = try makeLoadedController()
        let buttons = headerButtons(window).map(\.button)
        #expect(buttons.count == 6)

        // 六颗同网格自绘，墨迹并集按长边缩到 ToolbarIcon.inkSide——长边一致就是尺寸契约本身。
        // 换图标时长边一旦重新散开，这里就会红——这一排「大小不一」被用户挑过两次。
        //
        // 宽高比不入断言：六颗照各自的现成约定画（正文行是横的、行李牌是方的、三点是一条），
        // 硬把它们撑成同一个宽高比，只能靠在小尺寸里堆笔画换，而笔画一密就糊。
        var sizes: [NSSize] = []
        for button in buttons {
            let image = try #require(button.image, "\(button.toolTip ?? "?") 没有图标")
            sizes.append(try #require(inkSize(of: image), "\(button.toolTip ?? "?") 图标是空的"))
        }
        for (button, size) in zip(buttons, sizes) {
            let longEdge = max(size.width, size.height)
            #expect(
                abs(longEdge - ToolbarIcon.inkSide) <= 1.0,
                "\(button.toolTip ?? "?") 墨迹长边 \(longEdge)pt，与 \(ToolbarIcon.inkSide)pt 差出 1pt 以上"
            )
        }
    }

    @Test("6 个按钮各自带图标、文字与 tooltip，点击落在自己身上")
    func iconButtonsAreLabelledAndHittable() throws {
        let (_, window) = try makeLoadedController()
        let content = try #require(window.contentView)

        for (button, frame) in headerButtons(window) {
            #expect(button.toolTip?.isEmpty == false)
            // 符号名写错时 NSImage(systemSymbolName:) 返回 nil，按钮只剩一行字
            #expect(button.image != nil)
            #expect(button.attributedTitle.length > 0)
            let hit = content.hitTest(NSPoint(x: frame.midX, y: frame.midY))
            #expect(hit === button || (hit?.isDescendant(of: button) ?? false))
        }
    }

    @Test("在 repo 内的文件，复制相对路径按钮可用")
    func copyRelativePathIsEnabledInsideARepository() throws {
        let (_, window) = try makeLoadedController()
        let relative = headerButtons(window).first { $0.button.toolTip == "Copy Relative Path (⇧⌥⌘C)" }
        #expect(try #require(relative).button.isEnabled)
    }
}
