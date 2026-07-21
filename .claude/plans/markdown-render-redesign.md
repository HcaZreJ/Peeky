# Feature: Markdown 渲染（WKWebView + 真 github-markdown-css）

## Overview

Markdown 预览用 **WKWebView 渲染 HTML + 内嵌真正的 github-markdown-css** 实现——像素级对齐 github 由 CSS 引擎保证，而非在原生 TextKit 里手工临摹 CSS。**混合架构**：仅 markdown 走 WebView；JSON/JSONL/源码/日志/纯文本仍走既有原生（NSTextView / NSOutlineView）即时渲染。选中+复制由 WebView 原生自带。**零新增 SPM 依赖**：用现有 swift-markdown 解析、手写 AST→HTML、内嵌 CSS 资源。

## Intent Brief

- **Goal**：markdown 预览像素级「就是 github」，选中可复制，启动可接受。
- **Motivation**：原生 TextKit 手工复刻 CSS 收敛不了（标题线、表格、引用、任务列表逐一失真），且后台作业无法自验视觉；用 CSS 引擎渲染 CSS 是唯一可靠达成「对齐 github-markdown-css」的路径。
- **Known context**：peeky 是常驻窗口 app（PreviewWindowController + tabs）；资源经 `Peeky_PeekyKit.bundle` 多候选寻径加载（见 HighlightService.loadBundleSource）；swift-markdown 0.8.0 已在依赖。
- **Constraints**：零第三方 SPM 依赖（WKWebView 是系统框架，不算 SPM 依赖）；性能预算沿用；主线程纪律。
- **Non-goals**：不改 JSON/源码/日志等的原生渲染；不做 GLFM 专属元素（issue #14）；markdown 代码块**不做语法高亮**（github-markdown-css 本身不含高亮，仅代码块样式，故不高亮即是「对齐 github-markdown-css」）。
- **Success criteria**：markdown 经 WebView 呈现，标题/底边线/表格/引用（含嵌套）/任务列表/列表/代码块/行内码/链接与 github 一致；浅深随系统外观；文本可选中 ⌘C 复制；大纲侧栏可点跳转、`peeky://` 行定位可用；其它文件类型行为不变。
- **Assumptions / Unknowns**：见 Ledger。

## Alignment Gate

- **I will implement**：markdown → WKWebView（HTML + 真 github-markdown-css）；AST→HTML 纯函数；HTML 文档包装 + CSS 资源加载；WebView 集成（外观跟随、预热、大纲跳转、行定位、原生选中复制）。
- **I will not implement**：其它文件类型的渲染改动；markdown 代码块语法高亮；GLFM 元素。
- **Acceptance**：AST→HTML 结构化测试全绿 + 用户对 WebView 实机观感签字。

## Assumption Ledger

| Assumption | Confidence | Impact if Wrong | Status |
|---|---|---|---|
| WebView 首帧一次性 ~100ms 量级、可预热隐藏，peeky 常驻模型下可接受 | high | medium | 用户已确认接受 |
| 放宽 repo「无 WebView」约定（改用 WKWebView 渲 markdown） | high | high | 用户已批准 |
| github-markdown-css 不含代码高亮，故 markdown 代码块不高亮即对齐 CSS | high | low | 架构师判断，随终审校验 |
| 原生 markdown 路径（attributed MarkdownRenderer body + palette + 标题线绘制）在 WebView 落地后清理，outline 抽取保留复用 | high | low | 计划中，WebView 验收后执行 |

## Work-Unit Specs

```yaml
- id: W1
  title: MarkdownHTMLRenderer——AST→HTML 纯函数（GFM 完整）
  file_path: Sources/PeekyKit/MarkdownHTMLRenderer.swift   # 新文件
  functions:
    - name: renderHTML(_ markdown: String) -> String
      outputs: .markdown-body 的内层 HTML 片段
      behavioral_contract: |
        用 swift-markdown 解析、MarkupVisitor 走 AST 输出 HTML：标题 h1-h6（按文档顺序
        赋 id="heading-0/1/2…" 供大纲跳转）、段落、ul/ol、GFM 任务列表（<li> 内含
        <input type=checkbox disabled [checked]>）、表格（<table><thead><th>…<tbody><td>，
        列对齐用 style=text-align）、引用块（含多级嵌套 <blockquote>）、围栏代码块
        （<pre><code class="language-x">，语言在 class）、行内码 <code>、<em>/<strong>/<del>、
        链接 <a href>、图片 <img>、GFM 裸链接自动识别、<hr>、软/硬换行。所有文本内容
        HTML 转义（& < > "）。
      error_cases:
        - { condition: "空/仅空白输入", behavior: "返回空串或最小片段，不崩" }
        - { condition: "畸形/未闭合结构", behavior: "尽力渲染，不崩" }
    - name: outline(in: String) -> [MarkdownOutlineItem]
      behavioral_contract: |
        标题按文档顺序抽取（level/title/sourceLine），顺序索引与 renderHTML 赋的
        heading id 序号一致，供大纲项 → #heading-N 跳转对齐。可复用既有 MarkdownRenderer.outline。
  dependencies: []
  reuse_candidates: 复用 swift-markdown 解析与既有 outline 抽取；HTML 转义自写小工具。
  acceptance: 结构化测试断言各 GFM 元素的 HTML 输出（含嵌套引用、任务列表、表格对齐、
    转义、标题 id 序号）；test-first + 盲测分离。

- id: W2
  title: HTML 文档包装 + github-markdown-css 资源加载
  file_path: Sources/PeekyKit/MarkdownHTMLRenderer.swift   # 与 W1 同文件（组装层）
  functions:
    - name: documentHTML(bodyHTML: String, css: String) -> String
      behavioral_contract: |
        组装完整文档：<!doctype html><html><head><meta charset utf-8>
        <meta name="viewport"><style>{css}</style><style>{包装：body.markdown-body 内边距/
        max-width、pre/table 横向滚动容器、图片 max-width:100%}</style></head>
        <body class="markdown-body">{bodyHTML}</body>（含极简 JS：scrollToHeading(n)）。纯字符串组装、可单测。
    - name: loadGithubMarkdownCSS() -> String
      behavioral_contract: |
        照 HighlightService 的多候选寻径从 Peeky_PeekyKit.bundle 读 github-markdown.css；
        找不到返回空串（样式降级不崩）。
  dependencies: [W1]
  reuse_candidates: 复用 HighlightService.loadBundleSource 的 bundle 寻径模式。
  acceptance: documentHTML 组装的结构化断言（含 markdown-body class、css 注入、body 注入）。

- id: W3
  title: WKWebView 集成到 PreviewWindowController（markdown 专用）
  file_path: Sources/PeekyKit/PreviewWindowController.swift
  functions:
    - name: markdown 渲染切到 WKWebView
      behavioral_contract: |
        新增一个 markdown 专用 WKWebView（与 scrollView/jsonOutlineView 同区叠放，仅 markdown
        显示、其它类型隐藏）；loadHTMLString(documentHTML, baseURL: nil)；外观跟随系统（不覆盖
        webview appearance，prefers-color-scheme 自动切浅深）；app 启动/首次预热一个共享实例；
        大纲项点击 → evaluateJavaScript scrollToHeading(index)；peeky:// line → 最近标题锚点；
        选中+复制走 WebView 原生（无需自定义）。非 markdown 路径与既有原生渲染一律不变。
      error_cases:
        - { condition: "CSS 资源缺失", behavior: "无样式裸 HTML，不崩" }
        - { condition: "超 8MB", behavior: "沿用大文件降级策略" }
  dependencies: [W1, W2]
  reuse_candidates: 复用既有 showJSONTree/showPlainText 的同区叠放显隐骨架、大纲侧栏点击回调、
    peeky:// 行定位入口。
  acceptance: markdown 经 WebView 呈现且像素级对齐 github（用户浅深两外观观感签字）；
    大纲跳转/行定位/选中复制可用；其它类型无回归（全量测试绿）。

- id: W4
  title: 清理原生 markdown 渲染死路径
  file_path: Sources/PeekyKit/MarkdownRenderer.swift, DropContainerView.swift, PreviewRenderer.swift
  functions:
    - name: 移除 WebView 落地后不再使用的原生 markdown body 渲染
      behavioral_contract: |
        WebView 路径验收通过后，移除仅服务原生 markdown body 的代码（GitHubMarkdownPalette、
        标题底线绘制、attributed body 构造等），保留 outline 抽取。不影响其它类型的原生渲染
        （代码/JSON 高亮、DropTextView 等）。
  dependencies: [W3]
  acceptance: 移除后全量测试绿、其它类型渲染无回归。
```

## Dependency Graph

```
W1 (MarkdownHTMLRenderer, AST→HTML) ─▶ W2 (HTML 包装 + CSS 加载) ─▶ W3 (WKWebView 集成) ─▶ W4 (清理原生死路径)
```
无环（DAG）。

## Execution Waves

- **Wave 1**：W1（AST→HTML，test-first 核心）
- **Wave 2**：W2（HTML 包装 + CSS 加载，可与 W1 尾部衔接）
- **Wave 3**：W3（WebView 集成，架构师直做，构建 + 用户观感验收）
- **Wave 4**：W4（WebView 验收通过后清理原生死路径）

## 验收模型

- **W1/W2 结构化测试**（test-first + 盲测分离）：断言 AST→HTML 各 GFM 元素输出、文档组装。
- **W3 观感终审**：构建 .app，用户在浅/深两外观核对 markdown 与 github 一致后签字。

## Status

Completed — WKWebView + 真 github-markdown-css 的 markdown 渲染已交付、用户实机验收通过（浅/深两外观、选中复制、大纲跳转、任务列表/表格/嵌套引用/标题底线像素级对齐 github）。W1/W2/W3/W4 全部完成：W4（原生 markdown 死路径清理，issue #17）已随本次收尾——`MarkdownRenderer` 仅保留 `outline(in:)`，`CodeBlockBackgroundLayoutManager` / `highlightMarkdownCodeBlocks` / attributed body / palette 全部移除，`PreviewRenderer` 的 markdown 分支合并到 raw 兜底；测试同步瘦身，全量 165 用例绿。后续跟踪进 issue：代码块语法高亮 → #16（仅知名语言时高亮）。
