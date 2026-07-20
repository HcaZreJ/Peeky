import AppKit
import Foundation
import Markdown

struct MarkdownOutlineItem {
    let level: Int
    let title: String
    let sourceLine: Int
    let renderedLocation: Int?
}

struct MarkdownRenderResult {
    let attributedText: NSAttributedString
    let outline: [MarkdownOutlineItem]
}

enum MarkdownRenderer {
    /// Carries the fenced-code-block language (if any) on the corresponding
    /// attributed run, so a future syntax-highlighting pass can pick it up
    /// without re-parsing the Markdown source.
    static let codeLanguageAttributeKey = NSAttributedString.Key("peeky.codeLanguage")

    /// Marks every character run belonging to a fenced/indented/HTML code
    /// block's *block-level* content (never inline code) so a later UI layer
    /// can identify contiguous ranges that need line-fragment-wide block
    /// background fill instead of per-glyph background fill.
    static let codeBlockBackgroundAttributeKey = NSAttributedString.Key("peeky.codeBlockBackground")

    /// Marks every character run belonging to *inline* code (single-backtick
    /// spans, never a fenced/indented/HTML block) so a later UI layer can
    /// identify the exact glyph range that needs a tight capsule-shaped
    /// background fill, as opposed to the block-level line-fragment-wide
    /// fill driven by `codeBlockBackgroundAttributeKey`.
    static let inlineCodeBackgroundAttributeKey = NSAttributedString.Key("peeky.inlineCodeBackground")

    /// swift-markdown only attaches the `table`/`strikethrough`/`tasklist`
    /// cmark-gfm syntax extensions (see `CommonMarkConverter.swift`); GFM's
    /// bare-URL "autolink" extension is not wired up, so plain `Text` nodes
    /// keep literal "https://…" runs as-is. `NSDataDetector` (Foundation,
    /// no extra dependency) reliably finds http(s)/www/email spans — including
    /// correct trailing-punctuation trimming — so it stands in for that
    /// missing extension when a `Text` run is appended.
    fileprivate static let autolinkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func render(_ text: String) -> NSAttributedString {
        renderWithOutline(text).attributedText
    }

    static func renderWithOutline(_ text: String) -> MarkdownRenderResult {
        let document = Document(parsing: text, options: [.disableSmartOpts])
        let visitor = MarkdownAttributedVisitor()
        for child in document.children {
            visitor.visit(child)
        }
        return MarkdownRenderResult(attributedText: visitor.output, outline: visitor.outline)
    }

    static func outline(in text: String) -> [MarkdownOutlineItem] {
        let document = Document(parsing: text, options: [.disableSmartOpts])
        var items: [MarkdownOutlineItem] = []
        for child in document.children {
            collectOutline(child, into: &items)
        }
        return items
    }

    private static func collectOutline(_ markup: Markup, into items: inout [MarkdownOutlineItem]) {
        if let heading = markup as? Heading {
            if heading.level <= 4 {
                items.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: plainDisplayText(of: heading),
                        sourceLine: heading.range?.lowerBound.line ?? 0,
                        renderedLocation: nil
                    )
                )
            }
            return
        }

        for child in markup.children {
            collectOutline(child, into: &items)
        }
    }

    /// Recursively flattens an element's readable text content, discarding
    /// Markdown syntax markers (backticks, emphasis asterisks, link
    /// brackets/URLs) so headings/table cells read naturally in the outline
    /// sidebar and in column-width measurement.
    fileprivate static func plainDisplayText(of markup: Markup) -> String {
        if let text = markup as? Text {
            return text.string
        }
        if let inlineCode = markup as? InlineCode {
            return inlineCode.code
        }
        if markup is SoftBreak {
            return " "
        }
        if markup is LineBreak {
            return " "
        }
        if let html = markup as? InlineHTML {
            return html.rawHTML
        }

        var combined = ""
        for child in markup.children {
            combined += plainDisplayText(of: child)
        }
        return combined
    }

    // MARK: - Typography (GitHub Primer derived values)

    fileprivate static func append(
        _ text: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard !text.isEmpty else { return }
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    fileprivate static func bodyFont() -> NSFont {
        NSFont.systemFont(ofSize: 16)
    }

    fileprivate static func boldFont(size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .boldFontMask)
    }

    fileprivate static func boldFont(from font: NSFont?) -> NSFont {
        NSFontManager.shared.convert(font ?? bodyFont(), toHaveTrait: .boldFontMask)
    }

    fileprivate static func italicFont(from font: NSFont?) -> NSFont {
        NSFontManager.shared.convert(font ?? bodyFont(), toHaveTrait: .italicFontMask)
    }

    fileprivate static func bodyAttributes(indent: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        // TextKit has no margin-collapse: the visible gap between two blocks
        // is the sum of the preceding block's trailing `paragraphSpacing`
        // and this block's own `paragraphSpacingBefore`. Every block in this
        // file (headings excepted, see `headingAttributes`) keeps
        // `paragraphSpacingBefore = 0` so the gap between two consecutive
        // blocks is expressed exactly once (16pt), not doubled to 32pt.
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 16
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = indent

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    fileprivate static func headingFontSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 32
        case 2: return 24
        case 3: return 20
        default: return 16
        }
    }

    fileprivate static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.25
        // Every other block in this file keeps `paragraphSpacingBefore = 0`
        // so its visible top gap is expressed entirely by the preceding
        // block's trailing `paragraphSpacing` (see `bodyAttributes`).
        // Headings are the one exception that still carry a (smaller)
        // leading value of their own, so a heading directly after body text
        // reads with more space above it than below (16 body paragraphSpacing
        // + 8 heading paragraphSpacingBefore = 24pt above vs. 16pt heading
        // paragraphSpacing + 0 next-block paragraphSpacingBefore = 16pt
        // below), matching Primer's "group with what follows" heading
        // rhythm without reintroducing the double-counted 32pt gap a
        // symmetric 16/16 split would produce between two ordinary body
        // paragraphs.
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 16

        var attributes: [NSAttributedString.Key: Any] = [
            .font: boldFont(size: headingFontSize(level: level)),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        // h1/h2 GitHub 观感的底边线：文字级 underline（只沿标题字符本身的
        // glyph 宽度绘制，短标题下线会短于内容列宽，但不会导致 TextKit1 下
        // 独立 NSTextBlock 挂普通段落时的内容宽度塌缩/逐字竖排问题）。
        if level <= 2 {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = NSColor.separatorColor
        }

        return attributes
    }

    fileprivate static func quoteAttributes(depth: Int) -> [NSAttributedString.Key: Any] {
        let indent = CGFloat(max(depth, 1)) * 20
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 16
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = indent

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
    }

    /// 每级缩进 2em（32pt @ 16pt 字号）。marker 行的结构是
    /// `\t<marker>\t<内容>`：第一个 tab 把 marker 右缘对齐到文本起点左侧
    /// `markerGap` 处（数字位数不同也保持右对齐），第二个 tab 把首行内容
    /// 推到 `headIndent`，与换行后的续行严格同列。几何对标 GitHub 渲染
    /// （`ul/ol { padding-left: 2em }` + marker 悬挂在内容左侧）。
    fileprivate static let listIndentUnit: CGFloat = 32
    fileprivate static let listMarkerGap: CGFloat = 7

    fileprivate static func listAttributes(depth: Int) -> [NSAttributedString.Key: Any] {
        let textStart = listIndentUnit * CGFloat(depth + 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 4
        paragraph.headIndent = textStart
        paragraph.firstLineHeadIndent = listIndentUnit * CGFloat(depth)
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: textStart - listMarkerGap),
            NSTextTab(textAlignment: .left, location: textStart)
        ]

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    /// Fenced/indented/HTML code blocks are appended as a single multi-line
    /// run sharing one `NSParagraphStyle` with `paragraphSpacing = 0`: every
    /// embedded source line is its own NSString paragraph, so a nonzero
    /// spacing here would stack up a visible gap between *every* line of
    /// code. The block's own bottom margin is instead applied only to its
    /// last logical line (see `MarkdownAttributedVisitor.appendCodeBlockContent`),
    /// which gets a copy of this style with `paragraphSpacing` overridden to
    /// 16pt; the block's top margin comes from whichever non-code block
    /// precedes it, following this file's single-sided spacing model (only
    /// a block's trailing `paragraphSpacing` expresses the gap to what
    /// follows it; `paragraphSpacingBefore` is 0 everywhere except
    /// headings). Every character run produced here also carries
    /// `codeBlockBackgroundAttributeKey` so a later UI layer can render a
    /// contiguous block-level background instead of relying on this
    /// per-glyph `.backgroundColor`.
    fileprivate static func codeBlockAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.35
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        paragraph.headIndent = 12
        paragraph.firstLineHeadIndent = 12
        paragraph.tailIndent = -12

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: codeBlockBackgroundColor(),
            .paragraphStyle: paragraph,
            codeBlockBackgroundAttributeKey: true
        ]
    }

    /// A copy of a code block's shared paragraph style with `paragraphSpacing`
    /// overridden to 16pt, applied only to the block's last logical line so
    /// the block contributes its bottom margin without any interior line
    /// inheriting it.
    fileprivate static func codeBlockTrailingSpacingParagraphStyle(
        from attributes: [NSAttributedString.Key: Any]
    ) -> NSParagraphStyle {
        let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        style.paragraphSpacing = 16
        return style
    }

    fileprivate static func inlineCodeAttributes(baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular),
            .foregroundColor: inlineCodeForegroundColor(),
            .backgroundColor: inlineCodeBackgroundColor(),
            inlineCodeBackgroundAttributeKey: true
        ]

        if let paragraphStyle = baseAttributes[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }

        return attributes
    }

    fileprivate static func thematicBreakAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 16

        return [
            .font: NSFont.systemFont(ofSize: 1),
            .foregroundColor: NSColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.separatorColor,
            .paragraphStyle: paragraph
        ]
    }

    // MARK: - Colors

    /// 把两个 NSColor 在指定外观下各自解析为具体 sRGB 分量后再混合，避免
    /// `NSColor.blended(withFraction:of:)` 在无当前绘制外观上下文时按默认外观
    /// （通常是浅色）一次性烘焙出固定色，导致深色模式下仍显示浅色底。
    private static func resolvedColor(_ color: NSColor, for appearanceName: NSAppearance.Name) -> NSColor {
        var resolved = color
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func blendedColor(
        _ base: NSColor,
        with tint: NSColor,
        fraction: CGFloat,
        for appearanceName: NSAppearance.Name
    ) -> NSColor {
        let resolvedBase = resolvedColor(base, for: appearanceName)
        let resolvedTint = resolvedColor(tint, for: appearanceName)
        return resolvedBase.blended(withFraction: fraction, of: resolvedTint) ?? resolvedBase
    }

    /// 构造一个真正随外观切换重新取值的 NSColor：浅色/深色两个具体值在实际
    /// 绘制时按当前外观选取，而不是在构造属性字符串那一刻就被写死。
    private static func adaptiveColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func codeBlockBackgroundColor() -> NSColor {
        adaptiveColor(
            light: blendedColor(.textBackgroundColor, with: .systemBlue, fraction: 0.08, for: .aqua),
            dark: blendedColor(.textBackgroundColor, with: .systemBlue, fraction: 0.08, for: .darkAqua)
        )
    }

    private static func inlineCodeBackgroundColor() -> NSColor {
        adaptiveColor(
            light: blendedColor(.textBackgroundColor, with: .systemPink, fraction: 0.08, for: .aqua),
            dark: blendedColor(.textBackgroundColor, with: .systemPink, fraction: 0.08, for: .darkAqua)
        )
    }

    private static func inlineCodeForegroundColor() -> NSColor {
        let darkPink = resolvedColor(.systemPink, for: .darkAqua)
        return adaptiveColor(
            light: resolvedColor(.systemPink, for: .aqua),
            dark: darkPink.blended(withFraction: 0.25, of: .white) ?? darkPink
        )
    }

    fileprivate static func tableHeaderBackgroundColor() -> NSColor {
        adaptiveColor(
            light: blendedColor(.controlBackgroundColor, with: .controlAccentColor, fraction: 0.18, for: .aqua),
            dark: blendedColor(.controlBackgroundColor, with: .controlAccentColor, fraction: 0.18, for: .darkAqua)
        )
    }

    fileprivate static func tableZebraBackgroundColor() -> NSColor {
        adaptiveColor(
            light: blendedColor(.textBackgroundColor, with: .labelColor, fraction: 0.035, for: .aqua),
            dark: blendedColor(.textBackgroundColor, with: .labelColor, fraction: 0.035, for: .darkAqua)
        )
    }

    // MARK: - Tables

    fileprivate static func tableHeaderFont() -> NSFont {
        boldFont(size: bodyFont().pointSize)
    }

    fileprivate static func tableColumnWidthPercentages(rows: [[Table.Cell]], columnCount: Int) -> [CGFloat] {
        guard columnCount > 0 else { return [] }

        var measuredWidths = Array(repeating: CGFloat(48), count: columnCount)
        for (rowIndex, row) in rows.enumerated() {
            let font = rowIndex == 0 ? tableHeaderFont() : bodyFont()
            for (columnIndex, cell) in row.enumerated() where columnIndex < columnCount {
                let text = plainDisplayText(of: cell)
                let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
                measuredWidths[columnIndex] = max(measuredWidths[columnIndex], width)
            }
        }

        let totalWidth = measuredWidths.reduce(0, +)
        guard totalWidth > 0 else {
            return Array(repeating: 100 / CGFloat(columnCount), count: columnCount)
        }

        let rawPercentages = measuredWidths.map { $0 / totalWidth * 100 }
        let minimum = min(CGFloat(10), 75 / CGFloat(columnCount))
        let maximum = max(100 / CGFloat(columnCount), min(CGFloat(55), 100 - minimum * CGFloat(columnCount - 1)))
        let percentages = balancedPercentages(rawPercentages, minimum: minimum, maximum: maximum)
        return percentages.map { $0 * 0.92 }
    }

    private static func balancedPercentages(
        _ percentages: [CGFloat],
        minimum: CGFloat,
        maximum: CGFloat
    ) -> [CGFloat] {
        var balanced = percentages.map { min(max($0, minimum), maximum) }
        var delta = 100 - balanced.reduce(0, +)

        while abs(delta) > 0.01 {
            let adjustable = balanced.indices.filter { delta > 0 ? balanced[$0] < maximum : balanced[$0] > minimum }
            guard !adjustable.isEmpty else { break }

            let weights = adjustable.map { index in
                if delta > 0 {
                    max(percentages[index], 0.1)
                } else {
                    max(balanced[index] - percentages[index], 0.1)
                }
            }
            let totalWeight = weights.reduce(0, +)
            var applied = CGFloat(0)

            for (offset, index) in adjustable.enumerated() {
                let share = delta * weights[offset] / totalWeight
                let limit = delta > 0 ? maximum - balanced[index] : minimum - balanced[index]
                let change = delta > 0 ? min(share, limit) : max(share, limit)
                balanced[index] += change
                applied += change
            }

            guard abs(applied) > 0.001 else { break }
            delta -= applied
        }

        return balanced
    }

    fileprivate static func tableCellBlock(
        table: NSTextTable,
        rowIndex: Int,
        columnIndex: Int,
        widthPercentage: CGFloat,
        isHeader: Bool,
        isZebraStripe: Bool
    ) -> NSTextTableBlock {
        let block = NSTextTableBlock(
            table: table,
            startingRow: rowIndex,
            rowSpan: 1,
            startingColumn: columnIndex,
            columnSpan: 1
        )
        block.verticalAlignment = .topAlignment
        block.setContentWidth(widthPercentage, type: .percentageValueType)
        block.setWidth(8, type: .absoluteValueType, for: .padding)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(NSColor.separatorColor.withAlphaComponent(0.45))

        if isHeader {
            block.backgroundColor = tableHeaderBackgroundColor()
        } else if isZebraStripe {
            block.backgroundColor = tableZebraBackgroundColor()
        } else {
            block.backgroundColor = NSColor.textBackgroundColor
        }

        return block
    }

    fileprivate static func tableParagraphStyle(
        cellBlock: NSTextTableBlock,
        alignment: Table.ColumnAlignment,
        isFirstRow: Bool,
        isLastRow: Bool
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.4
        // The table's own top margin comes from the preceding block's
        // trailing `paragraphSpacing` (single-sided spacing model, see
        // `bodyAttributes`), so every row — including the header —
        // keeps `paragraphSpacingBefore = 0`. `isFirstRow` is retained
        // for call-site symmetry with `isLastRow`, which still drives the
        // table's own bottom margin below.
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = isLastRow ? 16 : 0
        paragraph.textBlocks = [cellBlock]

        switch alignment {
        case .left:
            paragraph.alignment = .left
        case .center:
            paragraph.alignment = .center
        case .right:
            paragraph.alignment = .right
        @unknown default:
            paragraph.alignment = .left
        }

        return paragraph
    }

    fileprivate static func tableCellAttributes(
        isHeader: Bool,
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: isHeader ? tableHeaderFont() : bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }
}

/// Single-pass `MarkupVisitor` that appends directly onto one shared
/// `NSMutableAttributedString` (no per-node intermediate attributed strings
/// are built and re-concatenated), so large documents stay within the 8MB
/// rich-formatting budget without repeated whole-document relayout.
private final class MarkdownAttributedVisitor: MarkupVisitor {
    typealias Result = Void

    let output = NSMutableAttributedString()
    private(set) var outline: [MarkdownOutlineItem] = []

    /// Inline formatting context (font/color/paragraph style) composes as we
    /// descend into nested inline markup (e.g. `**bold _italic_**`); each
    /// inline container pushes a derived copy and pops it back off once its
    /// children have been visited.
    private var attributeStack: [[NSAttributedString.Key: Any]] = []
    private var listContextStack: [ListRenderContext] = []
    private var quoteDepth = 0
    private var linkDepth = 0

    private struct ListRenderContext {
        let isOrdered: Bool
        var nextNumber: Int
    }

    private var currentAttributes: [NSAttributedString.Key: Any] {
        attributeStack.last ?? MarkdownRenderer.bodyAttributes()
    }

    // MARK: - Fallback

    /// `MarkupVisitor.visit(_:)`'s default protocol-extension implementation
    /// is declared `mutating`, which would force every call site (including
    /// internal recursive calls on `self`) to treat this reference type as
    /// if it needed `var`-style mutation. Overriding it directly as a plain
    /// instance method lets a `let`-bound visitor recurse through its own
    /// reference without fighting Swift's mutating-witness dispatch.
    func visit(_ markup: Markup) {
        var this = self
        markup.accept(&this)
    }

    func defaultVisit(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    // MARK: - Block elements

    func visitParagraph(_ paragraph: Paragraph) {
        let attributes = quoteDepth > 0
            ? MarkdownRenderer.quoteAttributes(depth: quoteDepth)
            : MarkdownRenderer.bodyAttributes()

        if quoteDepth > 0 {
            appendQuoteBarPrefix(with: attributes)
        }

        appendInlineChildren(paragraph, attributes: attributes)
        appendParagraphBreak(with: attributes)
    }

    func visitHeading(_ heading: Heading) {
        let attributes = MarkdownRenderer.headingAttributes(level: heading.level)
        let renderedLocation = output.length
        appendInlineChildren(heading, attributes: attributes)

        if heading.level <= 4 {
            outline.append(
                MarkdownOutlineItem(
                    level: heading.level,
                    title: MarkdownRenderer.plainDisplayText(of: heading),
                    sourceLine: heading.range?.lowerBound.line ?? 0,
                    renderedLocation: renderedLocation
                )
            )
        }

        appendParagraphBreak(with: attributes)
    }

    func visitBlockQuote(_ blockQuote: BlockQuote) {
        quoteDepth += 1
        for child in blockQuote.children {
            visit(child)
        }
        quoteDepth -= 1
    }

    func visitCodeBlock(_ codeBlock: CodeBlock) {
        var attributes = MarkdownRenderer.codeBlockAttributes()
        if let language = codeBlock.language, !language.isEmpty {
            attributes[MarkdownRenderer.codeLanguageAttributeKey] = language
        }

        appendCodeBlockContent(codeBlock.code, attributes: attributes)
    }

    func visitHTMLBlock(_ html: HTMLBlock) {
        let attributes = MarkdownRenderer.codeBlockAttributes()
        appendCodeBlockContent(html.rawHTML, attributes: attributes)
    }

    func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let attributes = MarkdownRenderer.thematicBreakAttributes()
        MarkdownRenderer.append("\u{00a0}", to: output, attributes: attributes)
        appendParagraphBreak(with: attributes)
    }

    func visitOrderedList(_ orderedList: OrderedList) {
        listContextStack.append(ListRenderContext(isOrdered: true, nextNumber: Int(orderedList.startIndex)))
        for item in orderedList.listItems {
            visitListItem(item)
        }
        listContextStack.removeLast()
    }

    func visitUnorderedList(_ unorderedList: UnorderedList) {
        listContextStack.append(ListRenderContext(isOrdered: false, nextNumber: 0))
        for item in unorderedList.listItems {
            visitListItem(item)
        }
        listContextStack.removeLast()
    }

    func visitListItem(_ listItem: ListItem) {
        guard let context = listContextStack.last else {
            defaultVisit(listItem)
            return
        }

        let depth = listContextStack.count - 1
        let attributes = MarkdownRenderer.listAttributes(depth: depth)

        var didAppendMarker = false
        for child in listItem.children {
            if !didAppendMarker {
                appendListMarker(for: listItem, isOrdered: context.isOrdered, depth: depth, attributes: attributes)
                didAppendMarker = true
            }

            if let paragraph = child as? Paragraph {
                appendInlineChildren(paragraph, attributes: attributes)
                appendParagraphBreak(with: attributes)
            } else {
                visit(child)
            }
        }

        if !didAppendMarker {
            appendListMarker(for: listItem, isOrdered: context.isOrdered, depth: depth, attributes: attributes)
            appendParagraphBreak(with: attributes)
        }
    }

    /// marker 行结构 `\t<marker>\t`（tab 语义见 `listAttributes`）。无序 marker
    /// 按层级用 ●/○/■（对标浏览器 disc/circle/square），缩小字号 + 基线上移
    /// 模拟 disc 的尺寸（约 5.6pt）与垂直居中，不撑高行；数字与 checkbox
    /// 保持正文字号。
    private func appendListMarker(
        for listItem: ListItem,
        isOrdered: Bool,
        depth: Int,
        attributes: [NSAttributedString.Key: Any]
    ) {
        var markerAttributes = attributes
        let marker: String
        if let checkbox = listItem.checkbox {
            marker = checkbox == .checked ? "\u{2611}" : "\u{2610}"
        } else if isOrdered, !listContextStack.isEmpty {
            let lastIndex = listContextStack.count - 1
            let number = listContextStack[lastIndex].nextNumber
            listContextStack[lastIndex].nextNumber += 1
            marker = "\(number)."
        } else {
            switch depth {
            case 0: marker = "\u{25CF}"
            case 1: marker = "\u{25CB}"
            default: marker = "\u{25A0}"
            }
            markerAttributes[.font] = NSFont.systemFont(ofSize: 8)
            markerAttributes[.baselineOffset] = 1.5
        }

        MarkdownRenderer.append("\t", to: output, attributes: attributes)
        MarkdownRenderer.append(marker, to: output, attributes: markerAttributes)
        MarkdownRenderer.append("\t", to: output, attributes: attributes)
    }

    func visitTable(_ table: Table) {
        let columnCount = table.maxColumnCount
        guard columnCount > 0 else { return }

        var rows: [[Table.Cell]] = [Array(table.head.cells)]
        for row in table.body.rows {
            rows.append(Array(row.cells))
        }

        let rawAlignments = table.columnAlignments
        let alignments: [Table.ColumnAlignment] = (0..<columnCount).map { index in
            index < rawAlignments.count ? (rawAlignments[index] ?? .left) : .left
        }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setContentWidth(100, type: .percentageValueType)
        textTable.setWidth(0, type: .absoluteValueType, for: .border)

        let columnWidthPercentages = MarkdownRenderer.tableColumnWidthPercentages(rows: rows, columnCount: columnCount)

        for (rowIndex, row) in rows.enumerated() {
            let isHeader = rowIndex == 0
            let isLastRow = rowIndex == rows.count - 1
            let isZebraStripe = !isHeader && rowIndex % 2 == 0

            for columnIndex in 0..<columnCount {
                let cellBlock = MarkdownRenderer.tableCellBlock(
                    table: textTable,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    widthPercentage: columnWidthPercentages[columnIndex],
                    isHeader: isHeader,
                    isZebraStripe: isZebraStripe
                )
                let paragraph = MarkdownRenderer.tableParagraphStyle(
                    cellBlock: cellBlock,
                    alignment: alignments[columnIndex],
                    isFirstRow: isHeader,
                    isLastRow: isLastRow
                )
                let attributes = MarkdownRenderer.tableCellAttributes(isHeader: isHeader, paragraphStyle: paragraph)

                if columnIndex < row.count {
                    appendInlineChildren(row[columnIndex], attributes: attributes)
                }
                MarkdownRenderer.append("\n", to: output, attributes: attributes)
            }
        }
    }

    // MARK: - Inline elements

    func visitText(_ text: Text) {
        guard linkDepth == 0 else {
            MarkdownRenderer.append(text.string, to: output, attributes: currentAttributes)
            return
        }
        appendAutolinkingText(text.string, attributes: currentAttributes)
    }

    func visitSoftBreak(_ softBreak: SoftBreak) {
        MarkdownRenderer.append(" ", to: output, attributes: currentAttributes)
    }

    func visitLineBreak(_ lineBreak: LineBreak) {
        MarkdownRenderer.append("\n", to: output, attributes: currentAttributes)
    }

    func visitInlineHTML(_ inlineHTML: InlineHTML) {
        MarkdownRenderer.append(inlineHTML.rawHTML, to: output, attributes: currentAttributes)
    }

    func visitInlineCode(_ inlineCode: InlineCode) {
        // 胶囊背景向字形外扩 4pt 内边距（CodeBlockBackgroundLayoutManager），
        // 会吃掉与相邻正文之间的自然字距；用胶囊外的 thin space 分隔符
        // （携带正文属性、不带 inline 标记）把胶囊与正文推开。
        MarkdownRenderer.append("\u{2009}", to: output, attributes: currentAttributes)
        MarkdownRenderer.append(
            inlineCode.code,
            to: output,
            attributes: MarkdownRenderer.inlineCodeAttributes(baseAttributes: currentAttributes)
        )
        MarkdownRenderer.append("\u{2009}", to: output, attributes: currentAttributes)
    }

    func visitEmphasis(_ emphasis: Emphasis) {
        pushDerivedAttributes { attributes in
            attributes[.font] = MarkdownRenderer.italicFont(from: attributes[.font] as? NSFont)
        }
        for child in emphasis.inlineChildren {
            visit(child)
        }
        popAttributes()
    }

    func visitStrong(_ strong: Strong) {
        pushDerivedAttributes { attributes in
            attributes[.font] = MarkdownRenderer.boldFont(from: attributes[.font] as? NSFont)
        }
        for child in strong.inlineChildren {
            visit(child)
        }
        popAttributes()
    }

    func visitStrikethrough(_ strikethrough: Strikethrough) {
        pushDerivedAttributes { attributes in
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        for child in strikethrough.inlineChildren {
            visit(child)
        }
        popAttributes()
    }

    func visitLink(_ link: Link) {
        guard let destination = link.destination, !destination.isEmpty else {
            for child in link.inlineChildren {
                visit(child)
            }
            return
        }

        pushDerivedAttributes { attributes in
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.link] = URL(string: destination) ?? destination
        }
        linkDepth += 1
        for child in link.inlineChildren {
            visit(child)
        }
        linkDepth -= 1
        popAttributes()
    }

    func visitImage(_ image: Image) {
        let altText = MarkdownRenderer.plainDisplayText(of: image)
        let label = altText.isEmpty ? (image.source ?? "image") : altText

        var attributes = currentAttributes
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
        MarkdownRenderer.append("[\(label)]", to: output, attributes: attributes)
    }

    // MARK: - Shared helpers

    private func appendInlineChildren<Container: InlineContainer>(
        _ container: Container,
        attributes: [NSAttributedString.Key: Any]
    ) {
        attributeStack.append(attributes)
        for child in container.inlineChildren {
            visit(child)
        }
        attributeStack.removeLast()
    }

    private func appendParagraphBreak(with attributes: [NSAttributedString.Key: Any]) {
        MarkdownRenderer.append("\n", to: output, attributes: attributes)
    }

    /// Appends a fenced/indented/HTML code block's raw content (which may
    /// span multiple lines, each its own NSString paragraph under the shared
    /// `paragraphSpacing = 0` style from `codeBlockAttributes()`) followed by
    /// the block's terminating paragraph break, then overrides the paragraph
    /// style on the block's *last logical line only* (the text after the
    /// final embedded newline, plus the terminating break that was just
    /// appended) with a copy whose `paragraphSpacing` is 16 — supplying the
    /// block's bottom margin without any interior code line inheriting it.
    /// A single-line block's one line is both first and last, so it still
    /// ends up with `paragraphSpacing = 16`. All other attributes on that
    /// range — including `codeBlockBackgroundAttributeKey` — are left
    /// untouched.
    private func appendCodeBlockContent(_ rawContent: String, attributes: [NSAttributedString.Key: Any]) {
        var content = rawContent
        if content.hasSuffix("\n") {
            content.removeLast()
        }

        let startLocation = output.length
        MarkdownRenderer.append(content, to: output, attributes: attributes)
        appendParagraphBreak(with: attributes)
        let endLocation = output.length

        guard endLocation > startLocation else { return }

        let nsContent = content as NSString
        let lastNewlineRange = nsContent.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: nsContent.length)
        )
        let lastLineStart = lastNewlineRange.location == NSNotFound
            ? startLocation
            : startLocation + lastNewlineRange.location + lastNewlineRange.length

        let lastLineRange = NSRange(location: lastLineStart, length: endLocation - lastLineStart)
        let trailingStyle = MarkdownRenderer.codeBlockTrailingSpacingParagraphStyle(from: attributes)
        output.addAttribute(.paragraphStyle, value: trailingStyle, range: lastLineRange)
    }

    /// 引用块左侧视觉标记：独立 `NSTextBlock` 挂在普通段落上会在 TextKit1 下把
    /// 内容宽度塌缩成单字符宽（逐字竖排），故改为在引用段正文前插入按嵌套
    /// 深度重复的 "▎ " 竖条字符，着 `tertiaryLabelColor`，与引用文字本身的
    /// `secondaryLabelColor` 前景色/`headIndent` 缩进语义并存、互不覆盖。
    private func appendQuoteBarPrefix(with attributes: [NSAttributedString.Key: Any]) {
        var barAttributes = attributes
        barAttributes[.foregroundColor] = NSColor.tertiaryLabelColor
        let prefix = String(repeating: "\u{258E} ", count: quoteDepth)
        MarkdownRenderer.append(prefix, to: output, attributes: barAttributes)
    }

    private func pushDerivedAttributes(_ mutate: (inout [NSAttributedString.Key: Any]) -> Void) {
        var attributes = currentAttributes
        mutate(&attributes)
        attributeStack.append(attributes)
    }

    private func popAttributes() {
        attributeStack.removeLast()
    }

    /// Splits a plain-text run on bare http(s)/www/email spans (GFM's
    /// autolink extension, which swift-markdown's parser doesn't attach) and
    /// gives each detected span the same `.link` + underline + link-color
    /// styling an explicit `[text](url)` link gets.
    private func appendAutolinkingText(_ string: String, attributes: [NSAttributedString.Key: Any]) {
        guard let detector = MarkdownRenderer.autolinkDetector, !string.isEmpty else {
            MarkdownRenderer.append(string, to: output, attributes: attributes)
            return
        }

        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = detector.matches(in: string, range: fullRange)

        guard !matches.isEmpty else {
            MarkdownRenderer.append(string, to: output, attributes: attributes)
            return
        }

        var cursor = 0
        for match in matches {
            guard match.range.location >= cursor, match.range.length > 0 else { continue }

            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                MarkdownRenderer.append(nsString.substring(with: plainRange), to: output, attributes: attributes)
            }

            let linkText = nsString.substring(with: match.range)
            var linkAttributes = attributes
            linkAttributes[.foregroundColor] = NSColor.linkColor
            linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let url = match.url {
                linkAttributes[.link] = url
            } else {
                linkAttributes[.link] = linkText
            }
            MarkdownRenderer.append(linkText, to: output, attributes: linkAttributes)

            cursor = match.range.location + match.range.length
        }

        if cursor < nsString.length {
            let remainderRange = NSRange(location: cursor, length: nsString.length - cursor)
            MarkdownRenderer.append(nsString.substring(with: remainderRange), to: output, attributes: attributes)
        }
    }
}
