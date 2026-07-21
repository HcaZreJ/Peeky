import Foundation
import Markdown

struct MarkdownOutlineItem {
    let level: Int
    let title: String
    let sourceLine: Int
}

/// Markdown 大纲抽取：WKWebView 主渲染路径与 >8MB raw 兜底路径共用；`MarkdownHTMLRenderer`
/// 在 AST→HTML 遍历中直接产大纲，本入口是纯文本 raw 兜底走的独立解析入口。
enum MarkdownRenderer {
    static func outline(in text: String) -> [MarkdownOutlineItem] {
        let document = Document(parsing: text, options: [.disableSmartOpts])
        var items: [MarkdownOutlineItem] = []
        for child in document.children {
            collectOutline(child, into: &items)
        }
        return items
    }

    private static func collectOutline(_ markup: Markup, into items: inout [MarkdownOutlineItem]) {
        if let heading = markup as? Heading {
            if heading.level <= 4 {
                items.append(
                    MarkdownOutlineItem(
                        level: heading.level,
                        title: plainDisplayText(of: heading),
                        sourceLine: heading.range?.lowerBound.line ?? 0
                    )
                )
            }
            return
        }

        for child in markup.children {
            collectOutline(child, into: &items)
        }
    }

    /// Recursively flattens an element's readable text content, discarding
    /// Markdown syntax markers (backticks, emphasis asterisks, link
    /// brackets/URLs) so headings read naturally in the outline sidebar.
    static func plainDisplayText(of markup: Markup) -> String {
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
            combined += plainDisplayText(of: child)
        }
        return combined
    }
}
