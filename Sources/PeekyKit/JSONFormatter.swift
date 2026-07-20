import Foundation

struct JSONLineRecord {
    let originalLine: Int
    let range: NSRange
    let isInvalid: Bool
}

struct JSONLinesPreview {
    let text: String
    let invalidLineCount: Int
    let records: [JSONLineRecord]
}

enum JSONFormatter {
    static func prettyJSON(_ text: String) throws -> String {
        let object = try parseJSON(text)
        return try prettyJSONValue(object, fallback: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func prettyJSONLines(_ text: String) -> JSONLinesPreview {
        var invalidLineCount = 0
        var output = ""
        var records: [JSONLineRecord] = []
        var outputLength = 0
        var originalLine = 0

        text.enumerateLines { line, _ in
            originalLine += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let renderedLine: String
            let isInvalid: Bool

            do {
                let object = try parseJSON(trimmed)
                let pretty = try prettyJSONValue(object, fallback: trimmed)
                renderedLine = pretty
                isInvalid = false
            } catch {
                invalidLineCount += 1
                renderedLine = line
                isInvalid = true
            }

            if !output.isEmpty {
                output += "\n\n"
                outputLength += 2
            }

            let start = outputLength
            output += renderedLine
            outputLength += renderedLine.utf16.count

            records.append(
                JSONLineRecord(
                    originalLine: originalLine,
                    range: NSRange(location: start, length: renderedLine.utf16.count),
                    isInvalid: isInvalid
                )
            )
        }

        return JSONLinesPreview(text: output, invalidLineCount: invalidLineCount, records: records)
    }

    private static func parseJSON(_ text: String) throws -> Any {
        let data = Data(text.utf8)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func prettyJSONValue(_ object: Any, fallback: String) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            return fallback
        }

        let formattedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )

        return String(data: formattedData, encoding: .utf8) ?? fallback
    }
}
