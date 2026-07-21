# Feature: JSON/JSONL 查看器对齐 codebeautify（Ace code 视图）样板

## Overview
把 JSON/JSONL 渲染升级到用户给定样板（codebeautify.org/jsonviewer 左栏，即 Ace 编辑器 code 模式）的视觉与交互水准：语义分色、区分底色的行号 gutter、gutter 内折叠三角、折叠 chip 占位、缩进虚线导轨、底部 Ln/Col/选中字符数/文件大小状态栏、双击选中整个 element、monospaced 可选中文本。渲染形态保持原生 NSTextView + TextKit 1，配色全部经 `PeekyTheme` 语义色（换色只改 hex 常量）。样板截图存于 `/Users/hcazrej/.claude/image-cache/427ff2e6-afbe-45f3-89fb-e915bfed7f4e/1.png`–`6.png`。

## Intent Brief
- **Goal**：JSON/JSONL formatted 模式在样式与交互上对齐样板六图的全部特性（配色可用本 repo 自己的 palette）。
- **Motivation**：用户对现状渲染不满意多轮，给出可对齐的具体样板以消除"做成什么样"的歧义。
- **Known context**：现有管线 = `JSONFormatter` pretty-print → `JSONHighlighter` 可视区惰性分色 → `PreviewGutterView`(NSRulerView) 行号 → `PreviewWindowController` 编排；`PeekyTheme` 已承载 light/dark 语义色；像素级验收回路已建立（lldb 离屏渲染截图）。
- **Constraints**：只读查看器（一切变换只作用于显示态，文件零写入）；纯函数核心（新逻辑落无状态 enum 静态纯函数）；TextKit 1（gutter 依赖 NSLayoutManager）；性能预算 80MB/8MB/1.5M 不变，折叠与导轨绘制仅作用可视区；零第三方 SPM 依赖。
- **Non-goals**：repair-json（用户明确不要）；工具栏 sort/transform/undo-redo/compact 按钮（落 GitHub issues，本 plan 不实现）；与样板逐色对齐（用本 repo palette）；markdown/源码模式的行为变更。
- **Success criteria**：像素截图逐特征对照样板六图全部通过（折叠三角、跳号、chip、虚线导轨、状态栏、双击选区）；明暗两外观各过一遍；折叠态复制得到完整底层 JSON 文本；几万行 JSONL 冒烟不卡。
- **Assumptions / Unknowns**：见 Assumption Ledger。

## Alignment Gate
- **I will implement**：折叠（gutter 三角 + chip + 行号跳号）、缩进虚线导轨、底部状态栏（Ln/Col/选中数/size）、双击选中整 element、折叠态选择/复制映射回源文本、全部颜色入 `PeekyTheme`。
- **I will not implement**：repair-json；sort/transform/undo-redo/compact 工具栏按钮（已落 issues）；对样板的逐像素配色复刻。
- **Open assumptions**：下表 A1–A4。
- **Acceptance**：Success criteria 全项 + 全量测试与既有 220 用例全绿。

## Assumption Ledger
| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| A1 复制含折叠 chip 的选区时，剪贴板给出完整底层 JSON（Ace 同款语义） | high | medium | 默认执行 |
| A2 JSONL 折叠按每条记录独立生效（通用括号深度扫描天然支持），坏行无折叠区 | medium | medium | 默认执行，验收时用户复核 |
| A3 状态栏对所有 textView 类模式（JSON/JSONL/源码/文本）统一启用，成本相同且一致性更好 | medium | low | 默认执行 |
| A4 双击折叠 chip/元素 key 的选区 = 从 key 起引号到容器闭括号（含），不含尾逗号 | medium | low | 默认执行，验收时按样板微调 |

## Work-Unit Specs

```yaml
- id: F1
  title: 折叠结构索引（纯函数）
  file_path: Sources/PeekyKit/JSONFoldMap.swift   # 新文件
  functions:
    - name: JSONFoldMap.build
      inputs: [prettyText: String（JSONFormatter 输出）]
      outputs: JSONFoldMap { regions: [FoldRegion], lineDepths: [Int] }
      behavioral_contract: |
        单遍扫描 pretty-print 文本（复用 JSONHighlighter 词法级别的括号/引号识别，
        字符串字面量内的括号忽略）。FoldRegion { id, openLine, closeLine,
        innerCharRange, kind: object|array }，仅收 openLine < closeLine 的容器；
        lineDepths[i] = 第 i 行内容起点的缩进深度（2 空格 = 1 级）。JSONL 多顶层
        值天然支持（深度归零重启）。8MB 输入单遍完成，可后台线程调用。
      error_cases:
        - { condition: "括号不配对/坏行（JSONL invalid 行）", behavior: "跳过该未闭合区域，其余 region 正常产出，绝不抛错" }
  dependencies: []
  reuse_candidates: |
    JSONHighlighter 已有单遍 UTF-16 词法扫描骨架（字符串/转义处理）可参考其分支
    结构；JSONFormatter 的 lineStartLocations 已在 PreviewDisplayMetadata 存在，
    行表复用之，不重复计算。
  acceptance: F1 visible+hidden 全绿（含深嵌套、JSONL 多记录、坏行、8MB 级长文本用例）。

- id: F2
  title: 折叠态文本合成 + 双向坐标映射（纯函数）
  file_path: Sources/PeekyKit/JSONFoldComposer.swift   # 新文件
  functions:
    - name: JSONFoldComposer.compose
      inputs: [sourceText: String, foldMap: JSONFoldMap, collapsed: Set<FoldRegion.ID>]
      outputs: |
        FoldComposition { visibleText: String（折叠区替换为单字符占位 U+FFFC）,
        chipRanges: [NSRange]（占位在 visibleText 中的位置，UI 层贴 attachment）,
        visibleLineToSourceLine: [Int], visibleLineDepths: [Int],
        segments: [(visibleRange, sourceRange)]（单调段表） }
      behavioral_contract: |
        collapsed 为空时 visibleText == sourceText 且映射恒等。嵌套折叠：外层
        collapse 吞并内层。segments 支持双向换算：visible→source 用于复制/状态栏
        行列，source→visible 用于 JSONHighlighter token 上色与 scrollToLine。
        提供工具函数 sourceRange(forVisible:) / visibleRange(forSource:)。
      error_cases:
        - { condition: "collapsed 含 foldMap 中已不存在的 id", behavior: "忽略该 id，其余正常" }
  dependencies: [F1]
  reuse_candidates: 无现成实现；映射段表为新逻辑。
  acceptance: F2 visible+hidden 全绿（恒等、单折、嵌套折、跨 chip 选区映射、边界字符）。

- id: F3
  title: PeekyTheme 新语义色
  file_path: Sources/PeekyKit/PeekyTheme.swift
  functions:
    - name: ThemeColor 扩展
      inputs: []
      outputs: 新 case：indentGuide / foldChipBackground / foldChipBorder / foldChipGlyph / statusBarBackground / statusBarText / gutterDisclosure
      behavioral_contract: |
        light(GitHub Light)/dark(VSC Dark Modern) 两套 hex 常量各补齐；用途注释
        写清对应样板元素。既有 case 与取值零变动。
      error_cases: []
  dependencies: []
  reuse_candidates: PeekyTheme 既有 ThemeColor × hex 常量表模式，照抄结构。
  acceptance: peekyTheme 单元 visible+hidden 全绿（新增色两外观可解析、亮度方向断言）。

- id: F4
  title: gutter 折叠三角 + 点击命中 + 跳号行号
  file_path: Sources/PeekyKit/PreviewGutterView.swift
  functions:
    - name: 配置扩展与绘制
      inputs: [disclosures: [Int: DisclosureState]（visibleLine → expanded|collapsed）, visibleLineToSourceLine: [Int]]
      outputs: 绘制 + onToggleFold: (visibleLine) -> Void 回调
      behavioral_contract: |
        行号取 visibleLineToSourceLine 映射值（折叠后跳号如 12→181）。有
        disclosure 的行在行号左侧画三角（展开 ▾ / 折叠 ▸，色 gutterDisclosure），
        mouseDown 命中三角区触发 onToggleFold；命中区外维持既有选择行为。
        行号右对齐与 5pt 边距、分隔线绘制维持现状。
      error_cases:
        - { condition: "点击无 disclosure 的行", behavior: "无操作" }
  dependencies: [F2, F3]
  reuse_candidates: 既有 drawHashMarksAndLabels 骨架就地扩展。
  acceptance: 构建通过 + 像素截图可见三角两态 + lldb 触发 onToggleFold 后行号跳号正确。

- id: F5
  title: 正文视图：缩进虚线导轨 + 折叠 chip + 双击选区/复制语义
  file_path: Sources/PeekyKit/DropContainerView.swift   # DropTextView 所在文件
  functions:
    - name: 导轨与 chip 绘制、选择语义
      inputs: [visibleLineDepths, chipRanges, segments（经 controller 注入的展示配置）]
      outputs: drawBackground 导轨；chip attachment cell；selectionRange/copy 覆写
      behavioral_contract: |
        drawBackground(in:)：仅对可视区行片段，按该行 depth 在 x = 文本起点 +
        k×缩进步宽（k=1..depth-1）画 1px 虚线（色 indentGuide），深度取
        visibleLineDepths。chip：U+FFFC 处贴自绘 attachment cell（圆角矩形 +
        双向箭头字形，色 foldChip*）。双击 chip 或元素 key：选区扩展为该
        FoldRegion 全范围（A4 语义）。copy(_:)：选区经 segments 映射回源文本，
        含 chip 的选区展开为完整底层 JSON。
      error_cases:
        - { condition: "展示配置为空（非 JSON 模式）", behavior: "全部行为退化为既有 NSTextView 默认" }
  dependencies: [F2, F3]
  reuse_candidates: DropTextView 已有 overlayConfiguration 注入模式，照该通道扩展。
  acceptance: 构建通过 + 像素截图导轨/chip 呈现 + lldb 设选区后 copy 内容断言等于底层源文本。

- id: F6
  title: 控制器接线：fold 状态、状态栏、高亮坐标适配
  file_path: Sources/PeekyKit/PreviewWindowController.swift
  functions:
    - name: fold 状态与刷新管线
      inputs: []
      outputs: |
        collapsed 集合持有于 controller（UI 状态唯一住所）；toggle → 后台
        compose → 主线程换文本 + gutter/导轨配置刷新 + 滚动位置保持；
        JSONHighlighter 上色改为：可见 visible 范围经 segments 映射到 source
        分词，token 范围映射回 visible 后 setTemporaryAttributes。
    - name: 底部状态栏
      inputs: []
      outputs: |
        编辑器区底部常驻条：左侧 "Ln X, Col Y"（源坐标）+ 选中时 "N characters
        selected"（源字符数）；右侧 "size: X KB"（文档字节数）。监听
        NSTextViewDidChangeSelection。色走 statusBar*。textView 类模式统一
        启用（A3），markdown WebView 模式隐藏。
      error_cases:
        - { condition: "折叠后 scrollToLine 目标行位于折叠区内", behavior: "滚动到该区 openLine" }
  dependencies: [F1, F2, F3, F4, F5]
  reuse_candidates: applyVisibleJSONHighlighting、applyDisplayMetadata 既有通道就地扩展。
  acceptance: 全量测试绿 + 折叠/展开/滚动/选中全链路 lldb 冒烟通过。

- id: F7
  title: 集成像素验收（明暗两态 × 样板六图特征逐项对照）
  file_path: —（验收单元，架构师亲自执行）
  functions: []
  dependencies: [F6]
  reuse_candidates: lldb 离屏渲染截图回路（memory: background-gui-smoke）。
  acceptance: |
    settings.json 与几万行 JSONL 各一轮：① 分色 ② gutter 底色区分+三角 ③ 折叠
    12→181 跳号 + chip ④ 双击选区字符数断言 ⑤ 导轨虚线 ⑥ 状态栏 Ln/Col/size；
    light/dark 各一遍；性能预算内不卡；截图存 job tmp 供用户复核。
```

## Dependency Graph
```
F1 ──► F2 ──► F4 ──┐
        │          ├──► F6 ──► F7
        └────► F5 ──┘
F3 ──────────► F4, F5
```

## Execution Waves
- **Wave 1（并行）**：F1、F3
- **Wave 2**：F2（dep F1）
- **Wave 3（并行，不同文件）**：F4、F5（dep F2、F3）
- **Wave 4**：F6（dep 全部）
- **Wave 5**：F7 集成验收
- 交付时更新 PROJECT.md（JSON/JSONL 功能行与关键决策）、PATTERNS.md（如新增展示配置注入范式）。

## Status
Awaiting user approval（BACKLOG 已摆出，等待批准后派发）
