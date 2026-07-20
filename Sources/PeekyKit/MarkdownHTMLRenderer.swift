import Foundation

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
        ("", [])
    }

    /// 组装完整 HTML 文档：内嵌 css + 包装样式 + `.markdown-body` 容器 + 极简滚动 JS。
    static func documentHTML(bodyHTML: String, css: String) -> String {
        ""
    }

    /// 照 HighlightService 多候选寻径从 PeekyKit 资源包读 github-markdown.css；
    /// 找不到返回空串（样式降级不崩）。
    static func loadGithubMarkdownCSS() -> String {
        ""
    }
}
