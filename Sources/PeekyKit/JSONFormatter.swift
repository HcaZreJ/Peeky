import Foundation

struct JSONLineRecord {
    let originalLine: Int
    let range: NSRange
    let isInvalid: Bool
    let summary: String
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

    static func prettyJSONLines(
        _ text: String,
        collapseNestedContainers: Bool = false
    ) -> JSONLinesPreview {
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
            let summary: String

            do {
                let object = try parseJSON(trimmed)
                let pretty = try prettyJSONValue(object, fallback: trimmed)
                renderedLine = collapseNestedContainers
                    ? self.collapsedNestedContainers(in: pretty)
                    : pretty
                isInvalid = false
                summary = self.summary(for: object)
            } catch {
                invalidLineCount += 1
                renderedLine = line
                isInvalid = true
                summary = "invalid JSON"
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
                    isInvalid: isInvalid,
                    summary: summary
                )
            )
        }

        return JSONLinesPreview(text: output, invalidLineCount: invalidLineCount, records: records)
    }

    static func collapsedNestedContainers(in text: String, minimumDepth: Int = 1) -> String {
        let ranges = selectedFoldRanges(in: text, minimumDepth: minimumDepth)
        guard !ranges.isEmpty else { return text }

        let output = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.range.location > $1.range.location }) {
            output.replaceCharacters(in: range.range, with: range.placeholder)
        }

        return output as String
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

    private struct FoldRange {
        let range: NSRange
        let placeholder: String
    }

    private static func selectedFoldRanges(in text: String, minimumDepth: Int) -> [FoldRange] {
        let ranges = foldRanges(in: text, minimumDepth: minimumDepth)
            .sorted {
                if $0.range.location == $1.range.location {
                    $0.range.length > $1.range.length
                } else {
                    $0.range.location < $1.range.location
                }
            }

        var selected: [FoldRange] = []
        var selectedEnd = -1

        for range in ranges {
            guard range.range.location >= selectedEnd else { continue }
            selected.append(range)
            selectedEnd = NSMaxRange(range.range)
        }

        return selected
    }

    private static func foldRanges(in text: String, minimumDepth: Int) -> [FoldRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [FoldRange] = []
        var stack: [(character: unichar, location: Int, depth: Int)] = []
        var isInString = false
        var isEscaped = false

        for index in 0..<nsText.length {
            let character = nsText.character(at: index)

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == 92 {
                    isEscaped = true
                } else if character == 34 {
                    isInString = false
                }
                continue
            }

            if character == 34 {
                isInString = true
                continue
            }

            if character == 123 || character == 91 {
                stack.append((character: character, location: index, depth: stack.count))
                continue
            }

            if character == 125 || character == 93 {
                guard let opening = stack.last, matches(opening.character, character) else {
                    continue
                }
                stack.removeLast()

                let range = NSRange(location: opening.location, length: index - opening.location + 1)
                guard
                    opening.depth >= minimumDepth,
                    nsText.range(of: "\n", options: [], range: range).location != NSNotFound
                else {
                    continue
                }

                let placeholder = opening.character == 123 ? "{ ... }" : "[ ... ]"
                ranges.append(FoldRange(range: range, placeholder: placeholder))
            }
        }

        return ranges
    }

    private static func matches(_ opening: unichar, _ closing: unichar) -> Bool {
        (opening == 123 && closing == 125) || (opening == 91 && closing == 93)
    }

    private static func summary(for object: Any) -> String {
        if let dictionary = object as? [String: Any] {
            return dictionary.count == 1 ? "object - 1 key" : "object - \(dictionary.count) keys"
        }

        if let array = object as? [Any] {
            return array.count == 1 ? "array - 1 item" : "array - \(array.count) items"
        }

        if object is NSNull {
            return "null"
        }

        if let number = object as? NSNumber {
            return String(cString: number.objCType) == "c" ? "boolean" : "number"
        }

        if object is String {
            return "string"
        }

        return "value"
    }
}
