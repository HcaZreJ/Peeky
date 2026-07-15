import AppKit
import Foundation

/// 行号/记录标记 gutter：挂载为 scrollView.verticalRulerView（NSRulerView 子类），
/// drawHashMarksAndLabels(in:) 全接管绘制；scrollView 原生 ruler 管线负责按需
/// 请求重绘，配合下方显式监听的三路信号覆盖所有会改变可见内容的场景。
///
/// textView（DropTextView）显式钉死在 TextKit 1（用 NSLayoutManager 构造，
/// 避免与 TextKit2 混用导致 draw 管线错位），故这里走 layoutManager
/// .enumerateLineFragments 的等价方案，而非 TextKit2 的
/// enumerateTextLayoutFragments/textLineFragments：对比每个可见视觉行片段的
/// characterRange.location 与逻辑行起始位置表（lineStarts，来自
/// PreviewDisplayMetadata.lineStartLocations）—— 命中才画行号。折行产生的后续
/// 视觉行其 characterRange.location 必然大于对应逻辑行的起始位置，不会命中
/// lineStarts 中的任何项，因此天然只在每个逻辑行的首个视觉行编号。
///
/// 滚动同步用 convert(NSZeroPoint, from: textView) 取 textView 坐标原点在 ruler
/// 自身坐标系中的位置：ruler 是 clientView 的兄弟视图（非其子视图），不会随
/// clipView 滚动自动获得一致的 bounds 原点，需要显式坐标转换换算当前滚动偏移，
/// 再叠加 textContainerOrigin + lineRect 得到该行在 ruler 坐标系里的绘制 y。
///
/// clipsToBounds 显式 true：macOS 14 起 NSView 默认不裁剪，越界绘制会涂到兄弟
/// 视图上（本 repo 曾踩过的坑，见 issue #2）。
final class PreviewGutterView: NSRulerView {
    var configuration = PreviewGutterConfiguration.hidden {
        didSet {
            ruleThickness = configuration.width
            hostScrollView?.rulersVisible = configuration.isVisible
            needsDisplay = true
        }
    }

    private weak var textView: NSTextView?
    private weak var hostScrollView: NSScrollView?
    // deinit 在 Swift 6 严格并发下总是 nonisolated，无法访问主 actor 隔离的存储属性；
    // 这里的清理只是把注册在 NotificationCenter 里的 token 摘掉，无跨线程数据竞争
    // 风险，nonisolated(unsafe) 据实况解除隔离检查。
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    convenience init() {
        self.init(scrollView: nil, orientation: .verticalRuler)
    }

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        clipsToBounds = true
        ruleThickness = configuration.width
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// 接线：clientView 决定 ruler 读取哪个视图的坐标系与内容；显式监听
    /// scrollView.contentView 的 bounds 变更（滚动）+ textView 的 frame 变更
    /// （重排/换行模式切换致高度变化）+ NSText.didChangeNotification（内容变更）
    /// 三路信号触发重绘，覆盖行号契约要求的全部跟随场景。
    func connect(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.hostScrollView = scrollView
        clientView = textView

        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens = []

        textView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            // addObserver(queue: .main) 的 block 形参类型是 @Sendable，编译器无法
            // 静态验证 OperationQueue.main 与 MainActor 隔离域一致；queue: .main
            // 已保证运行时必在主线程，assumeIsolated 据实况断言而非新开 Task 调度。
            MainActor.assumeIsolated {
                self?.needsDisplay = true
            }
        })
        observerTokens.append(center.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            // addObserver(queue: .main) 的 block 形参类型是 @Sendable，编译器无法
            // 静态验证 OperationQueue.main 与 MainActor 隔离域一致；queue: .main
            // 已保证运行时必在主线程，assumeIsolated 据实况断言而非新开 Task 调度。
            MainActor.assumeIsolated {
                self?.needsDisplay = true
            }
        })
        observerTokens.append(center.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            // addObserver(queue: .main) 的 block 形参类型是 @Sendable，编译器无法
            // 静态验证 OperationQueue.main 与 MainActor 隔离域一致；queue: .main
            // 已保证运行时必在主线程，assumeIsolated 据实况断言而非新开 Task 调度。
            MainActor.assumeIsolated {
                self?.needsDisplay = true
            }
        })

        ruleThickness = configuration.width
        scrollView.rulersVisible = configuration.isVisible
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            configuration.isVisible,
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let separatorX = bounds.maxX - 0.5
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: separatorX, y: bounds.minY),
            to: NSPoint(x: separatorX, y: bounds.maxY)
        )

        // withoutAdditionalLayout 变体：gutter 绘制零布局副作用，只读已就绪数据。
        // 长文档的分片布局由 PreviewWindowController 的布局泵主动推进，可见区在
        // textView 自绘时已由 AppKit 布局完成。
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: textView.visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }

        let markerByLocation: [Int: PreviewGutterMarker]
        let lineStarts: [Int]

        switch configuration.mode {
        case .hidden:
            markerByLocation = [:]
            lineStarts = []
        case .lineNumbers(let starts):
            markerByLocation = [:]
            lineStarts = starts
        case .markers(let markers):
            markerByLocation = Dictionary(uniqueKeysWithValues: markers.map { ($0.characterLocation, $0) })
            lineStarts = []
        }

        let originInRuler = convert(NSZeroPoint, from: textView)

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { lineRect, _, _, lineGlyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)

            let label: String?
            let isWarning: Bool

            if let marker = markerByLocation[charRange.location] {
                label = marker.label
                isWarning = marker.isWarning
            } else if let visualLine = self.visualLineNumber(for: charRange.location, lineStarts: lineStarts) {
                label = String(visualLine)
                isWarning = false
            } else {
                label = nil
                isWarning = false
            }

            if let label {
                self.drawLabel(
                    label,
                    isWarning: isWarning,
                    lineRect: lineRect,
                    textView: textView,
                    originInRuler: originInRuler
                )
            }
        }
    }

    private func drawLabel(
        _ label: String,
        isWarning: Bool,
        lineRect: NSRect,
        textView: NSTextView,
        originInRuler: NSPoint
    ) {
        let prefix = isWarning ? "! " : ""
        let displayLabel = prefix + label
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: isWarning ? .semibold : .regular)
        let color = isWarning ? NSColor.systemRed : NSColor.tertiaryLabelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = displayLabel.size(withAttributes: attributes)
        let y = originInRuler.y
            + textView.textContainerOrigin.y
            + lineRect.minY
            + max(0, (lineRect.height - size.height) / 2)
        let x = bounds.maxX - size.width - 8

        displayLabel.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private func visualLineNumber(for location: Int, lineStarts: [Int]) -> Int? {
        guard !lineStarts.isEmpty else { return nil }

        var low = 0
        var high = lineStarts.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        guard lineStarts[match] == location else { return nil }
        return match + 1
    }
}
