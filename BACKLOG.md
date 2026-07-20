# BACKLOG

## 执行中 · Plan: markdown-render-redesign   (→ .claude/plans/markdown-render-redesign.md)

Markdown 改用 **WKWebView + 真 github-markdown-css**（混合架构，仅 markdown 用 WebView）。
验收含 AST→HTML 结构化测试全绿 + 用户 WebView 实机观感签字。

### Wave 1 — 核心（test-first）
- [ ] W1  MarkdownHTMLRenderer——AST→HTML 纯函数（GFM 完整）
        file: Sources/PeekyKit/MarkdownHTMLRenderer.swift（新）  deps: —
        spec: swift-markdown AST → HTML；标题赋 id=heading-N（与 outline 同序）、任务列表 checkbox、
              表格对齐、嵌套引用、围栏代码块 language class、行内元素、HTML 转义
        验收: 各 GFM 元素 HTML 结构化断言（含嵌套/转义/id 序号）全绿

### Wave 2 — 组装
- [ ] W2  HTML 文档包装 + github-markdown.css 资源加载
        file: Sources/PeekyKit/MarkdownHTMLRenderer.swift  deps: W1
        spec: documentHTML(body,css) 组装完整文档（markdown-body class + css 注入 + 包装样式 + 极简滚动 JS）；
              loadGithubMarkdownCSS 照 HighlightService 多候选寻径读资源
        验收: 组装结构化断言

### Wave 3 — 集成（架构师直做 + 观感验收）
- [ ] W3  WKWebView 集成到 PreviewWindowController（markdown 专用）
        file: Sources/PeekyKit/PreviewWindowController.swift  deps: W1,W2
        spec: markdown 专用 WebView 同区叠放显隐；loadHTMLString；外观跟随系统；预热共享实例；
              大纲点击→scrollToHeading(JS)；peeky:// 行→最近标题；选中复制走原生。其它类型不变
        验收: WebView 呈现像素级对齐 github（用户浅深两外观签字）+ 其它类型全量测试无回归

### Wave 4 — 清理（W3 验收后）
- [ ] W4  清理原生 markdown 死路径（palette/标题线绘制/attributed body），保留 outline
        file: MarkdownRenderer.swift, DropContainerView.swift, PreviewRenderer.swift  deps: W3
        验收: 移除后全量测试绿、其它类型无回归
