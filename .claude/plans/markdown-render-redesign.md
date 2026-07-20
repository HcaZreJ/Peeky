# Feature: Markdown 渲染重构（GFM · 高保真对齐 github-markdown-css · 单 Preview · 原生选中复制）

## Overview

把 markdown 预览从「Preview/Raw 双档 + 自适应系统色的近似排版」收敛成**单一 Preview**：一个原生 `NSTextView` 渲染的 `NSAttributedString`，视觉高保真对齐 github-markdown-css（light + dark 两套调色板），文本可见选中并原生 `⌘C` 复制。范围只做 **GFM**；GLFM 专属元素在 issue #14 逐项跟进。

痛点：现状排版用自适应系统色做近似、观感不达 GitHub；Preview/Raw 双档冗余；选区高亮被设成透明导致「看起来选不中」、复制菜单只会整文件复制。

## Intent Brief

- **Goal**：markdown 预览「好看（高保真复刻 github-markdown-css）+ 启动快」，单视图，能原生选中并复制任意片段。
- **Motivation**：现渲染观感差、可读性低；用户只要一个干净、像 GitHub、能选能拷的预览。
- **Known context**：渲染面是 `DropTextView: NSTextView`（TextKit1，喂 `NSAttributedString`，零 HTML/WebView）。`MarkdownRenderer` 用 swift-markdown AST + 自定义 `MarkupVisitor` 手搓 attributed string，已覆盖 GFM 主要元素（真表格 `NSTextTable`、任务列表、代码围栏 + shiki 高亮、引用、删除线、链接、自动链接、标题大纲）。排版常量标注为「GitHub Primer derived」。
- **Constraints**：repo 铁律——只读查看器、纯函数核心、零第三方 SPM 依赖默认、性能预算（读取 80MB / 富格式化 8MB / 高亮 1.5M UTF-16）、主线程纪律。启动快是硬约束。
- **Non-goals**：不引入 WKWebView/HTML/CSS 运行时；不做 GLFM 专属元素（→ issue #14）；不动 JSON/JSONL 的 tree/text 渲染（另案）；不改源码文件（`FileKind.text`）因扩展名命中 shiki 而变暗的既有行为。
- **Success criteria**：① markdown 只有单一 Preview；② 拖拽有可见选区高亮且 `⌘C` 复制选中片段、复制菜单含「复制选中」；③ 结构化属性断言全部命中 github-markdown-css 目标值（见 Work-Unit Specs 的色值/字号表）；④ light 与 dark 系统外观下各自呈现对应 github 调色板；⑤ 用户对整体观感做「好看」终审签字。
- **Assumptions**：见 Assumption Ledger。
- **Unknowns**：像素级天花板——原生 attributed string 与真 CSS 之间存在无法完全弥合的细节（圆角、精确内边距渲染），用户接受先看原生效果再定是否局部补强。

## Alignment Gate

- **I will implement**：单 Preview（移除 markdown 的 Format/Raw 档）；可见选区高亮 + 复制选中；`MarkdownRenderer` 全量色彩/字号对齐 github-markdown-css（light+dark 调色板）；代码块/行内码背景填充保真。
- **I will not implement**：WebView/HTML 路线；GLFM 元素；JSON/JSONL 视图变更；源码文件暗色主题逻辑变更。
- **Open assumptions**：见 Ledger 中 status 非 accepted 的行。
- **Acceptance criteria**：见 Success criteria；结构化测试全绿 + 用户观感签字。

## Assumption Ledger

| Assumption | Confidence | Impact if Wrong | Status |
|---|---|---|---|
| 「好看」=高保真复刻 github-markdown-css，可接受原生非像素级的保真上限 | high | high | 用户已确认 |
| 启动快为硬约束 → 采原生 NSTextView 路线而非 WebView | high | high | 用户已确认（工作量非考量、可拆分） |
| markdown 需同时忠实 light+dark（github-markdown-css 两套皆复刻），避免暗色系统下白色孤岛 | medium | medium | 架构师默认，随终审签字校验 |
| 纯 `⌘C` 未被复制菜单快捷键占用，原生 copy: 即复制选区 | high | medium | 代码已证实（Copy All 为 ⌘⌥C） |
| peeky:// 行定位反馈可改用瞬时高亮，无需再靠 setSelectedRange 占用选区外观 | medium | medium | 架构师默认，T3 落地校验 |

## Work-Unit Specs

色值目标（github-markdown-css，`RRGGBBAA` 中末两位为 alpha）：

| 语义 | light | dark |
|---|---|---|
| 正文/前景 | `#1f2328` | `#f0f6fc` |
| 链接 | `#0969da` | `#4493f8` |
| 行内码底 | `#818b981f` | `#656c7633` |
| 代码块底 | `#f6f8fa` | `#151b23` |
| 引用文字 | `#59636e` | `#9198a1` |
| 引用条/表格边框/hr | `#d1d9e0` | `#3d444d` |
| 表格斑马行底 | `#f6f8fa` | `#151b23` |
| h1/h2 底边线 | `#d1d9e0b3` | `#3d444db3` |
| 画布背景 | `#ffffff` | `#0d1117` |

几何目标（github-markdown-css 基线，16px 基准）：h1 32/h2 24/h3 20/h4 16/h5 14/h6 13.6，字重 600，标题上距 24 下距 16、行高 1.25；正文行高 1.5、段后距 16；行内码 padding .2em/.4em、圆角 6、字号 85%；代码块 padding 16、圆角 6、行高 1.45、字号 85%；引用左边框 4pt、内边距左 16；列表左缩进 32（2em）；表格单元 padding 6/13、边框 1pt；hr 高 4pt。

```yaml
- id: T1
  title: GitHubMarkdownPalette + MarkdownRenderer 色彩/字号高保真对齐
  file_path: Sources/PeekyKit/MarkdownRenderer.swift
  functions:
    - name: GitHubMarkdownPalette (新增 internal enum 命名空间，色彩单一真相)
      inputs: []
      outputs: 一组语义化「动态 NSColor」（text/link/inlineCodeBg/codeBlockBg/quoteText/border/tableZebra/headingRule/canvas）
      behavioral_contract: |
        每个语义色以 NSColor(name:dynamicProvider:) 构造为动态色：dark 外观解析为上表 dark 精确
        十六进制（含 alpha）、其余外观解析为 light 精确十六进制。render(_:) 签名不变，单次渲染的
        attributedText 在浅/深两外观下各自正确解析、无需重渲染。T3/T4 消费同一 palette。
      error_cases:
        - { condition: "未知/混合外观", behavior: "解析为 light 兜底" }
    - name: bodyAttributes / headingAttributes / quoteAttributes / listAttributes / codeBlockAttributes / inlineCodeAttributes / linkAttributes / 表格样式 helper / hr
      inputs: [depth/level/appearance 依既有签名]
      outputs: 依既有签名的属性字典，颜色改取自 GitHubMarkdownPalette，字号/间距校正到几何目标
      behavioral_contract: |
        headingFontSize 补 h5=14、h6=13.6；h1/h2 底边线色改用 palette.headingRule；
        引用文字改 palette.quoteText、引用条改 palette.border；行内码底改 palette.inlineCodeBg、
        圆角 6、字号 85%；代码块底改 palette.codeBlockBg；链接改 palette.link；
        表格边框/斑马改 palette.border/palette.tableZebra、单元 padding 6/13；hr 用 palette.border 高 4pt。
        既有单侧段距模型（只用 trailing paragraphSpacing 表达块间距、headings 例外携 paragraphSpacingBefore）保持不变。
      error_cases:
        - { condition: "level>6 或 <1", behavior: "钳到 h6/h1 尺寸" }
  dependencies: []
  reuse_candidates: |
    复用现有 MarkupVisitor 全部访问方法与 NSTextTable 表格构造；仅替换颜色来源与字号常量，
    新增 GitHubMarkdownPalette 作为唯一色彩出处。不新增依赖。
  acceptance: |
    结构化测试断言：各级标题字号、字重 600、链接色 #0969da/#4493f8、代码块底、行内码底、
    引用文字/条、表格边框/斑马、hr、h1/h2 底边线，在 light 与 dark appearance 下各命中目标值。

- id: T2
  title: PreviewRenderer 收敛——markdown 恒 formatted
  file_path: Sources/PeekyKit/PreviewRenderer.swift
  functions:
    - name: render(document:mode:)
      inputs: [document, mode]
      outputs: RenderedPreview
      behavioral_contract: |
        markdown 分支恒走 formatted（MarkdownRenderer.renderWithOutline），不再因传入 mode=.raw
        而产出 raw 文本；readBytes 超 richFormatLimit(8MB) 时仍安全回落到 raw 文本作为兜底。
        usesDarkModernTheme 对 markdown 恒 false（markdown 走自身 github 调色板，不套 DarkModernTheme）。
      error_cases:
        - { condition: "文档超 8MB", behavior: "回落 raw 文本 + 计算 outline，不崩" }
  dependencies: []
  reuse_candidates: 复用既有 dispatch 与 richFormatLimit 兜底；仅去掉 markdown 的用户级 raw 分档。
  acceptance: markdown 文档在任意 mode 入参下都返回 formatted 富文本（8MB 以内），tests 全绿。

- id: T3
  title: PreviewWindowController——单 Preview + 可见选区 + 复制选中 + github 外观应用
  file_path: Sources/PeekyKit/PreviewWindowController.swift
  functions:
    - name: setupTextView / applyEditorTheme / render 相关
      inputs: []
      outputs: void（UI 副作用）
      behavioral_contract: |
        ① selectedTextAttributes 改为可见高亮（选中背景取系统 selectedTextBackgroundColor 或
        github 选区色），使拖拽选区可见。
        ② peeky:// / 大纲行定位改用瞬时高亮（临时 .backgroundColor 属性，短延时后自动清除）替代
        setSelectedRange 占用选区外观，两者互不干扰。
        ③ markdown 时隐藏 Format/Raw 的 modeControl（单 Preview）；markdown 恒以 formatted 渲染。
        ④ 依当前 effectiveAppearance 对 markdown 应用 github light/dark 画布背景与前景，
        与 T1 palette 一致（暗色系统 → dark 画布，不出现白色孤岛）。
      error_cases:
        - { condition: "无 activeTab", behavior: "静默不作为" }
    - name: 复制选中 menu item + copySelection()
      inputs: []
      outputs: 写入 NSPasteboard
      behavioral_contract: |
        复制菜单新增「复制选中」项：复制 textView 当前选区字符串；选区为空时回落复制全文。
        纯 ⌘C 仍由 NSTextView 原生 copy: 处理（复制选区），不被菜单快捷键抢占。
      error_cases:
        - { condition: "选区为空", behavior: "回落 copyAllText 语义" }
  dependencies: [T1]
  reuse_candidates: |
    复用既有 copyMenu 结构与 copyAllText；复用 applyEditorTheme 的 appearance 切换骨架；
    modeControl 既有 for-markdown 标签逻辑（:1048-1049）改为隐藏。
  acceptance: |
    markdown 无 Format/Raw 档；选区高亮可见（selectedTextAttributes 非 clear）；
    「复制选中」写入选区字符串、空选区回落全文；light/dark 各应用对应 github 画布色。

- id: T4
  title: DropContainerView——代码块/行内码背景填充保真
  file_path: Sources/PeekyKit/DropContainerView.swift
  functions:
    - name: CodeBlockBackgroundLayoutManager 背景绘制
      inputs: [attributed runs 携 codeBlockBackgroundAttributeKey / 行内码 key]
      outputs: 绘制块级/行内码背景
      behavioral_contract: |
        块级代码背景填充色取 T1 palette.codeBlockBg（light #f6f8fa / dark #151b23），
        圆角 6、覆盖块的内边距区域；行内码胶囊底色取 palette.inlineCodeBg、圆角 6，
        沿字形紧致包裹。表格单元内的装饰绘制放行既有行为不回退。
      error_cases:
        - { condition: "无背景 key 的 run", behavior: "不绘制" }
  dependencies: [T1]
  reuse_candidates: 复用现有 CodeBlockBackgroundLayoutManager 绘制管线；仅统一取色到 palette。
  acceptance: 代码块底色/圆角、行内码胶囊在 light/dark 下与 palette 一致，tests + 观感通过。
```

## Dependency Graph

```
T1 (MarkdownRenderer, 定义 GitHubMarkdownPalette) ─┬─▶ T3 (PreviewWindowController, 用 palette.canvas)
                                                   └─▶ T4 (DropContainerView, 用 palette 代码/行内码色)
T2 (PreviewRenderer) — 独立
```
无环（DAG）。T3/T4 均消费 T1 定义的 palette，故排在 T1 之后。

## Execution Waves

- **Wave 1（并行，文件互不相同）**：T1 · T2
- **Wave 2（并行，文件互不相同，均 deps T1 的 palette）**：T3 · T4

各波内同文件不并行（四个单元分属四个不同文件，天然满足）。

## 验收模型

- **结构化测试**（test-first + 盲测分离）：断言 attributed string 的字号/字重/颜色/段距与 selection、copy 行为命中上表目标值；light 与 dark appearance 分别覆盖。
- **观感终审**：结构测试全绿后，构建并把 markdown 预览实际效果交用户做「好看」签字，未签字前不视为完成。

## Status

In Progress — 待用户批准 BACKLOG 后进入 test-first 派发。
