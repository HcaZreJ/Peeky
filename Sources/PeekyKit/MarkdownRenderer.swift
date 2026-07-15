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
        paragraph.paragraphSpacingBefore = 16
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
        // Primer's markdown-body headings carry more space above than below
        // (24pt vs 16pt) to visually group each heading with the content
        // that follows it rather than the content above.
        paragraph.paragraphSpacingBefore = 24
        paragraph.paragraphSpacing = 16

        if level <= 2 {
            paragraph.textBlocks = [headingDividerBlock()]
        }

        return [
            .font: boldFont(size: headingFontSize(level: level)),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    /// h1/h2 GitHub 观感的全宽底边线：挂在段落的 `NSTextBlock` 底（`.minY`）
    /// border 上，而不是文字级 underline——文字级 underline 只沿标题字符本身的
    /// glyph 宽度绘制，短标题下线会明显短于内容列宽；`NSTextBlock` 未绑定
    /// `NSTextTable` 时按整个可用文本宽度布局，边框天然铺满内容列。
    private static func headingDividerBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
        block.setBorderColor(NSColor.separatorColor, for: .minY)
        block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minY)
        return block
    }

    fileprivate static func quoteAttributes(depth: Int) -> [NSAttributedString.Key: Any] {
        let indent = CGFloat(max(depth, 1)) * 20
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.paragraphSpacingBefore = 16
        paragraph.paragraphSpacing = 16
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = indent
        paragraph.textBlocks = [quoteBarBlock()]

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
    }

    /// 引用块左侧色条：挂在段落的 `NSTextBlock` 左（`.minX`）border 上，色用
    /// 次级色系（`secondaryLabelColor` 半透明），与引用文字既有的
    /// `secondaryLabelColor` 前景色/`headIndent` 缩进语义并存，互不覆盖。
    private static func quoteBarBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(3.5, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(NSColor.secondaryLabelColor.withAlphaComponent(0.5), for: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
        return block
    }

    fileprivate static func listAttributes(depth: Int) -> [NSAttributedString.Key: Any] {
        let unit: CGFloat = 24
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4
        paragraph.headIndent = unit * CGFloat(depth + 1)
        paragraph.firstLineHeadIndent = unit * CGFloat(depth)

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    /// Fenced/indented code blocks are appended as a single multi-line run
    /// sharing one `NSParagraphStyle`. Any nonzero `paragraphSpacing`/
    /// `paragraphSpacingBefore` here would apply to *every* embedded source
    /// line (each one is its own NSString paragraph), stacking up visible
    /// gaps between every line of code. Vertical breathing room around the
    /// block is instead delegated to the neighboring blocks' own
    /// `paragraphSpacingBefore`/`paragraphSpacing` (body/heading/list/quote
    /// all carry a nonzero value on both sides), so the gap is always
    /// supplied by whichever adjacent block isn't a code block.
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
            .paragraphStyle: paragraph
        ]
    }

    fileprivate static func inlineCodeAttributes(baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13.6, weight: .regular),
            .foregroundColor: inlineCodeForegroundColor(),
            .backgroundColor: inlineCodeBackgroundColor()
        ]

        if let paragraphStyle = baseAttributes[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }

        return attributes
    }

    fileprivate static func thematicBreakAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 16
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
        paragraph.paragraphSpacingBefore = isFirstRow ? 16 : 0
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

        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }

        MarkdownRenderer.append(code, to: output, attributes: attributes)
        appendParagraphBreak(with: attributes)
    }

    func visitHTMLBlock(_ html: HTMLBlock) {
        let attributes = MarkdownRenderer.codeBlockAttributes()
        MarkdownRenderer.append(html.rawHTML, to: output, attributes: attributes)
        appendParagraphBreak(with: attributes)
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
        let marker = listMarkerText(for: listItem, isOrdered: context.isOrdered)
        let attributes = MarkdownRenderer.listAttributes(depth: depth)

        var didAppendMarker = false
        for child in listItem.children {
            if !didAppendMarker {
                MarkdownRenderer.append(marker, to: output, attributes: attributes)
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
            MarkdownRenderer.append(marker, to: output, attributes: attributes)
            appendParagraphBreak(with: attributes)
        }
    }

    private func listMarkerText(for listItem: ListItem, isOrdered: Bool) -> String {
        if let checkbox = listItem.checkbox {
            return checkbox == .checked ? "\u{2611} " : "\u{2610} "
        }

        if isOrdered, !listContextStack.isEmpty {
            let lastIndex = listContextStack.count - 1
            let number = listContextStack[lastIndex].nextNumber
            listContextStack[lastIndex].nextNumber += 1
            return "\(number). "
        }

        return "\u{2022} "
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
        MarkdownRenderer.append(
            inlineCode.code,
            to: output,
            attributes: MarkdownRenderer.inlineCodeAttributes(baseAttributes: currentAttributes)
        )
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
