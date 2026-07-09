import AppKit
import Foundation

/// 行号/记录标记 gutter。与 scrollView 平级的独立 NSView（macOS 26 起
/// NSRulerView 用 clipView.bounds 负偏移给 ruler 让位，与 NSTextView 的
/// draw pipeline 冲突导致正文不绘制，独立 subview 绕开该机制）。
///
/// clipsToBounds 必须为 true：macOS 14 起 NSView 默认不裁剪，draw 收到的
/// dirtyRect 可远大于 bounds（窗口首帧是整窗），fill(dirtyRect) 会把背景色
/// 涂到 header/sidebar 等兄弟视图上，表现为它们"空白"（issue #2）。
///
/// 滚动/重排跟随信号：DropTextView 每次 draw 后回调 textViewDidDraw()，
/// gutter 对比可见区滚动偏移有变化才自我重绘（textView 滚动与重排必然
/// 触发自身 draw，copy-on-scroll 也会绘制新露出的条带）。
final class PreviewGutterView: NSView {
    var configuration = PreviewGutterConfiguration.hidden {
        didSet {
            needsDisplay = true
        }
    }

    private weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    func connect(textView: NSTextView) {
        self.textView = textView
    }

    func textViewDidDraw() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            configuration.isVisible,
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let separatorX = bounds.maxX - 0.5
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: separatorX, y: bounds.minY),
            to: NSPoint(x: separatorX, y: bounds.maxY)
        )

        // 用 withoutAdditionalLayout 变体：gutter 绘制零布局副作用。文档
        // 布局由 PreviewWindowController 的分片布局泵主动推进（macOS 26 上
        // TextKit1 惰性布局不自行推进，无人推进时长文档 frame 停在视口
        // 高度、scrollView 无可滚动区域，issue #3）；可见区在 textView
        // 自绘时已由 AppKit 布局完成，此处只读已就绪的数据。
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

        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let charRange = layoutManager.characterRange(
                forGlyphRange: lineGlyphRange,
                actualGlyphRange: nil
            )

            let label: String?
            let isWarning: Bool

            if let marker = markerByLocation[charRange.location] {
                label = marker.label
                isWarning = marker.isWarning
            } else if let visualLine = visualLineNumber(for: charRange.location, lineStarts: lineStarts) {
                label = String(visualLine)
                isWarning = false
            } else {
                label = nil
                isWarning = false
            }

            if let label {
                drawLabel(
                    label,
                    isWarning: isWarning,
                    lineRect: lineRect,
                    textView: textView
                )
            }

            glyphIndex = NSMaxRange(lineGlyphRange)
        }
    }

    private func drawLabel(
        _ label: String,
        isWarning: Bool,
        lineRect: NSRect,
        textView: NSTextView
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
        let y = textView.textContainerOrigin.y
            + lineRect.minY
            - textView.visibleRect.minY
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
