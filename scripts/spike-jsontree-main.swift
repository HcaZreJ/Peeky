import Foundation

@main
struct SpikeMain {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            FileHandle.standardError.write("usage: spike-jsontree-main <path-to-json>\n".data(using: .utf8)!)
            exit(1)
        }

        let path = arguments[1]
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write("failed to decode file as UTF-8\n".data(using: .utf8)!)
            exit(1)
        }

        print("file size: \(data.count) bytes (\(Double(data.count) / 1024 / 1024) MB)")

        let clock = ContinuousClock()
        let start = clock.now
        let index = JSONTreeIndex.build(text: text, kind: .json)
        let elapsed = clock.now - start

        print("build elapsed: \(elapsed)")
        print("node count: \(index.nodes.count)")
        print("root count: \(index.rootIndices.count)")
        print("errorIndex is nil: \(index.errorIndex == nil)")
    }
}
