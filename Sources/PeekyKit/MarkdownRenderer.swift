import AppKit
import Foundation

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
    private enum TableAlignment {
        case left
        case center
        case right
    }

    private struct MarkdownTable {
        let rows: [[String]]
        let alignments: [TableAlignment]
        let endIndex: Int
    }

    static func render(_ text: String) -> NSAttributedString {
        renderWithOutline(text).attributedText
    }

    static func renderWithOutline(_ text: String) -> MarkdownRenderResult {
        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)
        var outline: [MarkdownOutlineItem] = []
        var inCodeBlock = false
        var lineIndex = 0

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock.toggle()
                lineIndex += 1
                continue
            }

            if inCodeBlock {
                append(rawLine + "\n", to: output, attributes: codeBlockAttributes())
                lineIndex += 1
                continue
            }

            if trimmed.isEmpty {
                output.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
                lineIndex += 1
                continue
            }

            if let table = parseTable(in: lines, startingAt: lineIndex) {
                appendTable(table, to: output)
                lineIndex = table.endIndex
                continue
            }

            if let heading = parseHeading(rawLine) {
                outline.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: heading.text,
                        sourceLine: lineIndex + 1,
                        renderedLocation: output.length
                    )
                )
                append(heading.text + "\n", to: output, attributes: headingAttributes(level: heading.level))
                lineIndex += 1
                continue
            }

            if let quote = parseBlockQuote(rawLine) {
                append("|\u{00a0}", to: output, attributes: quoteMarkAttributes())
                appendInline(quote + "\n", to: output, attributes: quoteTextAttributes())
                lineIndex += 1
                continue
            }

            if let bullet = parseBullet(rawLine) {
                append("\u{2022} ", to: output, attributes: listAttributes())
                appendInline(bullet + "\n", to: output, attributes: listAttributes())
                lineIndex += 1
                continue
            }

            if let numbered = parseNumberedItem(rawLine) {
                append(numbered.prefix, to: output, attributes: listAttributes())
                appendInline(numbered.text + "\n", to: output, attributes: listAttributes())
                lineIndex += 1
                continue
            }

            appendInline(rawLine + "\n", to: output, attributes: bodyAttributes())
            lineIndex += 1
        }

        return MarkdownRenderResult(attributedText: output, outline: outline)
    }

    static func outline(in text: String) -> [MarkdownOutlineItem] {
        let lines = text.components(separatedBy: .newlines)
        var outline: [MarkdownOutlineItem] = []
        var inCodeBlock = false

        for (lineIndex, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                continue
            }

            if let heading = parseHeading(rawLine) {
                outline.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: heading.text,
                        sourceLine: lineIndex + 1,
                        renderedLocation: nil
                    )
                )
            }
        }

        return outline
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex

        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }

        guard level > 0, index < line.endIndex, line[index].isWhitespace else {
            return nil
        }

        let textStart = line.index(after: index)
        return (level, String(line[textStart...]).trimmingCharacters(in: .whitespaces))
    }

    private static func parseBlockQuote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func parseBullet(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    private static func parseNumberedItem(_ line: String) -> (prefix: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }
        let number = trimmed[..<dot]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let afterDot = trimmed.index(after: dot)
        guard afterDot < trimmed.endIndex, trimmed[afterDot].isWhitespace else { return nil }

        let textStart = trimmed.index(after: afterDot)
        return ("\(number). ", String(trimmed[textStart...]))
    }

    private static func parseTable(in lines: [String], startingAt startIndex: Int) -> MarkdownTable? {
        guard startIndex + 1 < lines.count else { return nil }

        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]
        guard containsTablePipe(headerLine) || containsTablePipe(separatorLine) else { return nil }

        let header = splitTableRow(headerLine)
        guard let alignments = parseTableSeparator(separatorLine),
              !header.isEmpty,
              header.count == alignments.count else {
            return nil
        }

        var rows = [normalizeTableRow(header, columnCount: alignments.count)]
        var lineIndex = startIndex + 2

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  containsTablePipe(line) else {
                break
            }

            let cells = splitTableRow(line)
            guard !cells.isEmpty else { break }

            rows.append(normalizeTableRow(cells, columnCount: alignments.count))
            lineIndex += 1
        }

        return MarkdownTable(rows: rows, alignments: alignments, endIndex: lineIndex)
    }

    private static func parseTableSeparator(_ line: String) -> [TableAlignment]? {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }

        var alignments: [TableAlignment] = []
        for cell in cells {
            let marker = cell.filter { !$0.isWhitespace }
            let startsWithColon = marker.first == ":"
            let endsWithColon = marker.last == ":"
            var hyphenMarker = marker
            if startsWithColon {
                hyphenMarker.removeFirst()
            }
            if endsWithColon {
                hyphenMarker.removeLast()
            }

            guard hyphenMarker.count >= 3,
                  hyphenMarker.allSatisfy({ $0 == "-" }) else {
                return nil
            }

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }

        return alignments
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var isEscaping = false
        var activeBacktickCount = 0
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if isEscaping {
                current.append(character)
                isEscaping = false
                index = line.index(after: index)
                continue
            }

            if character == "\\", activeBacktickCount == 0 {
                isEscaping = true
                index = line.index(after: index)
                continue
            }

            if character == "`" {
                let tickCount = consecutiveBacktickCount(in: line, startingAt: index)
                if activeBacktickCount == 0 {
                    activeBacktickCount = tickCount
                } else if activeBacktickCount == tickCount {
                    activeBacktickCount = 0
                }

                current.append(String(repeating: "`", count: tickCount))
                index = line.index(index, offsetBy: tickCount)
                continue
            }

            if character == "|", activeBacktickCount == 0 {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }

            index = line.index(after: index)
        }

        if isEscaping {
            current.append("\\")
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))

        if startsWithTableDelimiter(line), cells.first == "" {
            cells.removeFirst()
        }
        if endsWithTableDelimiter(line), cells.last == "" {
            cells.removeLast()
        }

        return cells
    }

    private static func normalizeTableRow(_ cells: [String], columnCount: Int) -> [String] {
        var normalized = Array(cells.prefix(columnCount))
        if normalized.count < columnCount {
            normalized.append(contentsOf: Array(repeating: "", count: columnCount - normalized.count))
        }
        return normalized
    }

    private static func containsTablePipe(_ line: String) -> Bool {
        var isEscaping = false
        var activeBacktickCount = 0
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if isEscaping {
                isEscaping = false
                index = line.index(after: index)
                continue
            }

            if character == "\\", activeBacktickCount == 0 {
                isEscaping = true
                index = line.index(after: index)
                continue
            }

            if character == "`" {
                let tickCount = consecutiveBacktickCount(in: line, startingAt: index)
                if activeBacktickCount == 0 {
                    activeBacktickCount = tickCount
                } else if activeBacktickCount == tickCount {
                    activeBacktickCount = 0
                }
                index = line.index(index, offsetBy: tickCount)
                continue
            }

            if character == "|", activeBacktickCount == 0 {
                return true
            }

            index = line.index(after: index)
        }

        return false
    }

    private static func startsWithTableDelimiter(_ line: String) -> Bool {
        guard let firstNonWhitespace = line.firstIndex(where: { !$0.isWhitespace }) else {
            return false
        }
        return line[firstNonWhitespace] == "|"
    }

    private static func endsWithTableDelimiter(_ line: String) -> Bool {
        guard let lastNonWhitespace = line.lastIndex(where: { !$0.isWhitespace }) else {
            return false
        }
        return line[lastNonWhitespace] == "|"
    }

    private static func consecutiveBacktickCount(in line: String, startingAt startIndex: String.Index) -> Int {
        var count = 0
        var index = startIndex
        while index < line.endIndex, line[index] == "`" {
            count += 1
            index = line.index(after: index)
        }
        return count
    }

    private static func appendTable(_ table: MarkdownTable, to output: NSMutableAttributedString) {
        let textTable = NSTextTable()
        textTable.numberOfColumns = table.alignments.count
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setContentWidth(100, type: .percentageValueType)
        textTable.setWidth(0, type: .absoluteValueType, for: .border)
        let columnWidthPercentages = tableColumnWidthPercentages(table)

        for rowIndex in table.rows.indices {
            let isHeader = rowIndex == 0
            let isLastRow = rowIndex == table.rows.index(before: table.rows.endIndex)
            let row = table.rows[rowIndex]

            for columnIndex in row.indices {
                let cellBlock = tableCellBlock(
                    table: textTable,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    widthPercentage: columnWidthPercentages[columnIndex],
                    isHeader: isHeader
                )
                let paragraph = tableParagraphStyle(
                    cellBlock: cellBlock,
                    alignment: table.alignments[columnIndex],
                    isFirstRow: isHeader,
                    isLastRow: isLastRow
                )
                let attributes = tableCellAttributes(isHeader: isHeader, paragraphStyle: paragraph)
                appendInline(row[columnIndex], to: output, attributes: attributes)
                append("\n", to: output, attributes: attributes)
            }
        }

        output.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
    }

    private static func tableColumnWidthPercentages(_ table: MarkdownTable) -> [CGFloat] {
        let columnCount = table.alignments.count
        guard columnCount > 0 else { return [] }

        var measuredWidths = Array(repeating: CGFloat(48), count: columnCount)
        for rowIndex in table.rows.indices {
            let font = rowIndex == 0 ? tableHeaderFont() : bodyFont()
            for columnIndex in table.rows[rowIndex].indices {
                let text = inlinePlainText(table.rows[rowIndex][columnIndex])
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

    private static func inlinePlainText(_ text: String) -> String {
        let output = NSMutableAttributedString()
        appendInline(text, to: output, attributes: bodyAttributes())
        return output.string
    }

    private static func appendInline(
        _ text: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        var index = text.startIndex
        var plainStart = index

        func flushPlain(upTo end: String.Index) {
            guard plainStart < end else { return }
            append(String(text[plainStart..<end]), to: output, attributes: attributes)
        }

        while index < text.endIndex {
            if text[index] == "`",
               let close = text[text.index(after: index)...].firstIndex(of: "`") {
                flushPlain(upTo: index)
                let start = text.index(after: index)
                append(String(text[start..<close]), to: output, attributes: inlineCodeAttributes(baseAttributes: attributes))
                index = text.index(after: close)
                plainStart = index
                continue
            }

            if text[index...].hasPrefix("**"),
               let close = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                flushPlain(upTo: index)
                let start = text.index(index, offsetBy: 2)
                var bold = attributes
                let baseFont = attributes[.font] as? NSFont ?? bodyFont()
                bold[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                append(String(text[start..<close.lowerBound]), to: output, attributes: bold)
                index = close.upperBound
                plainStart = index
                continue
            }

            if text[index] == "[",
               let closeBracket = text[index...].firstIndex(of: "]"),
               closeBracket < text.index(before: text.endIndex),
               text[text.index(after: closeBracket)] == "(",
               let closeParen = text[text.index(after: closeBracket)..<text.endIndex].firstIndex(of: ")") {
                let urlStart = text.index(closeBracket, offsetBy: 2)
                if urlStart < closeParen {
                    flushPlain(upTo: index)
                    let labelStart = text.index(after: index)
                    let label = String(text[labelStart..<closeBracket])
                    let url = String(text[urlStart..<closeParen])
                    var link = attributes
                    link[.foregroundColor] = NSColor.linkColor
                    link[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    link[.link] = url
                    append(label, to: output, attributes: link)
                    index = text.index(after: closeParen)
                    plainStart = index
                    continue
                }
            }

            index = text.index(after: index)
        }

        flushPlain(upTo: text.endIndex)
    }

    private static func append(
        _ text: String,
        to output: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        output.append(NSAttributedString(string: text, attributes: attributes))
    }

    private static func bodyFont() -> NSFont {
        NSFont.systemFont(ofSize: 14)
    }

    private static func tableHeaderFont() -> NSFont {
        NSFont.systemFont(ofSize: 14, weight: .semibold)
    }

    private static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 7

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func headingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = level <= 2 ? 12 : 8
        paragraph.paragraphSpacing = 6

        let size: CGFloat
        switch level {
        case 1: size = 28
        case 2: size = 22
        case 3: size = 18
        default: size = 15
        }

        return [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

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

    private static func tableHeaderBackgroundColor() -> NSColor {
        adaptiveColor(
            light: blendedColor(.controlBackgroundColor, with: .controlAccentColor, fraction: 0.18, for: .aqua),
            dark: blendedColor(.controlBackgroundColor, with: .controlAccentColor, fraction: 0.18, for: .darkAqua)
        )
    }

    private static func codeBlockAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 0

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: codeBlockBackgroundColor(),
            .paragraphStyle: paragraph
        ]
    }

    private static func inlineCodeAttributes(baseAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: inlineCodeForegroundColor(),
            .backgroundColor: inlineCodeBackgroundColor()
        ]

        if let paragraphStyle = baseAttributes[.paragraphStyle] {
            attributes[.paragraphStyle] = paragraphStyle
        }

        return attributes
    }

    private static func quoteMarkAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.systemBlue
        ]
    }

    private static func quoteTextAttributes() -> [NSAttributedString.Key: Any] {
        var attributes = bodyAttributes()
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
        return attributes
    }

    private static func listAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        paragraph.headIndent = 24

        return [
            .font: bodyFont(),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func tableCellBlock(
        table: NSTextTable,
        rowIndex: Int,
        columnIndex: Int,
        widthPercentage: CGFloat,
        isHeader: Bool
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
        block.backgroundColor = isHeader
            ? tableHeaderBackgroundColor()
            : NSColor.textBackgroundColor
        return block
    }

    private static func tableParagraphStyle(
        cellBlock: NSTextTableBlock,
        alignment: TableAlignment,
        isFirstRow: Bool,
        isLastRow: Bool
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacingBefore = isFirstRow ? 8 : 0
        paragraph.paragraphSpacing = isLastRow ? 8 : 0
        paragraph.textBlocks = [cellBlock]
        switch alignment {
        case .left:
            paragraph.alignment = .left
        case .center:
            paragraph.alignment = .center
        case .right:
            paragraph.alignment = .right
        }
        return paragraph
    }

    private static func tableCellAttributes(
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
