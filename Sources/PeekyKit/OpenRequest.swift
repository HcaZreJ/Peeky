import Foundation

struct OpenRequest {
    let url: URL
    let line: Int?
    let column: Int?

    init(url: URL, line: Int? = nil, column: Int? = nil) {
        self.url = url.standardizedFileURL
        self.line = line
        self.column = column
    }

    static func fileURL(_ url: URL) -> OpenRequest? {
        guard url.isFileURL else { return nil }
        return OpenRequest(url: url)
    }

    static func commandLineArgument(_ argument: String) -> OpenRequest? {
        if let url = URL(string: argument),
           let scheme = url.scheme,
           !scheme.isEmpty,
           let request = incomingURL(url) {
            return request
        }

        let expandedPath = expandPath(argument)
        if FileManager.default.fileExists(atPath: expandedPath) {
            return OpenRequest(url: URL(fileURLWithPath: expandedPath))
        }

        if let parsed = parsePathLineSuffix(expandedPath),
           FileManager.default.fileExists(atPath: parsed.path) {
            return OpenRequest(
                url: URL(fileURLWithPath: parsed.path),
                line: parsed.line,
                column: parsed.column
            )
        }

        return nil
    }

    static func incomingURL(_ url: URL) -> OpenRequest? {
        if url.isFileURL {
            return fileURL(url)
        }

        guard url.scheme?.lowercased() == "peeky" else {
            return nil
        }

        return peekyURL(url)
    }

    private static func peekyURL(_ url: URL) -> OpenRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let line = positiveInt(queryItems.value(named: "line") ?? queryItems.value(named: "row"))
        let column = positiveInt(queryItems.value(named: "column") ?? queryItems.value(named: "col"))

        if let urlValue = queryItems.value(named: "url"),
           let fileURL = URL(string: urlValue),
           fileURL.isFileURL {
            return OpenRequest(url: fileURL, line: line, column: column)
        }

        if let pathValue = queryItems.value(named: "path") {
            let fileURL = fileURL(path: pathValue, cwd: queryItems.value(named: "cwd"))
            return OpenRequest(url: fileURL, line: line, column: column)
        }

        let path = components.path
        if !path.isEmpty, path != "/" {
            return OpenRequest(url: URL(fileURLWithPath: expandPath(path)), line: line, column: column)
        }

        return nil
    }

    private static func fileURL(path: String, cwd: String?) -> URL {
        let expandedPath = expandPath(path)
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        }

        if let cwd {
            let expandedCWD = expandPath(cwd)
            return URL(fileURLWithPath: expandedCWD).appendingPathComponent(expandedPath)
        }

        return URL(fileURLWithPath: expandedPath)
    }

    private static func expandPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private static func positiveInt(_ value: String?) -> Int? {
        guard let value, let number = Int(value), number > 0 else {
            return nil
        }
        return number
    }

    private static func parsePathLineSuffix(_ path: String) -> (path: String, line: Int, column: Int?)? {
        let pattern = #"^(.+):([1-9][0-9]*)(?::([1-9][0-9]*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsPath = path as NSString
        let fullRange = NSRange(location: 0, length: nsPath.length)
        guard let match = regex.firstMatch(in: path, range: fullRange),
              match.numberOfRanges >= 3 else {
            return nil
        }

        let filePath = nsPath.substring(with: match.range(at: 1))
        guard let line = Int(nsPath.substring(with: match.range(at: 2))) else {
            return nil
        }

        var column: Int?
        if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
            column = Int(nsPath.substring(with: match.range(at: 3)))
        }

        return (filePath, line, column)
    }
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}
