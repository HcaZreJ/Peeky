import PeekyCore

/// 文档的上色与交互方式。
package enum Presentation: Equatable, Sendable {
    /// 纯文本，不上色
    case plain
    /// shiki 高亮（Dark Modern 配色，整栏深色底）
    case source(language: String)
    /// XML / plist：标签、属性名、字符串着色
    case xml
    /// JSON：`structureIsValid` 为 true 时可建路径索引与折叠
    case json(structureIsValid: Bool)
    /// JSONL：逐条格式化
    case jsonLines
    /// Markdown：按终端宽度排版显示
    case markdown
}

extension Presentation {
    package var isJSON: Bool {
        switch self {
        case .json, .jsonLines: return true
        default: return false
        }
    }
}

/// 准备好要显示的文本：格式化后的文本、上色方式、标题行里的 note。
package struct PreparedText: Equatable, Sendable {
    package let text: String
    package let note: String
    package let presentation: Presentation
    /// 超过富格式化上限（非 JSON 降级为原文显示）；这类文件默认不换行。
    package let isLargeFile: Bool
    /// JSONL 里解析失败的记录所在的行（0 起算）。
    package let invalidLines: Set<Int>

    package init(text: String, note: String, presentation: Presentation, isLargeFile: Bool = false, invalidLines: Set<Int> = []) {
        self.text = text
        self.note = note
        self.presentation = presentation
        self.isLargeFile = isLargeFile
        self.invalidLines = invalidLines
    }
}

/// 纯函数：决定显示什么文本、怎么上色、标什么 note。规则与 app 的 `PreviewRenderer.render` 一致。
package enum DocumentPreparer {
    package static func prepare(_ document: LoadedText) -> PreparedText {
        if document.kind == .markdown {
            if document.readBytes > PreviewBudget.richFormatLimit {
                return PreparedText(text: document.text, note: "Raw preview for large file", presentation: .plain, isLargeFile: true)
            }
            return PreparedText(text: document.text, note: "Rendered", presentation: .markdown)
        }
        if !document.kind.hasFormattedPreview {
            return raw(document)
        }
        if document.readBytes > PreviewBudget.richFormatLimit, document.kind != .json, document.kind != .jsonl {
            let fallback = raw(document)
            return PreparedText(text: fallback.text, note: "Raw preview for large file", presentation: fallback.presentation, isLargeFile: true)
        }
        switch document.kind {
        case .json:
            if let pretty = try? JSONFormatter.prettyJSON(document.text) {
                return PreparedText(text: pretty, note: "Formatted", presentation: .json(structureIsValid: true))
            }
            return PreparedText(text: document.text, note: "Invalid JSON", presentation: .json(structureIsValid: false))
        case .jsonl:
            let result = JSONFormatter.prettyJSONLines(document.text)
            var notes = ["Formatted"]
            if result.invalidLineCount > 0 {
                notes.append("\(result.invalidLineCount) invalid line(s)")
            }
            return PreparedText(
                text: result.text,
                note: notes.joined(separator: ", "),
                presentation: .jsonLines,
                invalidLines: invalidLines(in: result)
            )
        case .xml:
            if let pretty = try? XMLFormatter.prettyXML(document.text) {
                return PreparedText(text: pretty, note: "Formatted", presentation: .xml)
            }
            return PreparedText(text: document.text, note: "Invalid XML", presentation: .xml)
        case .plist:
            if let pretty = try? XMLFormatter.prettyPropertyList(document.text) {
                return PreparedText(text: pretty, note: "Formatted", presentation: .xml)
            }
            return PreparedText(text: document.text, note: "Invalid plist", presentation: .plain)
        case .markdown, .yaml, .csv, .log, .text:
            return raw(document)
        }
    }

    /// 坏记录的起始位置（UTF-16）换算成行号。
    private static func invalidLines(in preview: JSONLinesPreview) -> Set<Int> {
        let starts = PreviewDisplayMetadata.lineStartLocations(in: preview.text)
        var lines: Set<Int> = []
        for record in preview.records where record.isInvalid {
            var low = 0
            var high = starts.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if starts[middle] <= record.range.location { low = middle } else { high = middle - 1 }
            }
            lines.insert(low)
        }
        return lines
    }

    private static func raw(_ document: LoadedText) -> PreparedText {
        let language = HighlightService.language(forExtension: document.url.pathExtension)
        let isLarge = document.readBytes > PreviewBudget.richFormatLimit
        switch document.kind {
        case .json:
            return PreparedText(
                text: document.text,
                note: "Raw",
                presentation: language.map { .source(language: $0) } ?? .plain,
                isLargeFile: isLarge
            )
        case .jsonl:
            return PreparedText(text: document.text, note: "Raw", presentation: .plain, isLargeFile: isLarge)
        case .xml, .plist:
            return PreparedText(text: document.text, note: "Raw", presentation: .xml, isLargeFile: isLarge)
        default:
            return PreparedText(
                text: document.text,
                note: "Raw",
                presentation: language.map { .source(language: $0) } ?? .plain,
                isLargeFile: isLarge
            )
        }
    }
}
