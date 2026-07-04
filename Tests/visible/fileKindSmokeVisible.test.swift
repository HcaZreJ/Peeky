import Testing
import Foundation
@testable import PeekyKit

@Suite("Visible_fileKindSmoke")
struct Visible_fileKindSmoke {
    @Test("markdown extension detects as markdown")
    func markdownExtension() {
        let url = URL(fileURLWithPath: "/tmp/notes.md")
        #expect(FileKind.detect(url: url, text: "# Title") == .markdown)
    }

    @Test("json extension detects as json")
    func jsonExtension() {
        let url = URL(fileURLWithPath: "/tmp/data.json")
        #expect(FileKind.detect(url: url, text: "{\"a\": 1}") == .json)
    }

    @Test("no extension plain text detects as text")
    func noExtensionPlainText() {
        let url = URL(fileURLWithPath: "/tmp/README")
        #expect(FileKind.detect(url: url, text: "hello world") == .text)
    }
}
