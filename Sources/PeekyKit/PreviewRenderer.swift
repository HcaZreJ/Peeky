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
                    // macOS 26 Tahoe 起，NSScrollView 显示 vertical ruler 会用 clipView.bounds
                    // 负偏移代替老式 frame-shift 给 ruler 让位；这个新几何与 NSTextView 的 draw
                    // pipeline 撞车，导致 gutter 显示但正文完全不 draw（layout 完成、⌘A⌘C 能
                    // 拷全文、resize 无救）。改用 .plain 暂降级到无行号 gutter 换文本可见；
                    // 长期方案是把 PreviewGutterView 从 NSRulerView 换成加到 contentView 里的
                    // 独立 subview，绕开 NSRulerView 内部 clipView.bounds 机制。
                    display: .plain
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.highlightJSON(document.text),
                    note: "Invalid JSON",
                    display: .plain
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
                // 同 .json：JSONL 的 gutter markers + record annotations 也走 NSRulerView，
                // 会被 macOS 26 clipView.bounds 新几何搞成 blank；本波先关掉 gutter 保证
                // 记录本身可见（record separators / indent guides 是 overlay 不受影响）。
                display: PreviewDisplayMetadata(
                    gutter: .hidden,
                    textOverlay: PreviewTextOverlayConfiguration(
                        showsIndentGuides: true,
                        recordSeparatorLocations: result.records.dropFirst().map { $0.range.location },
                        recordAnnotations: result.records.map {
                            PreviewRecordAnnotation(
                                characterLocation: $0.range.location,
                                text: $0.summary,
                                isWarning: $0.isInvalid
                            )
                        }
                    ),
                    targetLocationsByOriginalLine: Dictionary(uniqueKeysWithValues: result.records.map {
                        ($0.originalLine, $0.range.location)
                    })
                )
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
            // 同 formatted 路径的 stopgap：macOS 26 起 NSRulerView 导致内容 blank，本波
            // 全 kind 关掉 gutter 换文本可见（indent guides 与 record separators 是 overlay
            // 不走 ruler，保留）。
            return RenderedPreview(
                attributedText: SyntaxHighlighter.highlightJSON(document.text),
                note: "Raw",
                display: PreviewDisplayMetadata(
                    gutter: .hidden,
                    textOverlay: PreviewTextOverlayConfiguration(
                        showsIndentGuides: document.kind == .json,
                        recordSeparatorLocations: [],
                        recordAnnotations: []
                    ),
                    targetLocationsByOriginalLine: [:]
                )
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
