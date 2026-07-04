import Foundation

struct LoadedText {
    let url: URL
    let kind: FileKind
    let text: String
    let totalBytes: Int64
    let readBytes: Int
    let isTruncated: Bool
    let encodingName: String
}

enum TextLoadError: LocalizedError {
    case directory(URL)
    case unreadableEncoding(URL)

    var errorDescription: String? {
        switch self {
        case .directory(let url):
            return "\(url.lastPathComponent) is a directory."
        case .unreadableEncoding(let url):
            return "\(url.lastPathComponent) is not a readable text file."
        }
    }
}

enum TextFileLoader {
    private static let maxPreviewBytes = 80 * 1024 * 1024

    static func load(url: URL) throws -> LoadedText {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values.isDirectory == true {
            throw TextLoadError.directory(url)
        }

        let totalBytes = Int64(values.fileSize ?? 0)
        let data: Data
        let isTruncated: Bool

        if totalBytes > maxPreviewBytes {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxPreviewBytes) ?? Data()
            isTruncated = true
        } else {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
            isTruncated = false
        }

        guard let decoded = decode(data: data) else {
            throw TextLoadError.unreadableEncoding(url)
        }

        let text = stripByteOrderMark(from: decoded.text)
        let kind = FileKind.detect(url: url, text: text)

        return LoadedText(
            url: url,
            kind: kind,
            text: text,
            totalBytes: totalBytes,
            readBytes: data.count,
            isTruncated: isTruncated,
            encodingName: decoded.encodingName
        )
    }

    private static func decode(data: Data) -> (text: String, encodingName: String)? {
        let encodings: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"),
            (.isoLatin1, "ISO Latin 1"),
            (.ascii, "ASCII")
        ]

        for (encoding, name) in encodings {
            if let text = String(data: data, encoding: encoding) {
                return (text, name)
            }
        }

        return nil
    }

    private static func stripByteOrderMark(from text: String) -> String {
        guard text.first == "\u{feff}" else { return text }
        return String(text.dropFirst())
    }
}
