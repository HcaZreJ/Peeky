# BACKLOG

## 执行中 · Plan: markdown-render-redesign   (→ .claude/plans/markdown-render-redesign.md)

Markdown 渲染重构：GFM · 高保真对齐 github-markdown-css（light+dark）· 单 Preview · 原生选中复制。
验收含结构化测试全绿 + 用户对观感的「好看」终审签字。

### Wave 1 — 已完成
- [x] T1  GitHubMarkdownPalette + MarkdownRenderer 色彩/字号对齐   （hidden 41/41，50/50 全绿）
- [x] T2  PreviewRenderer——markdown 恒 formatted   （hidden 15/15，18/18 全绿）

### Wave 2 — 进行中
- [ ] T3  PreviewWindowController——单 Preview + 可见选区 + 复制选中 + github 画布
        file: Sources/PeekyKit/PreviewWindowController.swift   deps: T1
        spec: markdown 隐藏 Format/Raw 档；选区高亮改可见（github 选区色）；大纲/peeky:// 行定位
              与选区解耦（导航改瞬时闪烁 showFindIndicator，不占选区、不再现失焦灰带）；
              复制菜单加「复制选中」(纯逻辑 selectionCopyPayload：空选区回落全文)；
              markdown 画布背景取 GitHubMarkdownPalette.canvas（浅 #ffffff / 深 #0d1117）
        验收: 无 Format/Raw 档 + 拖拽选区可见可 ⌘C 复制 + 复制选中生效 + 导航不留灰带 +
              浅/深画布色正确；按 DEVFLOW 手动验收清单两外观各过一遍 + 用户观感签字

### 暂缓（观感终审时定夺）
- [ ] T4  代码块方角→6px 圆角（纯绘制细节）
        note: 颜色已由 T1 覆盖、行内码圆角胶囊既有；此项风险/收益由用户看实机后拍板
