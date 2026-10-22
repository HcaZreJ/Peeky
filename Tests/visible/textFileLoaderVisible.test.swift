import Foundation
import Testing
@testable import PeekyCore

// MARK: - 读文件可见样例
//
// 文件在外部被改写后，界面拿同一个 URL 再读一次：读到的必须是磁盘上此刻的内容与大小。

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("text-file-loader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("Visible_textFileLoader")
struct Visible_textFileLoader {
    @Test("同一个 URL 读过一次后文件被改写，再读拿到新的内容与大小")
    func reloadSeesRewrittenSize() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a.py")
        try "print(1)\n".write(to: url, atomically: true, encoding: .utf8)
        _ = try TextFileLoader.load(url: url)

        let rewritten = "print('rewritten')\n"
        try rewritten.write(to: url, atomically: true, encoding: .utf8)
        let reloaded = try TextFileLoader.load(url: url)

        #expect(reloaded.text == rewritten)
        #expect(reloaded.totalBytes == Int64(rewritten.utf8.count))
    }

    @Test("目录不当作文件读，报「是目录」")
    func directoryIsRejected() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect {
            try TextFileLoader.load(url: directory)
        } throws: { error in
            guard case TextLoadError.directory = error else { return false }
            return true
        }
    }
}
