import Foundation
import Markdown

/// Markdown → HTML 渲染（WebView 路径）：把 GFM markdown 转成 `.markdown-body` 内层
/// HTML，交由 WKWebView + 真 github-markdown-css 呈现，实现像素级对齐 github。
///
/// 纯函数命名空间（无状态 enum），符合本 repo functional-core 约定。
enum MarkdownHTMLRenderer {

    /// GFM markdown → `.markdown-body` 内层 HTML 片段。
    static func renderHTML(_ markdown: String) -> String {
        renderWithOutline(markdown).html
    }

    /// GFM markdown → (内层 HTML, 标题大纲)。h1–h4 标题按文档顺序赋 `id="heading-N"`，
    /// 序号 N 与 `outline` 数组下标一致，供大纲项 → `#heading-N` 跳转。
    static func renderWithOutline(_ markdown: String) -> (html: String, outline: [MarkdownOutlineItem]) {
        let document = Document(parsing: markdown, options: [.disableSmartOpts])
        let visitor = MarkdownHTMLVisitor()
        let html = document.children.map { visitor.visit($0) }.joined()
        return (html, visitor.outline)
    }

    /// 组装完整 HTML 文档：内嵌 css + 包装样式 + `.markdown-body` 容器 + 极简滚动 JS。
    static func documentHTML(bodyHTML: String, css: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        <style>
        body{margin:0}
        .markdown-body{box-sizing:border-box;max-width:980px;margin:0 auto;padding:32px 24px}
        .markdown-body img{max-width:100%}
        </style>
        </head>
        <body class="markdown-body">\(bodyHTML)</body>
        <script>function scrollToHeading(n){var e=document.getElementById('heading-'+n);if(e)e.scrollIntoView();}</script>
        </html>
        """
    }

    /// 照 HighlightService 多候选寻径从 PeekyKit 资源包读 github-markdown.css；
    /// 找不到返回空串（样式降级不崩）。
    static func loadGithubMarkdownCSS() -> String {
        let bundleName = "Peeky_PeekyKit.bundle"
        var candidateURLs: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(bundleName))
        }
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))

        for candidateURL in candidateURLs {
            guard let resourceBundle = Bundle(url: candidateURL) else { continue }
            guard let cssURL = resourceBundle.url(forResource: "github-markdown", withExtension: "css") else { continue }
            if let source = try? String(contentsOf: cssURL, encoding: .utf8) {
                return source
            }
        }

        return ""
    }

    // MARK: - Escaping

    /// 文本节点转义：`&` 先转、再 `<`、`>`。不涉及属性值的引号转义。
    fileprivate static func escapeText(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        return escaped
    }

    /// 属性值转义（href/src/alt）：在文本转义基础上再转 `"`。
    fileprivate static func escapeAttribute(_ text: String) -> String {
        var escaped = escapeText(text)
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        return escaped
    }

    // MARK: - Shared helpers

    /// 递归拉平元素的可读文本内容，丢弃 Markdown 语法标记（反引号、强调星号、
    /// 链接方括号/URL），供标题大纲标题与图片 alt 文本使用。
    fileprivate static func plainText(of markup: Markup) -> String {
        if let text = markup as? Text {
            return text.string
        }
        if let inlineCode = markup as? InlineCode {
            return inlineCode.code
        }
        if markup is SoftBreak {
            return " "
        }
        if markup is LineBreak {
            return " "
        }
        if let html = markup as? InlineHTML {
            return html.rawHTML
        }

        var combined = ""
        for child in markup.children {
            combined += plainText(of: child)
        }
        return combined
    }

    /// GFM 裸链接（autolink 扩展）识别：swift-markdown 未接入该 cmark-gfm 扩展，
    /// `NSDataDetector`（Foundation，无额外依赖）代为识别 http(s)/www/email 片段。
    fileprivate static let autolinkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
}

/// Single-pass `MarkupVisitor` that returns each node's HTML representation
/// as a `String`, built bottom-up from inline leaves to the document root.
private final class MarkdownHTMLVisitor: MarkupVisitor {
    typealias Result = String

    private(set) var outline: [MarkdownOutlineItem] = []
    private var headingCount = 0
    private var linkDepth = 0

    /// `MarkupVisitor.visit(_:)`'s default protocol-extension implementation
    /// is declared `mutating`, which would force every call site (including
    /// internal recursive calls on `self`) to treat this reference type as
    /// if it needed `var`-style mutation. Overriding it directly as a plain
    /// instance method lets a `let`-bound visitor recurse through its own
    /// reference without fighting Swift's mutating-witness dispatch.
    func visit(_ markup: Markup) -> String {
        var this = self
        return markup.accept(&this)
    }

    func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: - Block elements

    func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(inlineHTML(paragraph))</p>"
    }

    func visitHeading(_ heading: Heading) -> String {
        let inner = inlineHTML(heading)
        let tag = "h\(heading.level)"

        guard heading.level <= 4 else {
            return "<\(tag)>\(inner)</\(tag)>"
        }

        let index = headingCount
        headingCount += 1
        outline.append(
            MarkdownOutlineItem(
                level: heading.level,
                title: MarkdownHTMLRenderer.plainText(of: heading),
                sourceLine: heading.range?.lowerBound.line ?? 0,
                renderedLocation: nil
            )
        )

        return "<\(tag) id=\"heading-\(index)\">\(inner)</\(tag)>"
    }

    func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let inner = blockQuote.children.map { visit($0) }.joined()
        return "<blockquote>\(inner)</blockquote>"
    }

    func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }
        let escaped = MarkdownHTMLRenderer.escapeText(code)
        if let language = codeBlock.language, !language.isEmpty {
            return "<pre><code class=\"language-\(language)\">\(escaped)</code></pre>"
        }
        return "<pre><code>\(escaped)</code></pre>"
    }

    func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>"
    }

    func visitOrderedList(_ orderedList: OrderedList) -> String {
        let items: String = orderedList.listItems.map { self.visit($0) }.joined()
        if orderedList.startIndex != 1 {
            return "<ol start=\"\(orderedList.startIndex)\">\(items)</ol>"
        }
        return "<ol>\(items)</ol>"
    }

    func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let items: String = unorderedList.listItems.map { self.visit($0) }.joined()
        return "<ul>\(items)</ul>"
    }

    /// 普通列表项用无属性 `<li>`；段落子块不额外包 `<p>`（内容直接内联拼接），
    /// 嵌套块（子列表/引用/代码块等）按其自身块级渲染规则递归展开。
    func visitListItem(_ listItem: ListItem) -> String {
        var content = ""
        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                content += inlineHTML(paragraph)
            } else {
                content += visit(child)
            }
        }

        if let checkbox = listItem.checkbox {
            let checkedAttribute = checkbox == .checked ? " checked" : ""
            return "<li class=\"task-list-item\"><input type=\"checkbox\"\(checkedAttribute) disabled> \(content)</li>"
        }

        return "<li>\(content)</li>"
    }

    func visitTable(_ table: Table) -> String {
        let columnCount = table.maxColumnCount
        guard columnCount > 0 else { return "" }

        let rawAlignments = table.columnAlignments
        let alignments: [Table.ColumnAlignment?] = (0..<columnCount).map { index in
            index < rawAlignments.count ? rawAlignments[index] : nil
        }

        let headCells = Array(table.head.cells)
        var headRow = "<tr>"
        for index in 0..<columnCount {
            let content = index < headCells.count ? inlineHTML(headCells[index]) : ""
            headRow += "<th\(alignmentAttribute(alignments[index]))>\(content)</th>"
        }
        headRow += "</tr>"

        var bodyRows = ""
        for row in table.body.rows {
            let cells = Array(row.cells)
            var rowHTML = "<tr>"
            for index in 0..<columnCount {
                let content = index < cells.count ? inlineHTML(cells[index]) : ""
                rowHTML += "<td\(alignmentAttribute(alignments[index]))>\(content)</td>"
            }
            rowHTML += "</tr>"
            bodyRows += rowHTML
        }

        return "<table><thead>\(headRow)</thead><tbody>\(bodyRows)</tbody></table>"
    }

    // MARK: - Inline elements

    func visitText(_ text: Text) -> String {
        guard linkDepth == 0 else {
            return MarkdownHTMLRenderer.escapeText(text.string)
        }
        return autolinkedHTML(for: text.string)
    }

    func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>"
    }

    func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(MarkdownHTMLRenderer.escapeText(inlineCode.code))</code>"
    }

    func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(inlineHTML(emphasis))</em>"
    }

    func visitStrong(_ strong: Strong) -> String {
        "<strong>\(inlineHTML(strong))</strong>"
    }

    func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(inlineHTML(strikethrough))</del>"
    }

    func visitLink(_ link: Link) -> String {
        guard let destination = link.destination, !destination.isEmpty else {
            return inlineHTML(link)
        }

        linkDepth += 1
        let inner = inlineHTML(link)
        linkDepth -= 1

        return "<a href=\"\(MarkdownHTMLRenderer.escapeAttribute(destination))\">\(inner)</a>"
    }

    func visitImage(_ image: Image) -> String {
        let alt = MarkdownHTMLRenderer.plainText(of: image)
        let source = image.source ?? ""
        return "<img src=\"\(MarkdownHTMLRenderer.escapeAttribute(source))\" alt=\"\(MarkdownHTMLRenderer.escapeAttribute(alt))\">"
    }

    // MARK: - Shared helpers

    private func inlineHTML<Container: InlineContainer>(_ container: Container) -> String {
        container.inlineChildren.map { self.visit($0) }.joined()
    }

    private func alignmentAttribute(_ alignment: Table.ColumnAlignment?) -> String {
        guard let alignment else { return "" }
        switch alignment {
        case .left: return " align=\"left\""
        case .center: return " align=\"center\""
        case .right: return " align=\"right\""
        @unknown default: return ""
        }
    }

    /// Splits a plain-text run on bare http(s)/www/email spans (GFM's
    /// autolink extension, which swift-markdown's parser doesn't attach) and
    /// wraps each detected span in `<a href="{url}">{url}</a>`, matching the
    /// styling an explicit `[text](url)` link gets.
    private func autolinkedHTML(for string: String) -> String {
        guard let detector = MarkdownHTMLRenderer.autolinkDetector, !string.isEmpty else {
            return MarkdownHTMLRenderer.escapeText(string)
        }

        let nsString = string as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = detector.matches(in: string, range: fullRange)

        guard !matches.isEmpty else {
            return MarkdownHTMLRenderer.escapeText(string)
        }

        var result = ""
        var cursor = 0
        for match in matches {
            guard match.range.location >= cursor, match.range.length > 0 else { continue }

            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                result += MarkdownHTMLRenderer.escapeText(nsString.substring(with: plainRange))
            }

            let linkText = nsString.substring(with: match.range)
            let href = match.url?.absoluteString ?? linkText
            let escapedURL = MarkdownHTMLRenderer.escapeAttribute(href)
            let escapedText = MarkdownHTMLRenderer.escapeText(linkText)
            result += "<a href=\"\(escapedURL)\">\(escapedText)</a>"

            cursor = match.range.location + match.range.length
        }

        if cursor < nsString.length {
            let remainderRange = NSRange(location: cursor, length: nsString.length - cursor)
            result += MarkdownHTMLRenderer.escapeText(nsString.substring(with: remainderRange))
        }

        return result
    }
}
