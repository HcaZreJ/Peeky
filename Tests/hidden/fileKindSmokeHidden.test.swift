import Testing
import Foundation
@testable import PeekyKit

@Suite("Hidden_fileKindSmoke")
struct Hidden_fileKindSmoke {
    @Test("jsonl extension detects as jsonl")
    func jsonlExtension() {
        let url = URL(fileURLWithPath: "/tmp/records.jsonl")
        #expect(FileKind.detect(url: url, text: "{\"a\": 1}\n{\"a\": 2}") == .jsonl)
    }

    @Test("xml extension detects as xml")
    func xmlExtension() {
        let url = URL(fileURLWithPath: "/tmp/data.xml")
        #expect(FileKind.detect(url: url, text: "<root></root>") == .xml)
    }
}
