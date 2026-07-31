import Testing
import Foundation
@testable import PeekyKit

@Suite("Visible_markdownLinkPolicy")
struct Visible_markdownLinkPolicy {

    @Test("用户点击 http(s) 链接 → 取消页内导航，交系统默认浏览器打开原 URL")
    func test_markdownLinkPolicy_linkClickOpensExternally() throws {
        let url = try #require(URL(string: "https://example.com/docs?q=1"))
        let decision = MarkdownLinkPolicy.decision(for: url, isLinkActivated: true)
        #expect(decision == .openExternally(url))
    }

    @Test("loadHTMLString 等程序性加载（非链接点击）→ 放行")
    func test_markdownLinkPolicy_programmaticLoadAllowed() throws {
        let url = try #require(URL(string: "about:blank"))
        let decision = MarkdownLinkPolicy.decision(for: url, isLinkActivated: false)
        #expect(decision == .allow)
    }

    @Test("文档内锚点跳转（about:blank#…）→ 留在页内滚动")
    func test_markdownLinkPolicy_inDocumentAnchorAllowed() throws {
        let url = try #require(URL(string: "about:blank#heading-3"))
        let decision = MarkdownLinkPolicy.decision(for: url, isLinkActivated: true)
        #expect(decision == .allow)
    }
}
