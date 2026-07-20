# BACKLOG

## 执行中 · Plan: markdown-render-redesign   (→ .claude/plans/markdown-render-redesign.md)

Markdown 渲染重构：GFM · 高保真对齐 github-markdown-css（light+dark）· 单 Preview · 原生选中复制。
验收含结构化测试全绿 + 用户对观感的「好看」终审签字。

### Wave 1 — 无依赖 · 可并行（三文件互不相同）

- [ ] T1  GitHubMarkdownPalette + MarkdownRenderer 色彩/字号高保真对齐
        file: Sources/PeekyKit/MarkdownRenderer.swift   deps: —
        spec: 新增 GitHubMarkdownPalette(light+dark)；标题字号补 h5/h6、字重 600；
              链接/行内码底/代码块底/引用文字·条/表格边框·斑马/hr/h1h2 底边线全取 palette 精确色
        验收: light+dark 下各级结构化属性断言命中 github-markdown-css 目标值

- [ ] T2  PreviewRenderer 收敛——markdown 恒 formatted
        file: Sources/PeekyKit/PreviewRenderer.swift   deps: —
        spec: markdown 分支恒 formatted（8MB 超限仍安全回落 raw 兜底）；markdown usesDarkModernTheme 恒 false
        验收: 任意 mode 入参下 markdown 返回 formatted 富文本，tests 全绿

- [ ] T3  PreviewWindowController——单 Preview + 可见选区 + 复制选中 + github 外观
        file: Sources/PeekyKit/PreviewWindowController.swift   deps: —
        spec: 选区高亮改可见；行定位改瞬时高亮（不占选区外观）；markdown 隐藏 Format/Raw 档；
              复制菜单加「复制选中」(空选区回落全文)；依 appearance 应用 github light/dark 画布色
        验收: 无 Format/Raw 档 + 选区可见 + 复制选中生效 + light/dark 画布色正确

### Wave 2 — deps: T1

- [ ] T4  DropContainerView——代码块/行内码背景填充保真
        file: Sources/PeekyKit/DropContainerView.swift   deps: T1
        spec: 块级代码背景取 palette.codeBlockBg 圆角 6；行内码胶囊取 palette.inlineCodeBg 圆角 6 紧致包裹
        验收: light/dark 下代码块底/行内码胶囊与 palette 一致，tests + 观感通过
