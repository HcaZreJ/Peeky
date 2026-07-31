import Testing
import Foundation
@testable import PeekyKit

@Suite("Hidden_markdownLinkPolicy")
struct Hidden_markdownLinkPolicy {

    @Test("https 链接点击 → openExternally 携带原 URL")
    func test_markdownLinkPolicy_httpsOpensExternally() throws {
        let url = try #require(URL(string: "https://github.com/apple/swift-markdown"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .openExternally(url))
    }

    @Test("http 链接点击 → openExternally")
    func test_markdownLinkPolicy_httpOpensExternally() throws {
        let url = try #require(URL(string: "http://example.com"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .openExternally(url))
    }

    @Test("mailto 链接点击 → openExternally 交系统邮件客户端")
    func test_markdownLinkPolicy_mailtoOpensExternally() throws {
        let url = try #require(URL(string: "mailto:someone@example.com"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .openExternally(url))
    }

    @Test("file 链接点击 → openExternally 交系统默认程序")
    func test_markdownLinkPolicy_fileURLOpensExternally() throws {
        let url = URL(fileURLWithPath: "/tmp/readme.md")
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .openExternally(url))
    }

    @Test("自定义 scheme（如 vscode://）点击 → openExternally 交 LaunchServices 路由")
    func test_markdownLinkPolicy_customSchemeOpensExternally() throws {
        let url = try #require(URL(string: "vscode://file/tmp/a.swift"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .openExternally(url))
    }

    @Test("带 query 与 fragment 的外部 URL 原样传递，信息零丢失")
    func test_markdownLinkPolicy_externalURLPreservedVerbatim() throws {
        let url = try #require(URL(string: "https://example.com/a%20b?q=%E4%B8%AD#sec-2"))
        let decision = MarkdownLinkPolicy.decision(for: url, isLinkActivated: true)
        guard case .openExternally(let opened) = decision else {
            Issue.record("期望 openExternally，实际 \(decision)")
            return
        }
        #expect(opened.absoluteString == "https://example.com/a%20b?q=%E4%B8%AD#sec-2")
    }

    @Test("链接点击但 URL 为 nil → 静默取消")
    func test_markdownLinkPolicy_nilURLClickCancelled() throws {
        #expect(MarkdownLinkPolicy.decision(for: nil, isLinkActivated: true) == .cancel)
    }

    @Test("程序性加载 URL 为 nil → 放行")
    func test_markdownLinkPolicy_nilURLProgrammaticAllowed() throws {
        #expect(MarkdownLinkPolicy.decision(for: nil, isLinkActivated: false) == .allow)
    }

    @Test("程序性加载 http URL（重定向等）→ 放行")
    func test_markdownLinkPolicy_programmaticHTTPAllowed() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: false) == .allow)
    }

    @Test("about:blank 无锚点的点击 → 静默取消（无处可去）")
    func test_markdownLinkPolicy_aboutBlankWithoutFragmentCancelled() throws {
        let url = try #require(URL(string: "about:blank"))
        #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .cancel)
    }

    @Test("about:blank# 各种锚点值均留在页内")
    func test_markdownLinkPolicy_aboutBlankFragmentsAllowed() throws {
        for fragment in ["heading-0", "heading-42", "x"] {
            let url = try #require(URL(string: "about:blank#\(fragment)"))
            #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .allow)
        }
    }

    @Test("about: 下的非 blank 目标（相对链接对 about:blank 解析的产物）→ 静默取消")
    func test_markdownLinkPolicy_aboutNonBlankCancelled() throws {
        for raw in ["about:srcdoc", "about:other.md", "about:other.md#sec"] {
            let url = try #require(URL(string: raw))
            #expect(MarkdownLinkPolicy.decision(for: url, isLinkActivated: true) == .cancel)
        }
    }
}
