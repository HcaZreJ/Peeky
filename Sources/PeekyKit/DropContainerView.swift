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

        // 只处理 inline code 自身文字底色的填充：其 color 恒等于该处 .backgroundColor
        // 属性值。NSTextTable 的单元格底色/边框也经本方法绘制（charRange 落在单元格
        // 内容上、故 location 也带 inline 标记），但传入的是单元格底色/边框色而非 inline
        // 底色——用颜色相等把它们放行给 super，避免把单元格边框画成整格胶囊。
        let inlineBackground = storage.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? NSColor
        if storage.attribute(
            MarkdownRenderer.inlineCodeBackgroundAttributeKey,
            at: charRange.location,
            effectiveRange: nil
        ) != nil, let inlineBackground, color.isEqual(inlineBackground) {
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

            // 传入的 rectArray 是 TextKit 为该 .backgroundColor 段算好的字形紧致矩形
            // （横向贴字形、纵向为整行行高），单元格内外都正确；据此逐个把纵向收紧到
            // 贴文字高度、横向加内边距后画圆角胶囊。
            for i in 0..<rectCount {
                var glyphRect = rectArray[i]
                let probe = CGPoint(
                    x: glyphRect.midX - currentBackgroundOrigin.x,
                    y: glyphRect.midY - currentBackgroundOrigin.y
                )
                let glyphIndex = self.glyphIndex(for: probe, in: container)
                let charIndex = characterIndexForGlyph(at: glyphIndex)
                let font = (charIndex < storage.length
                    ? storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont
                    : nil) ?? fallbackFont

                let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let baselineViewY = lineRect.minY + location(forGlyphAt: glyphIndex).y + currentBackgroundOrigin.y

                // inline run 跨行换行时，TextKit 给非末行的矩形按选区语义延伸到
                // 行尾（含行末空白）；把右缘钳到该行 usedRect（实际字形使用宽度），
                // 胶囊只包住可见文字。行中不换行的矩形本就贴字形，钳制不生效。
                let usedRect = lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let usedMaxX = usedRect.maxX + currentBackgroundOrigin.x
                if glyphRect.maxX > usedMaxX {
                    glyphRect.size.width = usedMaxX - glyphRect.minX
                }
                guard glyphRect.width > 0 else { continue }

                let capsuleTop = baselineViewY - font.ascender - verticalPadding
                let capsuleHeight = (font.ascender - font.descender) + 2 * verticalPadding
                let capsule = NSRect(
                    x: glyphRect.minX - horizontalPadding,
                    y: capsuleTop,
                    width: glyphRect.width + 2 * horizontalPadding,
                    height: capsuleHeight
                )
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
        // 本方法只在 drawBackground 的调用链内执行——TextKit1 的背景绘制
        // 固定发生在主线程，读取 main-actor 隔离的 effectiveAppearance 安全；
        // 该前提无法让本编译器版本静态采信（assumeIsolated 会对捕获 self 报
        // sending 错误），经 KVC 读取，运行时语义与直接属性访问一致。
        let textView = textContainers.first?.textView
        guard let appearance = (textView as NSObject?)?.value(forKey: "effectiveAppearance") as? NSAppearance else {
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
    /// effectiveAppearance 变更回调（系统明暗切换）：PreviewWindowController 据此
    /// 对跟随系统外观的编辑器区（JSON/JSONL）即时重刷背景与全文基础前景。
    var onEffectiveAppearanceChanged: (() -> Void)?
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
        onDidDraw?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        onEffectiveAppearanceChanged?()
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
}
