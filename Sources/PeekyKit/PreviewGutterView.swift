import AppKit
import Foundation

final class PreviewGutterView: NSRulerView {
    var configuration = PreviewGutterConfiguration.hidden {
        didSet {
            ruleThickness = configuration.width
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = nil
        ruleThickness = configuration.width
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            configuration.isVisible,
            let textView = clientView as? NSTextView,
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

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: textView.visibleRect,
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
