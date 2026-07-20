import Testing
import Foundation
@testable import PeekyKit

// MARK: - Helpers
//
// 结构化断言小工具：只用于从渲染出的 HTML 片段里数出现次数 / 取出某个标签
// 自身（含属性，不含内容）的文本，不涉及 MarkdownHTMLRenderer 的内部实现细节。
// spec 明确要求断言用 `.contains`/正则/计数，禁止对整份 HTML 做精确相等
// （标签间空白/换行可变），这些 helper 就是为此服务的。

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

/// 找到紧邻在 `text` 之前、名为 `tagName` 的最近一个开标签（如
/// `<th align="right">`），返回该开标签自身的完整文本（含属性）。用于断言
/// 标签自身的属性（id/align/class），而不误判到别的同名标签或标签内容。
private func openingTag(_ tagName: String, before text: String, in html: String) -> String? {
    guard let textRange = html.range(of: text) else { return nil }
    guard let tagStart = html.range(of: "<\(tagName)", options: .backwards, range: html.startIndex..<textRange.lowerBound) else {
        return nil
    }
    guard let tagClose = html.range(of: ">", range: tagStart.upperBound..<textRange.lowerBound) else { return nil }
    return String(html[tagStart.lowerBound..<tagClose.upperBound])
}

/// 找到包含 `text` 的最近一个完整 `<li>...</li>` 片段（用于校验任务列表某一
/// 项的 class/input 勾选态，避免被同一文档内其它 `<li>` 的属性串味）。
private func liFragment(containing text: String, in html: String) -> String? {
    guard let textRange = html.range(of: text) else { return nil }
    guard let liStart = html.range(of: "<li", options: .backwards, range: html.startIndex..<textRange.lowerBound) else {
        return nil
    }
    guard let liEnd = html.range(of: "</li>", range: textRange.upperBound..<html.endIndex) else { return nil }
    return String(html[liStart.lowerBound..<liEnd.upperBound])
}

/// 安全下标：stub 阶段集合可能是退化的空集合，直接 `array[i]` 会 trap 并
/// 中止整个共享 PeekyTests 进程；越界时返回 nil，交给调用方 `try #require`。
private func element<T>(_ array: [T], _ index: Int) -> T? {
    array.indices.contains(index) ? array[index] : nil
}

@Suite("Hidden_markdownHTMLRenderer")
struct Hidden_markdownHTMLRenderer {

    // MARK: - 标题

    @Test("h1-h4 按文档顺序赋 id=heading-N（N 从 0 起）")
    func test_renderHTML_headingsH1ThroughH4GetSequentialIds() throws {
        let markdown = "# A\n\n## B\n\n### C\n\n#### D"
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        #expect(html.contains("<h1 id=\"heading-0\">A</h1>"))
        #expect(html.contains("<h2 id=\"heading-1\">B</h2>"))
        #expect(html.contains("<h3 id=\"heading-2\">C</h3>"))
        #expect(html.contains("<h4 id=\"heading-3\">D</h4>"))
    }

    @Test("h5/h6 渲染为对应标签，但不带 id")
    func test_renderHTML_headingsH5H6RenderWithoutId() throws {
        let markdown = "##### E\n\n###### F"
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        let h5Tag = try #require(openingTag("h5", before: "E", in: html))
        #expect(!h5Tag.contains("id="))

        let h6Tag = try #require(openingTag("h6", before: "F", in: html))
        #expect(!h6Tag.contains("id="))
    }

    // MARK: - 段落 / 行内

    @Test("普通段落包裹在 <p>...</p> 中")
    func test_renderHTML_paragraphWrapsText() throws {
        let html = MarkdownHTMLRenderer.renderHTML("Just a paragraph of text.")
        #expect(html.contains("<p>Just a paragraph of text.</p>"))
    }

    @Test("行内加粗/斜体/删除线/代码均按契约标签渲染")
    func test_renderHTML_inlineFormattingBoldEmStrikeCode() throws {
        let html = MarkdownHTMLRenderer.renderHTML("**bold** *em* ~~strike~~ `code`")
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>em</em>"))
        #expect(html.contains("<del>strike</del>"))
        #expect(html.contains("<code>code</code>"))
    }

    // MARK: - 围栏代码块

    @Test("带语言的围栏代码块渲染 language-<lang> class")
    func test_renderHTML_fencedCodeBlockWithLanguageClass() throws {
        let html = MarkdownHTMLRenderer.renderHTML("```swift\nlet x = 1\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = 1"))
    }

    @Test("无语言的围栏代码块不带 class，且代码内容做 HTML 转义")
    func test_renderHTML_fencedCodeBlockWithoutLanguageEscapesContent() throws {
        let html = MarkdownHTMLRenderer.renderHTML("```\n<div>&\n```")
        #expect(html.contains("<pre><code>"))
        #expect(!html.contains("<pre><code class="))
        #expect(html.contains("&lt;div&gt;&amp;"))
    }

    // MARK: - 引用块

    @Test("单层引用块渲染 <blockquote> 且内含 <p>x</p>")
    func test_renderHTML_blockquoteWrapsParagraph() throws {
        let html = MarkdownHTMLRenderer.renderHTML("> Quoted line")
        #expect(html.contains("<blockquote"))
        #expect(html.contains("<p>Quoted line</p>"))
    }

    @Test("嵌套引用块出现至少 2 个 <blockquote，且最内层是最内文本的 <p>")
    func test_renderHTML_nestedBlockquoteHasMultipleLevels() throws {
        let html = MarkdownHTMLRenderer.renderHTML("> Outer\n> > Inner")
        #expect(occurrences(of: "<blockquote", in: html) >= 2)
        #expect(html.contains("<p>Inner</p>"))
    }

    // MARK: - 列表

    @Test("无序列表渲染 <ul> 与对应数量的 <li>")
    func test_renderHTML_unorderedListRendersULAndLI() throws {
        let html = MarkdownHTMLRenderer.renderHTML("- One\n- Two\n- Three")
        #expect(html.contains("<ul>"))
        #expect(occurrences(of: "<li>", in: html) == 3)
        #expect(html.contains("One"))
        #expect(html.contains("Two"))
        #expect(html.contains("Three"))
    }

    @Test("有序列表起始号非 1 时用 <ol start=\"N\">")
    func test_renderHTML_orderedListWithNonDefaultStart() throws {
        let html = MarkdownHTMLRenderer.renderHTML("5. Five\n6. Six\n7. Seven")
        #expect(html.contains("<ol start=\"5\">"))
        #expect(occurrences(of: "<li>", in: html) == 3)
    }

    // MARK: - 任务列表

    @Test("任务列表已完成/未完成项均带 task-list-item class 与 disabled checkbox，仅已完成带 checked")
    func test_renderHTML_taskListCheckedAndUncheckedStates() throws {
        let html = MarkdownHTMLRenderer.renderHTML("- [x] Done\n- [ ] Todo")

        let doneFragment = try #require(liFragment(containing: "Done", in: html))
        #expect(doneFragment.contains("class=\"task-list-item\""))
        #expect(doneFragment.contains("<input type=\"checkbox\""))
        #expect(doneFragment.contains("disabled"))
        #expect(doneFragment.contains("checked"))

        let todoFragment = try #require(liFragment(containing: "Todo", in: html))
        #expect(todoFragment.contains("class=\"task-list-item\""))
        #expect(todoFragment.contains("<input type=\"checkbox\""))
        #expect(todoFragment.contains("disabled"))
        #expect(!todoFragment.contains("checked"))
    }

    // MARK: - 表格

    @Test("表格结构标签齐全，显式左/右对齐列各自带对应 align 属性")
    func test_renderHTML_tableExplicitLeftAndRightAlignment() throws {
        let markdown = "| A | B |\n| :-- | --: |\n| c | d |"
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        #expect(html.contains("<table>"))
        #expect(html.contains("<thead>"))
        #expect(html.contains("<tbody>"))
        // 用闭合标签计数：`<th` 是 `<thead>` 的前缀会误数，`</th>` 无此冲突。
        #expect(occurrences(of: "</th>", in: html) == 2)
        #expect(occurrences(of: "</td>", in: html) == 2)

        let thA = try #require(openingTag("th", before: "A", in: html))
        #expect(thA.contains("align=\"left\""))

        let thB = try #require(openingTag("th", before: "B", in: html))
        #expect(thB.contains("align=\"right\""))

        let tdD = try #require(openingTag("td", before: "d", in: html))
        #expect(tdD.contains("align=\"right\""))
    }

    @Test("表格列无显式对齐标记时，该列单元格不携带 align 属性")
    func test_renderHTML_tableColumnWithoutExplicitAlignmentOmitsAttribute() throws {
        let markdown = "| A | B |\n| --- | --: |\n| c | d |"
        let html = MarkdownHTMLRenderer.renderHTML(markdown)

        let thA = try #require(openingTag("th", before: "A", in: html))
        #expect(!thA.contains("align="))

        let tdC = try #require(openingTag("td", before: "c", in: html))
        #expect(!tdC.contains("align="))

        let thB = try #require(openingTag("th", before: "B", in: html))
        #expect(thB.contains("align=\"right\""))
    }

    // MARK: - 链接 / 图片 / 裸链接

    @Test("显式 markdown 链接渲染 <a href=\"u\">t</a>")
    func test_renderHTML_explicitLinkRendersAnchorTag() throws {
        let html = MarkdownHTMLRenderer.renderHTML("[Example](https://example.com)")
        #expect(html.contains("<a href=\"https://example.com\">Example</a>"))
    }

    @Test("图片渲染 <img src=\"u\" alt=\"a\">")
    func test_renderHTML_imageRendersImgTag() throws {
        let html = MarkdownHTMLRenderer.renderHTML("![Alt text](https://example.com/img.png)")
        #expect(html.contains("<img src=\"https://example.com/img.png\" alt=\"Alt text\">"))
    }

    @Test("正文中的裸链接自动变为 <a href=\"u\">u</a>")
    func test_renderHTML_bareURLAutolinksToAnchor() throws {
        let html = MarkdownHTMLRenderer.renderHTML("Visit https://example.com/page today.")
        #expect(html.contains("<a href=\"https://example.com/page\">https://example.com/page</a>"))
    }

    // MARK: - 分隔线

    @Test("水平分隔线渲染 <hr>")
    func test_renderHTML_thematicBreakRendersHR() throws {
        let markdown = "First paragraph.\n\n---\n\nSecond paragraph."
        let html = MarkdownHTMLRenderer.renderHTML(markdown)
        #expect(html.contains("<hr>"))
    }

    // MARK: - 转义

    @Test("正文中的 & < > 均做 HTML 转义，不遗留裸露的尖括号/&")
    func test_renderHTML_specialCharactersAreEscaped() throws {
        let html = MarkdownHTMLRenderer.renderHTML("a < b & c > d")
        #expect(html.contains("a &lt; b &amp; c &gt; d"))
        #expect(!html.contains("a < b"))
        #expect(!html.contains("b & c"))
    }

    // MARK: - 鲁棒性

    @Test(
        "空输入 / 纯空白输入不产生任何标题标签",
        arguments: ["", "\n\n   \n\t\n"]
    )
    func test_renderHTML_emptyOrWhitespaceInputHasNoHeadingTags(markdown: String) throws {
        let html = MarkdownHTMLRenderer.renderHTML(markdown)
        #expect(!html.contains("<h1"))
        #expect(!html.contains("<h2"))
        #expect(!html.contains("<h3"))
    }

    // MARK: - 大纲

    @Test("renderWithOutline 对 h1-h4 依文档顺序生成大纲，且与 html 中的 heading id 对应")
    func test_renderWithOutline_headingSequenceMatchesIdsAndOutlineForH1ThroughH4() throws {
        let markdown = "# One\n\n## Two\n\n### Three\n\n#### Four"
        let result = MarkdownHTMLRenderer.renderWithOutline(markdown)

        #expect(result.outline.count == 4)

        let expected: [(level: Int, title: String)] = [
            (1, "One"), (2, "Two"), (3, "Three"), (4, "Four"),
        ]
        for (item, exp) in zip(result.outline, expected) {
            #expect(item.level == exp.level)
            #expect(item.title == exp.title)
        }

        // sourceLine 反映源文档中的位置，随文档顺序单调递增。
        if result.outline.count > 1 {
            for index in 1..<result.outline.count {
                guard let current = element(result.outline, index), let previous = element(result.outline, index - 1) else {
                    Issue.record("missing outline item at index \(index) or \(index - 1)")
                    continue
                }
                #expect(current.sourceLine > previous.sourceLine)
            }
        }

        #expect(result.html.contains("<h1 id=\"heading-0\">One</h1>"))
        #expect(result.html.contains("<h2 id=\"heading-1\">Two</h2>"))
        #expect(result.html.contains("<h3 id=\"heading-2\">Three</h3>"))
        #expect(result.html.contains("<h4 id=\"heading-3\">Four</h4>"))
    }

    @Test("h5/h6 不进入大纲，但仍渲染在 html 中；大纲下标与仅计入 h1-h4 的 id 编号一致")
    func test_renderWithOutline_h5H6ExcludedFromOutlineButStillRendered() throws {
        let markdown = "# A\n\n##### E\n\n###### F\n\n## B"
        let result = MarkdownHTMLRenderer.renderWithOutline(markdown)

        #expect(result.outline.count == 2)
        let first = try #require(element(result.outline, 0))
        #expect(first.level == 1)
        #expect(first.title == "A")
        let second = try #require(element(result.outline, 1))
        #expect(second.level == 2)
        #expect(second.title == "B")

        #expect(result.html.contains("<h1 id=\"heading-0\">A</h1>"))
        #expect(result.html.contains("<h2 id=\"heading-1\">B</h2>"))

        let h5Tag = try #require(openingTag("h5", before: "E", in: result.html))
        #expect(!h5Tag.contains("id="))
        let h6Tag = try #require(openingTag("h6", before: "F", in: result.html))
        #expect(!h6Tag.contains("id="))
    }

    @Test(
        "空输入 / 纯空白输入的大纲为空",
        arguments: ["", "\n\n   \n\t\n"]
    )
    func test_renderWithOutline_emptyOrWhitespaceInputProducesEmptyOutline(markdown: String) throws {
        let result = MarkdownHTMLRenderer.renderWithOutline(markdown)
        #expect(result.outline.isEmpty)
    }

    // MARK: - documentHTML 组装

    @Test("documentHTML 组装出含 doctype/html/head/body 骨架，并原样注入 css 与 bodyHTML")
    func test_documentHTML_assemblesDoctypeHeadBodyWithInjectedCSSAndBody() throws {
        let bodyHTML = "<h2 id=\"heading-1\">Section</h2><p>Body copy.</p>"
        let css = "body{margin:0}\n.markdown-body{max-width:800px}"
        let doc = MarkdownHTMLRenderer.documentHTML(bodyHTML: bodyHTML, css: css)

        #expect(doc.lowercased().contains("<!doctype html"))
        #expect(doc.contains("<html"))
        #expect(doc.contains("<head"))
        #expect(doc.contains("<style"))
        #expect(doc.contains(css))
        #expect(doc.contains("<body"))
        #expect(doc.contains("class=\"markdown-body\""))
        #expect(doc.contains(bodyHTML))
    }

    @Test("documentHTML 原样注入 bodyHTML，不对其已有的 HTML 转义再次转义")
    func test_documentHTML_injectsBodyHTMLVerbatimWithoutDoubleEscaping() throws {
        let bodyHTML = "<p>A &amp; B &lt;tag&gt;</p>"
        let doc = MarkdownHTMLRenderer.documentHTML(bodyHTML: bodyHTML, css: "")

        #expect(doc.contains(bodyHTML))
        #expect(!doc.contains("&amp;amp;"))
        #expect(!doc.contains("&lt;lt;"))
    }

    // MARK: - 端到端（renderWithOutline 接入 documentHTML）

    @Test("renderWithOutline 产出的 html 接入 documentHTML 后，标题 id 与注入的 css 都完整保留")
    func test_markdownHTMLRenderer_endToEndOutlineIntoDocumentHTMLPreservesHeadingIds() throws {
        let markdownSource = "# Intro\n\nSome text.\n\n## Details\n\nMore text."
        let rendered = MarkdownHTMLRenderer.renderWithOutline(markdownSource)
        let doc = MarkdownHTMLRenderer.documentHTML(bodyHTML: rendered.html, css: ".markdown-body{color:blue}")

        #expect(rendered.outline.count == 2)
        #expect(doc.contains("<h1 id=\"heading-0\">Intro</h1>"))
        #expect(doc.contains("<h2 id=\"heading-1\">Details</h2>"))
        #expect(doc.contains(".markdown-body{color:blue}"))
        #expect(doc.contains("class=\"markdown-body\""))
    }
}
