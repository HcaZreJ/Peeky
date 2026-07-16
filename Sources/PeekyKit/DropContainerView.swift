import AppKit

@MainActor
enum FileDropSupport {
    static func register(_ view: NSView) {
        view.registerForDraggedTypes([.fileURL])
    }

    static func register(_ window: NSWindow) {
        window.registerForDraggedTypes([.fileURL])
    }

    static func draggingEntered(_ sender: NSDraggingInfo, onActiveChanged: ((Bool) -> Void)?) -> NSDragOperation {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        onActiveChanged?(true)
        return .copy
    }

    static func draggingUpdated(_ sender: NSDraggingInfo, onActiveChanged: ((Bool) -> Void)?) -> NSDragOperation {
        draggingEntered(sender, onActiveChanged: onActiveChanged)
    }

    static func draggingExited(onActiveChanged: ((Bool) -> Void)?) {
        onActiveChanged?(false)
    }

    static func prepareDrop(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender.draggingPasteboard).isEmpty
    }

    static func performDrop(
        _ sender: NSDraggingInfo,
        onActiveChanged: ((Bool) -> Void)?,
        onDropFiles: (([URL]) -> Void)?
    ) -> Bool {
        onActiveChanged?(false)
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )

        return objects?.compactMap { object in
            if let url = object as? URL {
                return url
            }
            return (object as? NSURL) as URL?
        } ?? []
    }
}

final class DropWindow: NSWindow {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        FileDropSupport.register(self)
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }
}

final class DropContainerView: NSView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FileDropSupport.register(self)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        FileDropSupport.register(self)
        wantsLayer = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }

    func setDropHighlight(_ active: Bool) {
        layer?.borderWidth = active ? 3 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
    }
}

final class DropHeaderView: NSVisualEffectView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FileDropSupport.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        FileDropSupport.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }
}

final class DropSidebarView: NSVisualEffectView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FileDropSupport.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        FileDropSupport.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }
}

final class DropScrollView: NSScrollView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FileDropSupport.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        FileDropSupport.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }
}

/// Renders a contiguous block-level background for Markdown fenced/indented/HTML
/// code block lines instead of TextKit's stock per-glyph background fill.
///
/// `NSLayoutManager`'s default `fillBackgroundRectArray` fills only the rects it
/// receives, which are sized to the actual glyph extent of the attributed run —
/// flush against the paragraph's `headIndent`, so the background's left edge sits
/// right at the first character with no visible padding. Every code-block line run
/// is tagged with `MarkdownRenderer.codeBlockBackgroundAttributeKey`; when that
/// marker is present this subclass fills the full `lineFragmentRect` width for each
/// line fragment the range spans instead (contiguous, non-jagged), while the text
/// itself stays inset by the paragraph's `headIndent`/`tailIndent` — producing
/// visible left/right padding inside the block. Ranges without the marker (inline
/// code, plain body text) fall through to `super`, so their fills are unaffected.
final class CodeBlockBackgroundLayoutManager: NSLayoutManager {
    private var currentBackgroundOrigin: NSPoint = .zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        currentBackgroundOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard
            charRange.location != NSNotFound,
            charRange.length > 0,
            let storage = textStorage,
            charRange.location < storage.length
        else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }

        if storage.attribute(
            MarkdownRenderer.codeBlockBackgroundAttributeKey,
            at: charRange.location,
            effectiveRange: nil
        ) != nil {
            let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
                return
            }

            resolvedBackgroundColor(color).setFill()

            var glyphIndex = glyphRange.location
            while glyphIndex < NSMaxRange(glyphRange) {
                var lineGlyphRange = NSRange()
                let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
                lineRect.offsetBy(dx: currentBackgroundOrigin.x, dy: currentBackgroundOrigin.y).fill()
                glyphIndex = NSMaxRange(lineGlyphRange)
            }
            return
        }

        if storage.attribute(
            MarkdownRenderer.inlineCodeBackgroundAttributeKey,
            at: charRange.location,
            effectiveRange: nil
        ) != nil {
            let glyphRange = self.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            guard
                glyphRange.length > 0,
                let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil)
            else {
                super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
                return
            }

            resolvedBackgroundColor(color).setFill()

            let horizontalPadding: CGFloat = 4
            let verticalPadding: CGFloat = 1.5
            let fallbackFont = NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular)

            // enumerateEnclosingRects 返回的是选区高亮用的字形紧致矩形——即便在
            // NSTextTable 单元格内也贴着字形，而 boundingRect(forGlyphRange:in:)
            // 在单元格里返回整行单元格宽（会把胶囊撑成一整条）。逐个紧致矩形按
            // 该行 baseline + 字体度量收紧纵向、横向加内边距后画圆角胶囊。
            enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { [self] enclosingRect, _ in
                let probe = CGPoint(x: enclosingRect.midX, y: enclosingRect.midY)
                let glyphIndex = self.glyphIndex(for: probe, in: container)
                let charIndex = characterIndexForGlyph(at: glyphIndex)
                let font = (charIndex < storage.length
                    ? storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont
                    : nil) ?? fallbackFont

                let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let baselineY = lineRect.minY + location(forGlyphAt: glyphIndex).y

                let capsuleTop = baselineY - font.ascender - verticalPadding
                let capsuleHeight = (font.ascender - font.descender) + 2 * verticalPadding
                let capsule = NSRect(
                    x: enclosingRect.minX - horizontalPadding,
                    y: capsuleTop,
                    width: enclosingRect.width + 2 * horizontalPadding,
                    height: capsuleHeight
                ).offsetBy(dx: currentBackgroundOrigin.x, dy: currentBackgroundOrigin.y)

                let radius = min(5, capsule.height / 2)
                NSBezierPath(roundedRect: capsule, xRadius: radius, yRadius: radius).fill()
            }
            return
        }

        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }

    /// 把（可能是动态外观的）背景色按 textView 当前 effectiveAppearance 解析为具体
    /// sRGB 值再用于自绘填充。背景绘制回调里 NSAppearance.current 不保证是视图的
    /// 外观，动态色会按默认（通常浅色）外观烘焙——暗色模式下把代码块/胶囊底色渲成
    /// 近白。显式在视图外观下解析可消除该串色。
    private func resolvedBackgroundColor(_ color: NSColor) -> NSColor {
        guard let appearance = textContainers.first?.textView?.effectiveAppearance else {
            return color
        }
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}

final class DropTextView: NSTextView {
    var onDropFiles: (([URL]) -> Void)?
    var onFileDragActiveChanged: ((Bool) -> Void)?
    /// 每次 draw 后回调（gutter 的滚动/重排跟随信号，见 PreviewGutterView）。
    var onDidDraw: (() -> Void)?
    var overlayConfiguration = PreviewTextOverlayConfiguration.hidden {
        didSet {
            needsDisplay = true
        }
    }

    convenience init() {
        // macOS 15+ / Tahoe(26) NSTextView 默认走 TextKit2；gutter (PreviewGutterView) 与
        // draw 覆盖层都读 textView.layoutManager 老 API，混用后 draw 管线错位（textStorage
        // 有内容却看不见字，能 ⌘A/⌘C 复制到文本）。显式构造 TextKit1 栈把管线钉死在
        // NSLayoutManager 侧。
        let storage = NSTextStorage()
        let layoutManager = CodeBlockBackgroundLayoutManager()
        let container = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FileDropSupport.register(self)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        FileDropSupport.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        FileDropSupport.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingEntered(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        FileDropSupport.draggingUpdated(sender, onActiveChanged: onFileDragActiveChanged)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        FileDropSupport.draggingExited(onActiveChanged: onFileDragActiveChanged)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.prepareDrop(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        FileDropSupport.performDrop(
            sender,
            onActiveChanged: onFileDragActiveChanged,
            onDropFiles: onDropFiles
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawRecordSeparators()
        drawIndentGuides()
        drawRecordAnnotations()
        onDidDraw?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func drawRecordSeparators() {
        guard !overlayConfiguration.recordSeparatorLocations.isEmpty else { return }

        let path = NSBezierPath()
        path.lineWidth = 1

        for location in overlayConfiguration.recordSeparatorLocations {
            guard let rects = lineRects(forCharacterLocation: location) else { continue }
            let y = max(rects.lineRect.minY - 7, bounds.minY)
            path.move(to: NSPoint(x: textContainerOrigin.x, y: y))
            path.line(to: NSPoint(x: bounds.maxX - 12, y: y))
        }

        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }

    private func drawIndentGuides() {
        guard
            overlayConfiguration.showsIndentGuides,
            let layoutManager,
            let textContainer,
            let textStorage,
            textStorage.length > 0
        else {
            return
        }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let spaceWidth = " ".size(withAttributes: [.font: font]).width
        let text = string as NSString
        let path = NSBezierPath()
        path.lineWidth = 1

        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            var lineGlyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let line = text.substring(with: charRange)
            let leadingSpaces = countLeadingSpaces(in: line)

            if leadingSpaces >= 2 {
                let yStart = textContainerOrigin.y + lineRect.minY + 1
                let yEnd = textContainerOrigin.y + lineRect.maxY - 1

                for level in stride(from: 2, through: leadingSpaces, by: 2) {
                    let x = textContainerOrigin.x + CGFloat(level) * spaceWidth - spaceWidth / 2
                    path.move(to: NSPoint(x: x, y: yStart))
                    path.line(to: NSPoint(x: x, y: yEnd))
                }
            }

            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        NSColor.separatorColor.withAlphaComponent(0.38).setStroke()
        path.stroke()
    }

    private func drawRecordAnnotations() {
        guard !overlayConfiguration.recordAnnotations.isEmpty else { return }

        for annotation in overlayConfiguration.recordAnnotations {
            guard let rects = lineRects(forCharacterLocation: annotation.characterLocation) else { continue }

            let font = NSFont.systemFont(ofSize: 11, weight: annotation.isWarning ? .semibold : .regular)
            let color = annotation.isWarning ? NSColor.systemRed : NSColor.secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let size = annotation.text.size(withAttributes: attributes)
            let x = rects.usedRect.maxX + 18
            guard x + size.width + 12 < visibleRect.maxX else { continue }

            let y = rects.lineRect.minY + max(0, (rects.lineRect.height - size.height) / 2)
            annotation.text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }

    private func lineRects(forCharacterLocation location: Int) -> (lineRect: NSRect, usedRect: NSRect)? {
        guard
            let layoutManager,
            let textStorage,
            textStorage.length > 0
        else {
            return nil
        }

        let characterLocation = min(max(location, 0), textStorage.length - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterLocation)

        var lineGlyphRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineGlyphRange,
            withoutAdditionalLayout: true
        ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let usedRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

        guard visibleRect.intersects(lineRect.insetBy(dx: -1, dy: -12)) else { return nil }
        return (lineRect, usedRect)
    }

    private func countLeadingSpaces(in line: String) -> Int {
        var count = 0
        for scalar in line.unicodeScalars {
            if scalar == " " {
                count += 1
            } else {
                break
            }
        }
        return count
    }
}
