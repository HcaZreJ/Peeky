import Testing
import Foundation
@testable import PeekyMermaid
@testable import PeekyCore

@Suite("Visible_mermaidRenderJob")
struct Visible_mermaidRenderJob {

    @Test("深色、两张图：按出现顺序配成「源码文件 → 输出 PNG」")
    func test_mermaidRenderJob_parsesAppearanceAndPairs() {
        let arguments = ["peeky-mermaid", "--appearance", "dark", "/tmp/a.mmd", "/tmp/a.png", "/tmp/b.mmd", "/tmp/b.png"]

        let expected = MermaidRenderJob(appearance: .dark, diagrams: [
            .init(source: URL(fileURLWithPath: "/tmp/a.mmd"), output: URL(fileURLWithPath: "/tmp/a.png")),
            .init(source: URL(fileURLWithPath: "/tmp/b.mmd"), output: URL(fileURLWithPath: "/tmp/b.png")),
        ])
        #expect(MermaidRenderJob.parse(arguments) == .success(expected))
    }

    @Test("浅色")
    func test_mermaidRenderJob_parsesLightAppearance() {
        let result = MermaidRenderJob.parse(["peeky-mermaid", "--appearance", "light", "/tmp/a.mmd", "/tmp/a.png"])

        #expect(result == .success(MermaidRenderJob(appearance: .light, diagrams: [
            .init(source: URL(fileURLWithPath: "/tmp/a.mmd"), output: URL(fileURLWithPath: "/tmp/a.png")),
        ])))
    }

    @Test("缺 --appearance、明暗写错、路径不成对、一张图都没有：各报各的错误码")
    func test_mermaidRenderJob_rejectsMalformedArguments() {
        #expect(MermaidRenderJob.parse(["peeky-mermaid", "/tmp/a.mmd", "/tmp/a.png"]) == .failure(.missingAppearance))
        #expect(MermaidRenderJob.parse(["peeky-mermaid"]) == .failure(.missingAppearance))
        #expect(MermaidRenderJob.parse(["peeky-mermaid", "--appearance", "dim", "/tmp/a.mmd", "/tmp/a.png"]) == .failure(.invalidAppearance("dim")))
        #expect(MermaidRenderJob.parse(["peeky-mermaid", "--appearance", "dark", "/tmp/a.mmd"]) == .failure(.unpairedPath("/tmp/a.mmd")))
        #expect(MermaidRenderJob.parse(["peeky-mermaid", "--appearance", "dark"]) == .failure(.noDiagrams))
    }

    @Test("错误同时给出错误码与给人读的说明")
    func test_mermaidRenderJob_errorCarriesCodeAndMessage() {
        let error = MermaidRenderJob.ParseError.unpairedPath("/tmp/a.mmd")

        #expect(error.code == "unpaired_path")
        #expect(error.message.contains("/tmp/a.mmd"))
    }
}
