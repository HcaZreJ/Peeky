import Testing
import Foundation
@testable import PeekyKit

// MARK: - Helpers
//
// 结构化断言小工具：只用于从渲染出的 HTML 片段里数出现次数 / 取出某个标签
// 自身（含属性）的文本，不涉及 MarkdownHTMLRenderer 的内部实现细节。

/// 计算 needle 在 haystack 中非重叠出现次数。
private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = haystack.startIndex..<haystack.endIndex
    while let range = haystack.range(of: needle, range: searchRange) {
        count += 1
        searchRange = range.upperBound..<haystack.endIndex
    }
    return count
}

/// 安全下标：stub 阶段集合可能是退化的空集合，直接 `array[i]` 会 trap 并
/// 中止整个共享 PeekyTests 进程；越界时返回 nil，交给调用方 `try #require`。
private func element<T>(_ array: [T], _ index: Int) -> T? {
    array.indices.contains(index) ? array[index] : nil
}

@Suite("Visible_markdownHTMLRenderer")
struct Visible_markdownHTMLRenderer {

    @Test("标题带序号 id、段落包裹、行内加粗/斜体/代码均按契约渲染")
    func test_markdownHTMLRenderer_headingsParagraphAndInlineFormatting() throws {
        let markdown = "# Title\n\nA paragraph with **bold**, *em*, and `code`."
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        #expect(html.contains("<h1 id=\"heading-0\">Title</h1>"))
        #expect(html.contains("<p>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>em</em>"))
        #expect(html.contains("<code>code</code>"))
    }

    @Test("无序列表与带语言的围栏代码块按契约渲染")
    func test_markdownHTMLRenderer_listsAndFencedCodeBlock() throws {
        let markdown = "- Apple\n- Banana\n\n```swift\nlet x = 1\n```"
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        #expect(html.contains("<ul>"))
        #expect(occurrences(of: "<li>", in: html) == 2)
        #expect(html.contains("Apple"))
        #expect(html.contains("Banana"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = 1"))
    }

    @Test("顶部 YAML frontmatter 剥离为 <dl> 键值表：inline scalar 直接展示，含裸引号 value 被容忍")
    func test_markdownHTMLRenderer_extractsFrontmatterInlineScalars() throws {
        let markdown = """
            ---
            name: Explore
            description: Search agent — accepts "medium" or "very thorough" breadth
            ---

            正文段落。
            """
        let result = MarkdownHTMLRenderer.renderWithOutline(markdown)

        #expect(result.html.contains("<dl class=\"peeky-frontmatter\">"))
        #expect(result.html.contains("<dt class=\"peeky-fm-key\">name</dt>"))
        #expect(result.html.contains("<dd class=\"peeky-fm-value\">Explore</dd>"))
        #expect(result.html.contains("<dt class=\"peeky-fm-key\">description</dt>"))
        #expect(result.html.contains("\"medium\""))
        #expect(result.html.contains("\"very thorough\""))
        #expect(result.html.contains("<p>正文段落。</p>"))
        #expect(!result.html.contains("<h2"))
        #expect(!result.html.contains("<hr>"))
        #expect(result.outline.isEmpty)
    }

    @Test("嵌套 YAML frontmatter 的 block value 降级为 <pre class=peeky-fm-block> 分色源码块")
    func test_markdownHTMLRenderer_extractsFrontmatterNestedBlockValue() throws {
        let markdown = """
            ---
            name: fn
            hooks:
              PreToolUse:
                - matcher: "Read|Glob"
            ---

            body
            """
        let result = MarkdownHTMLRenderer.renderWithOutline(markdown)

        #expect(result.html.contains("<dt class=\"peeky-fm-key\">hooks</dt>"))
        #expect(result.html.contains("<pre class=\"peeky-fm-block\">"))
        #expect(result.html.contains("<span class=\"peeky-fm-nested-key\">PreToolUse</span>"))
        #expect(result.html.contains("<span class=\"peeky-fm-dash\">- </span>"))
        #expect(result.html.contains("<span class=\"peeky-fm-nested-key\">matcher</span>"))
        #expect(result.html.contains("\"Read|Glob\""))
        // 顶级扁平 pair 仍走 inline scalar
        #expect(result.html.contains("<dd class=\"peeky-fm-value\">fn</dd>"))
    }

    @Test("renderWithOutline 提取的大纲与 html 标题 id 对应；documentHTML 组装出完整文档骨架")
    func test_markdownHTMLRenderer_outlineAndDocumentHTMLAssembly() throws {
        let result = MarkdownHTMLRenderer.renderWithOutline("# One\n\n## Two\n\n### Three")

        #expect(result.outline.count == 3)
        let first = try #require(element(result.outline, 0))
        #expect(first.level == 1)
        #expect(first.title == "One")
        let second = try #require(element(result.outline, 1))
        #expect(second.level == 2)
        #expect(second.title == "Two")
        let third = try #require(element(result.outline, 2))
        #expect(third.level == 3)
        #expect(third.title == "Three")

        #expect(result.html.contains("<h1 id=\"heading-0\">One</h1>"))
        #expect(result.html.contains("<h2 id=\"heading-1\">Two</h2>"))
        #expect(result.html.contains("<h3 id=\"heading-2\">Three</h3>"))

        let doc = MarkdownHTMLRenderer.documentHTML(
            bodyHTML: "<h1 id=\"heading-0\">Hi</h1>",
            css: ".markdown-body{color:red}"
        )

        #expect(doc.lowercased().contains("<!doctype html"))
        #expect(doc.contains("<html"))
        #expect(doc.contains("<head"))
        #expect(doc.contains(".markdown-body{color:red}"))
        #expect(doc.contains("<body"))
        #expect(doc.contains("class=\"markdown-body\""))
        #expect(doc.contains("<h1 id=\"heading-0\">Hi</h1>"))
    }
}
