import AppKit
import Foundation

enum PreviewMode: Int {
    case formatted = 0
    case raw = 1
}

struct RenderedPreview {
    let attributedText: NSAttributedString
    let note: String?
    let outline: [MarkdownOutlineItem]
    let display: PreviewDisplayMetadata

    init(
        attributedText: NSAttributedString,
        note: String?,
        outline: [MarkdownOutlineItem] = [],
        display: PreviewDisplayMetadata = .plain
    ) {
        self.attributedText = attributedText
        self.note = note
        self.outline = outline
        self.display = display
    }
}

enum PreviewRenderer {
    private static let richFormatLimit = 8 * 1024 * 1024

    static func render(
        document: LoadedText,
        mode: PreviewMode,
        collapseNestedJSON: Bool = false
    ) -> RenderedPreview {
        if mode == .raw || !document.kind.hasFormattedPreview {
            let raw = renderRaw(document)
            if document.kind == .markdown {
                return RenderedPreview(
                    attributedText: raw.attributedText,
                    note: raw.note,
                    outline: MarkdownRenderer.outline(in: document.text)
                )
            }
            return raw
        }

        if document.readBytes > richFormatLimit {
            let raw = renderRaw(document)
            let outline = document.kind == .markdown ? MarkdownRenderer.outline(in: document.text) : []
            return RenderedPreview(
                attributedText: raw.attributedText,
                note: "Raw preview for large file",
                outline: outline
            )
        }

        switch document.kind {
        case .markdown:
            let rendered = MarkdownRenderer.renderWithOutline(document.text)
            return RenderedPreview(
                attributedText: rendered.attributedText,
                note: nil,
                outline: rendered.outline
            )
        case .json:
            do {
                let pretty = try JSONFormatter.prettyJSON(document.text)
                let renderedText = collapseNestedJSON
                    ? JSONFormatter.collapsedNestedContainers(in: pretty)
                    : pretty
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightJSON(renderedText),
                    note: collapseNestedJSON ? "Formatted, folded" : "Formatted",
                    display: .lineNumbers(for: renderedText, showsIndentGuides: true)
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightJSON(document.text),
                    note: "Invalid JSON",
                    display: .lineNumbers(for: document.text, showsIndentGuides: true)
                )
            }
        case .jsonl:
            let result = JSONFormatter.prettyJSONLines(
                document.text,
                collapseNestedContainers: collapseNestedJSON
            )
            let attributed = NSMutableAttributedString(
                attributedString: SyntaxHighlighter.highlightJSON(result.text)
            )
            applyInvalidLineHighlighting(to: attributed, records: result.records)

            var notes = [collapseNestedJSON ? "Formatted, folded" : "Formatted"]
            if result.invalidLineCount > 0 {
                notes.append("\(result.invalidLineCount) invalid line(s)")
            }

            return RenderedPreview(
                attributedText: attributed,
                note: notes.joined(separator: ", "),
                display: .jsonLines(text: result.text, records: result.records)
            )
        case .xml:
            do {
                let pretty = try XMLFormatter.prettyXML(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(pretty),
                    note: "Formatted"
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(document.text),
                    note: "Invalid XML"
                )
            }
        case .plist:
            do {
                let pretty = try XMLFormatter.prettyPropertyList(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightXML(pretty),
                    note: "Formatted"
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.monospace(document.text),
                    note: "Invalid plist"
                )
            }
        case .yaml, .csv, .log, .text:
            return renderRaw(document)
        }
    }

    private static func renderRaw(_ document: LoadedText) -> RenderedPreview {
        switch document.kind {
        case .json, .jsonl:
            return RenderedPreview(
                attributedText: SyntaxHighlighter.highlightJSON(document.text),
                note: "Raw",
                display: .lineNumbers(for: document.text, showsIndentGuides: document.kind == .json)
            )
        case .xml, .plist:
            return RenderedPreview(attributedText: SyntaxHighlighter.highlightXML(document.text), note: "Raw")
        default:
            return RenderedPreview(attributedText: SyntaxHighlighter.monospace(document.text), note: "Raw")
        }
    }

    private static func applyInvalidLineHighlighting(
        to attributed: NSMutableAttributedString,
        records: [JSONLineRecord]
    ) {
        for record in records where record.isInvalid {
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor.systemRed.withAlphaComponent(0.13),
                range: record.range
            )
            attributed.addAttribute(
                .foregroundColor,
                value: NSColor.systemRed,
                range: record.range
            )
        }
    }
}
