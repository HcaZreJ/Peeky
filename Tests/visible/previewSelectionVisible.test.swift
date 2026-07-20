import Testing
import AppKit
@testable import PeekyKit

// T3 的唯一纯逻辑点：复制选中的 payload 判定（选区非空取选区，空则回落全文）。
// 其余 T3 改动属 NSTextView/菜单/外观等 UI 接线，靠构建 + 手动两外观验收，无单测。
@Suite("Visible_previewSelection")
struct Visible_previewSelection {

    @Test("selectionCopyPayload: 选区非空时返回选区文本")
    func test_previewSelection_returnsSelectionWhenNonEmpty() {
        #expect(PreviewWindowController.selectionCopyPayload(selected: "picked", full: "picked and more") == "picked")
    }

    @Test("selectionCopyPayload: 选区为空时回落返回全文")
    func test_previewSelection_fallsBackToFullWhenEmpty() {
        #expect(PreviewWindowController.selectionCopyPayload(selected: "", full: "the whole document") == "the whole document")
    }

    @Test("selectionCopyPayload: 仅空白的选区视为真实选区（长度非零），不回落")
    func test_previewSelection_whitespaceSelectionIsNotEmpty() {
        #expect(PreviewWindowController.selectionCopyPayload(selected: "   ", full: "full text") == "   ")
    }

    @Test("selectionCopyPayload: 选区与全文相同也照常返回选区")
    func test_previewSelection_selectionEqualToFullReturnsSelection() {
        #expect(PreviewWindowController.selectionCopyPayload(selected: "same", full: "same") == "same")
    }
}
