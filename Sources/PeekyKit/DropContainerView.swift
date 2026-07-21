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
        drawHeadingBottomRules(forGlyphRange: glyphsToShow, at: origin)
    }

    /// h1/h2 的 GitHub `border-bottom`：在标题文字下方的段间距留白处画一条整列宽
    /// 1px 细线（palette.headingRule），与文字拉开距离——对标 github-markdown-css
    /// h1/h2 的 padding-bottom + border-bottom，而非贴字形、仅字宽的 glyph 下划线。
    private func drawHeadingBottomRules(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard
            let storage = textStorage,
            let container = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil)
        else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let padding = container.lineFragmentPadding
        let ruleColor = resolvedBackgroundColor(MarkdownRenderer.GitHubMarkdownPalette.headingRule)

        storage.enumerateAttribute(MarkdownRenderer.headingBottomRuleAttributeKey, in: charRange) { value, range, _ in
            guard (value as? Bool) == true, range.length > 0 else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let lastGlyph = NSMaxRange(glyphRange) - 1
            let lineRect = self.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let ruleRect = NSRect(
                x: origin.x + padding,
                y: origin.y + lineRect.maxY + 6,
                width: max(container.size.width - padding * 2, 0),
                height: 1
            )
            ruleColor.setFill()
            ruleRect.fill()
        }
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

            // 累积整块的行片段并集，作为一块 6px 圆角矩形填充（对标 github 代码块
            // border-radius: 6px），而非逐行方角填充。
            var unionRect = NSRect.null
            var glyphIndex = glyphRange.location
            while glyphIndex < NSMaxRange(glyphRange) {
                var lineGlyphRange = NSRange()
                let lineRect = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
                unionRect = unionRect.union(lineRect)
                glyphIndex = NSMaxRange(lineGlyphRange)
            }
            if !unionRect.isNull {
                let blockRect = unionRect.offsetBy(dx: currentBackgroundOrigin.x, dy: currentBackgroundOrigin.y)
                NSBezierPath(roundedRect: blockRect, xRadius: 6, yRadius: 6).fill()
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

/// JSON 折叠态正文视图的注入面：缩进导轨深度表 + 双击选区扩展表 + 复制映射。
/// `DropTextView.foldOverlay` 为 nil 时（非 JSON 模式/未折叠）本文件既有行为
/// （拖放、record separators、markdown 代码块底色）完全不受影响。
struct FoldOverlayConfiguration {
    /// 每可见行的缩进深度（0-based 行号索引）。
    let lineDepths: [Int]
    /// 可见文本每行起点的 UTF-16 位置（与 lineDepths 等长）。
    let lineStartLocations: [Int]
    /// 一个缩进级（2 空格）的宽度，单位 pt（由控制器按正文 mono 字体算好传入）。
    let indentStepWidth: CGFloat
    /// 双击选区扩展表：proposedCharRange 与 trigger 相交（或为其内零长度光标）时，
    /// 双击选区扩展为 selection。全部为可见坐标。
    let selectionExpansions: [(trigger: NSRange, selection: NSRange)]
    /// 复制映射：入参当前选区（可见坐标），返回应写入剪贴板的完整底层源文本；
    /// 返回 nil 时走 NSTextView 默认复制。
    let copyTransform: (NSRange) -> String?
}

/// 折叠占位 chip 的 attachment cell：控制器把它挂在 U+FFFC 占位字符的 .attachment
/// 属性上，绘制圆角矩形底 + 描边 + 居中双向箭头字形，取色跟随 controlView 的
/// effectiveAppearance 即时响应明暗切换。
final class FoldChipAttachmentCell: NSTextAttachmentCell {
    private nonisolated static let size = NSSize(width: 26, height: 13)
    private static let glyph = "⟷"

    override func cellSize() -> NSSize {
        Self.size
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -3)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        Self.drawChip(in: cellFrame, appearance: PeekyTheme.resolveAppearance(controlView?.effectiveAppearance))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        Self.drawChip(in: cellFrame, appearance: PeekyTheme.resolveAppearance(controlView?.effectiveAppearance))
    }

    private static func drawChip(in cellFrame: NSRect, appearance: PeekyTheme.Appearance) {
        let background = PeekyTheme.color(.foldChipBackground, appearance: appearance)
        let border = PeekyTheme.color(.foldChipBorder, appearance: appearance)
        let glyphColor = PeekyTheme.color(.foldChipGlyph, appearance: appearance)

        let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        background.setFill()
        path.fill()
        path.lineWidth = 1
        border.setStroke()
        path.stroke()

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: glyphColor
        ]
        let size = glyph.size(withAttributes: attributes)
        let origin = NSPoint(
            x: cellFrame.midX - size.width / 2,
            y: cellFrame.midY - size.height / 2
        )
        glyph.draw(at: origin, withAttributes: attributes)
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
    /// JSON/JSONL 折叠态注入面：缩进导轨深度表 + 双击选区扩展表 + 复制映射。
    /// 无折叠上下文的模式（markdown/源码/纯文本）保持 nil，本类既有行为不受影响。
    var foldOverlay: FoldOverlayConfiguration? {
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

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let foldOverlay else { return }
        drawIndentGuides(using: foldOverlay)
    }

    override func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        guard granularity == .selectByWord, let foldOverlay else {
            return super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        }

        var bestSelection: NSRange?
        for expansion in foldOverlay.selectionExpansions {
            let intersects: Bool
            if proposedCharRange.length == 0 {
                intersects = NSLocationInRange(proposedCharRange.location, expansion.trigger)
            } else {
                intersects = NSIntersectionRange(proposedCharRange, expansion.trigger).length > 0
            }
            guard intersects else { continue }
            if let current = bestSelection, expansion.selection.length <= current.length {
                continue
            }
            bestSelection = expansion.selection
        }

        return bestSelection ?? super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
    }

    override func copy(_ sender: Any?) {
        guard
            let foldOverlay,
            selectedRange().length > 0,
            let text = foldOverlay.copyTransform(selectedRange())
        else {
            super.copy(sender)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 缩进导轨：可见区每个视觉行片段按其逻辑行深度画竖直虚线（d ≤ 1 零导轨），
    /// 折行产生的后续视觉行片段沿用同一逻辑行深度——characterRange.location 二分
    /// 落在同一 lineStartLocations 区间，天然继承。画在文字后面（drawBackground）。
    private func drawIndentGuides(using foldOverlay: FoldOverlayConfiguration) {
        guard let layoutManager, let textContainer else { return }

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: visibleRect,
            in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }

        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([2, 2], count: 2, phase: 0)

        let originX = textContainerOrigin.x + textContainer.lineFragmentPadding
        let originY = textContainerOrigin.y
        var hasSegments = false

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { lineRect, _, _, lineGlyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            guard
                let visualLine = Self.visibleLineIndex(for: charRange.location, in: foldOverlay.lineStartLocations)
            else { return }
            let depth = visualLine < foldOverlay.lineDepths.count ? foldOverlay.lineDepths[visualLine] : 0
            guard depth > 1 else { return }

            let top = lineRect.minY + originY
            let bottom = lineRect.maxY + originY

            for k in 1..<depth {
                let x = originX + foldOverlay.indentStepWidth * CGFloat(k)
                path.move(to: NSPoint(x: x, y: top))
                path.line(to: NSPoint(x: x, y: bottom))
                hasSegments = true
            }
        }

        guard hasSegments else { return }
        let appearance = PeekyTheme.resolveAppearance(effectiveAppearance)
        PeekyTheme.color(.indentGuide, appearance: appearance).setStroke()
        path.stroke()
    }

    /// 二分出 location 所属的可见行号：最后一个 lineStartLocations[v] <= location 的 v。
    /// 折行续行的 characterRange.location 落在同一区间内，天然复用其逻辑行的行号。
    private static func visibleLineIndex(for location: Int, in lineStartLocations: [Int]) -> Int? {
        guard !lineStartLocations.isEmpty else { return nil }

        var low = 0
        var high = lineStartLocations.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if lineStartLocations[mid] <= location {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return match
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
