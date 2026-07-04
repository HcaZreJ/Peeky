import AppKit
import Foundation

enum SyntaxHighlighter {
    private static let highlightLimit = 1_500_000

    static func monospace(_ text: String) -> NSAttributedString {
        NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
    }

    static func highlightJSON(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
        guard text.utf16.count <= highlightLimit else {
            return attributed
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let stringRanges = applyStringHighlighting(to: attributed, nsText: nsText, fullRange: fullRange)

        applyRegex(
            pattern: #"(?<![\w.])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemPurple,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"\b(?:true|false)\b"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemOrange,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"\bnull\b"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .secondaryLabelColor,
            excludedRanges: stringRanges
        )
        applyRegex(
            pattern: #"[{}\[\],:]"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .tertiaryLabelColor,
            excludedRanges: []
        )

        return attributed
    }

    static func highlightXML(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseMonospaceAttributes())
        guard text.utf16.count <= highlightLimit else {
            return attributed
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        applyRegex(
            pattern: #"<!--[\s\S]*?-->"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .secondaryLabelColor,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"</?[\w:.-]+"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemBlue,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"[\w:.-]+(?=\=)"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemPurple,
            excludedRanges: []
        )
        applyRegex(
            pattern: #""(?:\\.|[^"\\])*""#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .systemGreen,
            excludedRanges: []
        )
        applyRegex(
            pattern: #"[<>/=]"#,
            to: attributed,
            nsText: nsText,
            fullRange: fullRange,
            color: .tertiaryLabelColor,
            excludedRanges: []
        )

        return attributed
    }

    private static func baseMonospaceAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func applyStringHighlighting(
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange
    ) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#) else {
            return []
        }

        let matches = regex.matches(in: nsText as String, range: fullRange)
        var stringRanges: [NSRange] = []

        for match in matches {
            stringRanges.append(match.range)
            let color: NSColor = isObjectKey(match.range, in: nsText) ? .systemBlue : .systemGreen
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }

        return stringRanges
    }

    private static func isObjectKey(_ range: NSRange, in text: NSString) -> Bool {
        var index = NSMaxRange(range)
        while index < text.length {
            let character = text.character(at: index)
            if character == 32 || character == 9 || character == 10 || character == 13 {
                index += 1
                continue
            }
            return character == 58
        }
        return false
    }

    private static func applyRegex(
        pattern: String,
        to attributed: NSMutableAttributedString,
        nsText: NSString,
        fullRange: NSRange,
        color: NSColor,
        excludedRanges: [NSRange]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: nsText as String, range: fullRange)

        for match in matches where !intersects(match.range, excludedRanges) {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }

    private static func intersects(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
