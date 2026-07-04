import Foundation

enum FileKind: Equatable {
    case markdown
    case json
    case jsonl
    case yaml
    case xml
    case plist
    case csv
    case log
    case text

    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .jsonl: "JSONL"
        case .yaml: "YAML"
        case .xml: "XML"
        case .plist: "Property List"
        case .csv: "CSV"
        case .log: "Log"
        case .text: "Text"
        }
    }

    var hasFormattedPreview: Bool {
        switch self {
        case .markdown, .json, .jsonl, .xml, .plist:
            true
        case .yaml, .csv, .log, .text:
            false
        }
    }

    static func detect(url: URL, text: String) -> FileKind {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        case "json":
            return .json
        case "jsonl", "ndjson":
            return .jsonl
        case "yaml", "yml":
            return .yaml
        case "xml":
            return .xml
        case "plist":
            return .plist
        case "csv", "tsv":
            return .csv
        case "log":
            return .log
        default:
            break
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }
        if trimmed.hasPrefix("<") {
            return .xml
        }
        return .text
    }
}
