import AppKit
import Foundation

enum PreviewMode: Int {
    case formatted = 0
    case raw = 1
}

/// 源码类文件 / JSON 原文模式命中 `HighlightService` 高亮范围时，编辑器区固定使用的
/// VSCode Dark Modern 配色；未命中范围的类型（markdown/xml/csv/log/纯文本/jsonl）
/// 保持既有动态外观不变。
enum DarkModernTheme {
    static let background = NSColor(srgbRed: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1)
    static let foreground = NSColor(srgbRed: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255, alpha: 1)
    static let gutterLineNumber = NSColor(srgbRed: 0x6E / 255, green: 0x76 / 255, blue: 0x81 / 255, alpha: 1)
    static let gutterSeparator = gutterLineNumber.withAlphaComponent(0.35)
}

struct RenderedPreview {
    let attributedText: NSAttributedString
    let note: String?
    let outline: [MarkdownOutlineItem]
    let display: PreviewDisplayMetadata
    /// 非 nil = 命中 HighlightService 高亮接入范围（shiki language id）；PreviewWindowController
    /// 据此起 highlightStream 分块上色，并统一编辑器区为 Dark Modern 配色。
    let highlightLanguage: String?
    /// true = 由 PreviewWindowController 用 `JSONHighlighter` 对可见区做惰性语义上色（JSON/JSONL）。
    let usesJSONHighlighting: Bool
    /// true = 编辑器区背景/前景/token 走 `PeekyTheme` 跟随系统 light/dark 外观。
    let followsSystemAppearance: Bool

    init(
        attributedText: NSAttributedString,
        note: String?,
        outline: [MarkdownOutlineItem] = [],
        display: PreviewDisplayMetadata = .plain,
        highlightLanguage: String? = nil,
        usesJSONHighlighting: Bool = false,
        followsSystemAppearance: Bool = false
    ) {
        self.attributedText = attributedText
        self.note = note
        self.outline = outline
        self.display = display
        self.highlightLanguage = highlightLanguage
        self.usesJSONHighlighting = usesJSONHighlighting
        self.followsSystemAppearance = followsSystemAppearance
    }

    var usesDarkModernTheme: Bool { highlightLanguage != nil }
}

enum PreviewRenderer {
    private static let richFormatLimit = 8 * 1024 * 1024

    static func render(
        document: LoadedText,
        mode: PreviewMode
    ) -> RenderedPreview {
        if document.kind != .markdown && (mode == .raw || !document.kind.hasFormattedPreview) {
            return renderRaw(document)
        }

        if document.readBytes > richFormatLimit && document.kind != .json && document.kind != .jsonl {
            let raw = renderRaw(document)
            let outline = document.kind == .markdown ? MarkdownRenderer.outline(in: document.text) : []
            return RenderedPreview(
                attributedText: raw.attributedText,
                note: "Raw preview for large file",
                outline: outline,
                highlightLanguage: raw.highlightLanguage
            )
        }

        switch document.kind {
        case .json:
            do {
                let pretty = try JSONFormatter.prettyJSON(document.text)
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.monospace(pretty),
                    note: "Formatted",
                    display: .lineNumbers(for: pretty),
                    usesJSONHighlighting: true,
                    followsSystemAppearance: true
                )
            } catch {
                return RenderedPreview(
                    attributedText: SyntaxHighlighter.monospace(document.text),
                    note: "Invalid JSON",
                    display: .lineNumbers(for: document.text),
                    usesJSONHighlighting: true,
                    followsSystemAppearance: true
                )
            }
        case .jsonl:
            let result = JSONFormatter.prettyJSONLines(document.text)

            var notes = ["Formatted"]
            if result.invalidLineCount > 0 {
                notes.append("\(result.invalidLineCount) invalid line(s)")
            }

            return RenderedPreview(
                attributedText: SyntaxHighlighter.monospace(result.text),
                note: notes.joined(separator: ", "),
                display: .jsonLines(text: result.text, records: result.records),
                usesJSONHighlighting: true,
                followsSystemAppearance: true
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
        case .markdown, .yaml, .csv, .log, .text:
            return renderRaw(document)
        }
    }

    private static func renderRaw(_ document: LoadedText) -> RenderedPreview {
        let extensionLanguage = HighlightService.language(forExtension: document.url.pathExtension)

        switch document.kind {
        case .json, .jsonl:
            // 仅 JSON 的原文模式命中高亮接入范围；JSONL 原文保留既有记录标记/坏行管线，不接。
            let language = document.kind == .json ? extensionLanguage : nil
            return RenderedPreview(
                attributedText: rawAttributedText(document.text, language: language) {
                    SyntaxHighlighter.highlightJSON(document.text)
                },
                note: "Raw",
                display: .lineNumbers(for: document.text),
                highlightLanguage: language
            )
        case .xml, .plist:
            return RenderedPreview(attributedText: SyntaxHighlighter.highlightXML(document.text), note: "Raw")
        default:
            return RenderedPreview(
                attributedText: rawAttributedText(document.text, language: extensionLanguage) {
                    SyntaxHighlighter.monospace(document.text)
                },
                note: "Raw",
                highlightLanguage: extensionLanguage
            )
        }
    }

    /// 命中高亮接入范围（language 非 nil）时先铺 Dark Modern 基色纯文本——token 分块到达后由
    /// PreviewWindowController 原位 addAttribute 覆盖前景色，绝不整文重设 attributedString；
    /// 未命中范围时走既有 fallback（现状高亮/monospace）。
    private static func rawAttributedText(
        _ text: String,
        language: String?,
        fallback: () -> NSAttributedString
    ) -> NSAttributedString {
        guard language != nil else { return fallback() }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: DarkModernTheme.foreground,
            .paragraphStyle: paragraph
        ])
    }
}
