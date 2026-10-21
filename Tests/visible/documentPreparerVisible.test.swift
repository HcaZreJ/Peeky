import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - DocumentPreparer 可见样例
//
// 终端版决定「显示什么文本、怎么上色、标什么 note」的规则与 app 的 PreviewRenderer 一致：
// JSON / XML / plist 能格式化就格式化（失败时显示原文并标 Invalid …），超过 8 MB 的非 JSON
// 文件显示原文并标 Raw preview for large file，其余文本按扩展名决定 shiki 高亮语言。

private func loaded(_ text: String, name: String, kind: FileKind, readBytes: Int? = nil) -> LoadedText {
    LoadedText(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        kind: kind,
        text: text,
        totalBytes: Int64(readBytes ?? text.utf8.count),
        readBytes: readBytes ?? text.utf8.count,
        isTruncated: false,
        encodingName: "UTF-8"
    )
}

@Suite("Visible_documentPreparer")
struct Visible_documentPreparer {
    @Test("合法 JSON：格式化并标 Formatted")
    func validJSON() {
        let prepared = DocumentPreparer.prepare(loaded("{\"a\":1}", name: "x.json", kind: .json))
        #expect(prepared.text.contains("\"a\" : 1"))
        #expect(prepared.note == "Formatted")
        #expect(prepared.presentation == .json(structureIsValid: true))
    }

    @Test("非法 JSON：显示原文并标 Invalid JSON")
    func invalidJSON() {
        let prepared = DocumentPreparer.prepare(loaded("{\"a\":", name: "x.json", kind: .json))
        #expect(prepared.text == "{\"a\":")
        #expect(prepared.note == "Invalid JSON")
        #expect(prepared.presentation == .json(structureIsValid: false))
    }

    @Test("XML：格式化；非法时显示原文并标 Invalid XML")
    func xmlFormattingAndFailure() {
        let pretty = DocumentPreparer.prepare(loaded("<a><b>1</b></a>", name: "x.xml", kind: .xml))
        #expect(pretty.note == "Formatted")
        #expect(pretty.presentation == .xml)
        #expect(pretty.text.contains("\n"))
        let broken = DocumentPreparer.prepare(loaded("<a><b>", name: "x.xml", kind: .xml))
        #expect(broken.note == "Invalid XML")
        #expect(broken.text == "<a><b>")
    }

    @Test("非法 plist：显示原文、不上色，标 Invalid plist")
    func invalidPlist() {
        let prepared = DocumentPreparer.prepare(loaded("<plist><dict>", name: "x.plist", kind: .plist))
        #expect(prepared.note == "Invalid plist")
        #expect(prepared.presentation == .plain)
    }

    @Test("YAML 与源码按扩展名走 shiki 高亮，纯文本不上色", arguments: [
        ("config.yaml", FileKind.yaml, Presentation.source(language: "yaml")),
        ("main.swift", FileKind.text, Presentation.source(language: "swift")),
        ("notes.txt", FileKind.text, Presentation.plain),
    ] as [(String, FileKind, Presentation)])
    func rawTextLanguage(name: String, kind: FileKind, expected: Presentation) {
        let prepared = DocumentPreparer.prepare(loaded("a: 1", name: name, kind: kind))
        #expect(prepared.presentation == expected)
        #expect(prepared.note == "Raw")
    }

    @Test("超过 8 MB 的非 JSON 文件显示原文并标大文件；JSON 例外仍格式化")
    func largeFileBudget() {
        let big = DocumentPreparer.prepare(loaded("<a/>", name: "x.xml", kind: .xml, readBytes: PreviewBudget.richFormatLimit + 1))
        #expect(big.note == "Raw preview for large file")
        #expect(big.isLargeFile)
        let bigJSON = DocumentPreparer.prepare(loaded("[1]", name: "x.json", kind: .json, readBytes: PreviewBudget.richFormatLimit + 1))
        #expect(bigJSON.note == "Formatted")
    }
}
