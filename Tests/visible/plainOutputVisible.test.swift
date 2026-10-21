import Foundation
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 非终端输出可见样例
//
// 标准输出不是终端（`peek-tui x.md | cat`）时直接输出文字：Markdown 按 80 列排成纯文字
// （项目符号、表格边框照常显示），JSON / XML 输出格式化后的文本；不带任何转义序列，以换行结尾。

private func loaded(_ name: String, _ text: String) throws -> LoadedText {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("plain-output-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try text.write(to: url, atomically: true, encoding: .utf8)
    return try TextFileLoader.load(url: url)
}

@Suite("Visible_plainOutput")
struct Visible_plainOutput {
    @Test("Markdown 排成纯文字：保留项目符号，不带转义序列")
    func markdownAsPlainText() throws {
        let output = PlainOutput.text(for: try loaded("a.md", "# Title\n\n- first\n- second\n"))
        #expect(output.contains("Title"))
        #expect(output.contains("• first"))
        #expect(!output.contains("\u{1B}"))
        #expect(output.hasSuffix("\n"))
    }

    @Test("JSON 输出格式化后的文本")
    func jsonFormatted() throws {
        let output = PlainOutput.text(for: try loaded("a.json", "{\"a\":1}"))
        #expect(output == "{\n  \"a\" : 1\n}\n")
    }
}
