# Feature: 预览窗口工具栏与文件 tab 信息层级重构

## Overview

预览窗口顶栏 4 个 icon button 混杂了两种语义层级（当前文件动作 vs. 打开新文件到 app），Copy 视觉承诺"点=复制"实为"点=开菜单"，Reveal 用了搜索图标，line wrap 与"动作"不同类。左侧 Open tab 的 close X 因 rowStack pack + 行高 ≥46 + opacity 跨状态漂移导致跨行位置不稳、无法定点连关，且缺 Close All 一键入口。

本 plan 以 interface-design skill 的三步流程 + 8 条硬规则为唯一决策依据，重构顶栏与 tab list 使信息层级清晰、组件隐喻贴合、同级同装。

## Intent Brief

- **Goal**：预览窗口顶栏与左侧 Open tab list 满足 skill §0 总纲——每个视觉差异必须编码一个信息差异；违反 §1 硬规则的所有点全部修复。
- **Motivation**：用户实测反馈——Copy options 用户猜不到、Reveal 图标错认为搜索、Open 与当前文件动作混同层级、close X 视觉不齐、多文件难以连关。
- **Known context**：Peeky 是 macOS 原生只读文件查看器；PATTERNS.md 规定 UI 状态只住 `PreviewWindowController`；AppKit 视图/控制器层走"构建 + 冒烟清单验收"（不走 test-first）；empty state 的 Open File 按钮是全 app 唯一绿色强调色 CTA。
- **Constraints**：零第三方 SPM 依赖；性能预算（80MB / 8MB / 1.5M）不动；主线程纪律；顶栏保持"只读查看器"定位（不引入编辑动作）。
- **Non-goals**：Copy 菜单条目行为不变（仍是 6 项复制变体 + Open in Editor）；主菜单栏不动；ModeControl 的 "Format | Raw" 语义与显隐条件不动；键盘快捷键（⌘O ⇧⌘C 等）保持。
- **Success criteria**：
  - 顶栏仅承载"当前预览文件的动作/视图切换"；无 app-level 入口混入
  - Copy 按钮外观自解释——一眼可辨"能一步复制"和"能展开选项"
  - Reveal 图标不与"搜索"或"打开新文件"隐喻冲突
  - Line wrap 仍可访问但不占主动作栏视觉预算
  - 侧栏 Open tab 的所有 close X 跨行像素级同 x/y、同 opacity；tabs ≥2 时提供 Close All 入口
  - skill §2 单屏自检 7 条全过
- **Assumptions**（见 Ledger）
- **Unknowns**：无（所有设计决策由 skill 原则闭环决出，见 §Design Decisions）

## Alignment Gate

- **I will implement**：
  - 顶栏 Open 按钮移除（依赖既有 ⌘O / empty state CTA / 侧栏 Open tab / drag-drop / Finder Open With 承接）
  - 顶栏 Copy 改 split-button（主区点击=Copy All，chevron 区展开菜单）
  - 顶栏 Reveal 图标改 SF Symbol `folder`
  - 顶栏新增 `ellipsis.circle` overflow 菜单，把 Wrap Lines 移入（原顶栏 wrap 图标按钮删除）
  - modeControl 与右侧动作按钮之间加更大组间距分隔为两组
  - `FileTabView` 的 close 按钮从 rowStack 剥离，硬约束到 view.trailingAnchor / centerY；行高改 `equalToConstant: 46`；close opacity 恒 1.0（不再随 hover/selected 变化）
  - Open tab 顶部新增 Close All 灰字按钮（tabs.count ≥ 2 时可见）
- **I will not implement**：
  - Copy 菜单条目集合调整（保持既有 6 项复制变体 + Open in Editor）
  - 顶栏其它区域布局（title/metadata 灰字层保持不动）
  - PROJECT.md 已完成的两大渲染重构相关任何代码
  - 应用主菜单栏与快捷键
- **Open assumptions**：见 Ledger `Status ≠ resolved` 行
- **Acceptance criteria**：
  1. 空态：工具栏只有 "Peeky" 标题（无 icon 按钮），Open File 主按钮仍在中央（绿色强调色）
  2. 已加载文件：工具栏右侧从左到右 = `[modeControl（如适用）] · gap · [Copy▼] [Reveal folder] [⋯]`
  3. Copy 主按钮区点击 = 立即复制全文；chevron 区点击 = 展开原六项菜单 + Open in Editor
  4. Reveal 按钮 hover tooltip = "Reveal in Finder"，图标 = folder；点击 = `NSWorkspace.activateFileViewerSelecting`
  5. `⋯` 菜单当前只 "Wrap Lines"（checkable，反映当前 wrapsLines 状态）；勾选切换即刻生效
  6. Open tab section：tabs 数 ≥ 2 时顶部显示 "Close All"（次要样式，右对齐）；点击关全部 tab；tabs ≤ 1 时该按钮隐藏
  7. 打开 3+ 个文件后，鼠标钉在同一屏幕点连点，可顺序关掉所有 tab
  8. skill §2 单屏自检逐条通过（见 §Self-check）

## Assumption Ledger

| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| Line wrap 有真实使用价值（长行 CSV/log/minified raw）值得保留而非删除 | medium | low | 保留成本零；即使无人用也不占主视觉预算，风险低 → accepted |
| SF Symbol `folder` 与 Finder 隐喻贴合，用户不会与"打开新文件"混淆 | high | low | Open 按钮同步移除，无同屏冲突；folder 是 Finder 的通用视觉隐喻 → accepted |
| Empty state Open File 主按钮 + ⌘O + 侧栏 Open tab + drag-drop + Finder Open With 已足够替代顶栏 Open 按钮 | high | medium | 五种入口皆在，冗余度足够；若用户反馈丢失，回退成本 = 加回一个按钮 → accepted with fallback |
| macOS 原生 `NSButton` 无内建 split-button；需以 NSSegmentedControl（2 段）或 NSButton + trailing NSPopUpButton 组合手实现 | high | medium | 用 2 段 NSSegmentedControl（segment 0 = icon 主动作，segment 1 = chevron 弹菜单）承载，避免自绘 → accepted |
| Close X 剥离到直接约束后仍能正确响应 hover/click 事件、不被父 view 拦截 | high | high | AppKit 事件路由按 hit test 递归，直接子 view 有效；已在既有代码验证过 close 事件流 → accepted |

## Design Decisions（skill 原则应用）

### D1 · 顶栏移除 Open 按钮

**违反规则识别**：顶栏 `[wrap, copy, reveal, open]` 是视觉等价的 icon button 并列组。找共同总体名词：`wrap` = 视图选项；`copy` = 复制动作；`reveal` = 在 Finder 显示当前文件位置；`open` = 打开新文件到 app。前三者共享"作用于当前预览文件"总体；`open` 是"打开新文件到 app"（app-level）。**违反 §1.3 并列即同级**——同一并列组必须能给出唯一共同总体名词。

**决策**：Open 按钮从顶栏移除。app-level 打开入口通过既有五路承接：⌘O 快捷键、empty state Open File 主按钮、侧栏 Open tab（复用最近打开文件列表）、drag-drop、Finder Open With。移除后顶栏并列组的共同总体名词收敛为"当前预览文件的动作/视图切换"。

### D2 · Copy 改 split-button

**违反规则识别**：当前 Copy 是 icon-only NSButton，视觉与 Reveal / Open 完全同装（`§1.4 同级同装`）。点击行为却是 popUpMenu（`showCopyMenu`），其余同装按钮是即时动作。**违反 §1.8 组件隐喻贴合**——视觉承诺"点=复制"，行为是"点=开菜单"，读者先按旧隐喻理解、点了才纠错。

**决策**：Copy 改 2 段 NSSegmentedControl：
- Segment 0：`doc.on.doc` 图标，`.momentary` tracking，action = Copy All
- Segment 1：`chevron.down` 图标，`.momentary` tracking，action = popUp copyMenu

依据：这个视觉差异（chevron 存在与否）**编码了信息差异**——"这一半含菜单，那一半是主动作"——符合 §0 总纲。宽度约束：主段 30，chevron 段 18。总宽 48，仍紧凑。

菜单内容不变（六项复制变体 + Open in Editor 分隔组），继续与 `Edit` 主菜单共用。

### D3 · Reveal 图标改 folder

**违反规则识别**：`magnifyingglass` 是"搜索"的通用隐喻（跨 macOS/iOS 系统 UI 一致）。用于"Reveal in Finder"违反 §1.8——读者按搜索理解，点了发现是文件定位。

**决策**：改为 SF Symbol `folder`。Open 按钮已移除（D1），folder 不再与"打开新文件"隐喻冲突。folder = Finder 里承载文件的容器隐喻，语义贴合。

### D4 · Line wrap 移入 overflow 菜单

**违反规则识别**：顶栏动作组的共同总体名词是"当前文件的动作/位置操作"（Copy/Reveal 皆是）。line wrap 是"如何显示当前文件"的视图选项，与 modeControl 才同类。塞在动作组里**违反 §1.3**。

**决策**：删除顶栏 wrapButton；在动作组末尾加 `ellipsis.circle` overflow 按钮，其菜单含单项 `Wrap Lines`（checkable，反映 `wrapsLines`）。

- 依据：§1.6 并列数 ≤4。移除 wrap、加入 overflow 后，动作组从 4 项降为 3 项 icon（Copy split-button 作为一个组件，即使 2 段也计一项）+ 1 项 overflow = 4 项，处于阈值。
- 不删完全保留：line wrap 对长行 log / minified raw / 宽 CSV 有真实使用价值；overflow 让功能可发现但不占主视觉预算。
- 未来其他视图设置可扩展进同一 overflow 菜单，不再新增顶栏按钮。

### D5 · modeControl 与动作组之间加组间距

**违反规则识别**：当前 controls stack 均匀间距（默认 8），modeControl 与 icon buttons 视觉粘合。它们是两个不同并列组——**违反 §1.7 分组靠间距**（组内间距应显著小于组间间距）。

**决策**：将 controls 从单一 NSStackView 改为两个子 stack，中间隔 20pt：
- Group A：`[modeControl]` （视图模式段控件；隐藏条件保留：JSON 家族 / 空态 / 加载中 → hidden）
- Group B：`[Copy split-button, Reveal, overflow]` （当前文件动作 + 视图设置入口）

组内 spacing = 8，组间 spacing = 20（≥1.5× 组内间距）。当 Group A 隐藏时不留视觉洞（用 stack 的 isHidden 自动折叠布局）。

### D6 · Close X 硬约束到 FileTabView.trailingAnchor

**违反规则识别**：`§1.4 同级同装`——同一并列组内所有 tab card 的 close X 应视觉完全一致（含位置）。当前 close 靠 rowStack pack 布局，行高 `≥46` 允许浮动，理论上跨行 y 稳定，但 opacity 55%↔100% 随 hover/selected 变化——**opacity 差异不编码任何信息**（不区分"能关/不能关"，任何 tab 都能关），是设计熵。用户报告"多文件时定点连点关不掉全部"，佐证跨行视觉不稳。

**决策**：
- Close 按钮从 rowStack 中拆出，直接约束：`trailingAnchor = FileTabView.trailingAnchor - 8`，`centerYAnchor = FileTabView.centerYAnchor`，尺寸 20×20。
- textStack.trailing = closeButton.leadingAnchor - 8（textStack 让位给 close）。
- 行高：`heightAnchor.constraint(equalToConstant: 46)`（不再 `≥46`），跨行像素级同 y。tabStack.spacing = 4 已固定 → 每行位置 = 46 + 4，close X 世界坐标严格线性。
- `updateAppearance`：close 的 `alphaValue` 恒 1.0（移除随 hover/selected 变化的逻辑）；contentTintColor 保持 secondaryLabelColor。

### D7 · Open tab 顶部加 Close All

**违反规则识别**：Close All 不是 tab card 的并列成员（成员共同总体名词 = "已打开文件"）。放在 tab card 列表里当第一项会**违反 §1.3**。但功能需求真实：多 tab 时用户需要一键清空。

**决策**：Close All 单独一行放在 sidebarSectionControl 与 tabStack 之间。
- 视觉：文字按钮（无 icon、无 subtitle），字号 11pt，`secondaryLabelColor`，右对齐——归入"元信息/次级动作"层（§1.5 灰字放元信息层）。
- 显隐：`tabs.count ≥ 2` 时显示；`≤ 1` 时隐藏（isHidden 折叠布局，无空洞）。
- 位置：与 tabStack 相同 leading/trailing padding，与首个 tab card 间距 8。
- 组间距分隔：Close All 与 tab card 组之间视觉靠 8pt 空白 + 字号/字色差异（元信息层 vs. 内容层）明确分组，不属于同一并列组。

## Self-check（skill §2 单屏自检推演）

### Preview window（file loaded state）

1. **灰度眯眼**：焦点应在预览区文件内容本体（占据画面大部分面积）；工具栏 icon 全 secondaryLabel 灰调、不抢焦点 ✓
2. **一句话概括**：本屏展示当前文件 + 允许对当前文件做动作/切换视图。无"和"连接两件事 ✓
3. **并列组**：
   - 右侧动作组：`[Copy▼, Reveal, ⋯]`，共同总体名词 = "当前文件的动作/视图设置"，计数 3 ≤ 4，组内同装（icon-only NSButton） ✓（Copy 有 chevron 编码信息差异，非同装破坏）
   - modeControl 单独一组（segmented 组件形态与 icon button 不同——本身编码"渲染模式多选一状态"信息差异）✓
4. **视觉差异审查**：
   - Copy chevron 存在 = 编码"含菜单" ✓
   - modeControl segmented style = 编码"多选一状态" ✓
   - 组间大间距 = 编码"两组不同类" ✓
5. **红色扫描**：无红色（错误状态由 metaLabel 文字变红承担，仅错误时出现）✓
6. **字阶**：文件名 semibold 13pt / 元信息 11pt secondaryLabel = 2 阶 ≤ 3；灰字只在元信息 ✓
7. **跨屏抽查**：Empty state Open File 是全 app 唯一绿色 CTA（§1.2 强调色单义）；预览态无绿色元素 → 跨屏一致 ✓

### Sidebar · Open tab

1. **灰度眯眼**：焦点在当前选中 tab 的背景高亮（§1.2 强调色 = 当前位置）；其他 tab 无背景 ✓
2. **一句话概括**：显示已打开文件、允许切换/关闭 ✓
3. **并列组**：
   - Tab card 并列组：所有 tab 共同总体名词 = "已打开文件"，同装（icon + title + subtitle + close X 位置一致） ✓
   - Close All 独立一行，不进 tab card 并列组（元动作层，与内容层分离） ✓
4. **视觉差异审查**：
   - 选中 tab 背景高亮 = 编码"当前"（§1.2） ✓
   - Close All 灰字小号 = 编码"次级/元动作层" ✓
   - close X 所有 tab 完全一致（位置、opacity、颜色） ✓
5. **红色扫描**：错误 tab 的 subtitle 红色（isError = true 时），是错误语义 ✓
6. **字阶**：title 12pt / subtitle 10pt secondaryLabel / Close All 11pt secondaryLabel = 3 阶 ≤ 3 ✓
7. **跨屏抽查**：与 Files / Contents section 使用相同 sidebarSectionControl；tab card 样式与其它 section 内容有明显组件区分 ✓

## Work-Unit Specs

### T1 · 预览窗口顶栏与文件 tab 关闭对齐重构

- **id**：T1
- **title**：预览窗口顶栏（split-button Copy / folder Reveal / overflow）+ 文件 tab close 对齐 + Close All
- **file_path**：`Sources/PeekyKit/PreviewWindowController.swift`
- **functions/regions**（同一文件、紧耦合、单单元）：

  - **`FileTabView.init` + `updateAppearance`**
    - 移除 `closeButton` 从 `rowStack` 的 arrangedSubviews；改由直接约束：
      - `closeButton.trailingAnchor = self.trailingAnchor - 8`
      - `closeButton.centerYAnchor = self.centerYAnchor`
      - `closeButton.widthAnchor = 20`，`heightAnchor = 20`
    - `rowStack` 只留 `[iconView, textStack]`；`rowStack.trailingAnchor = closeButton.leadingAnchor - 8`
    - 高度约束从 `greaterThanOrEqualToConstant: 46` 改为 `equalToConstant: 46`
    - `updateAppearance()` 移除 `closeButton.alphaValue` 随状态变化行；`closeButton.alphaValue = 1.0` 恒定（或直接不设，取默认 1.0）
    - `contentTintColor` 保留 `.secondaryLabelColor`
    - behavioral_contract：所有 tab 的 close X 世界坐标严格 (self.trailing - 8, y_i)，其中 y_i = tab_i_top + 23（46 / 2）；opacity 全等；hover/selected 只改背景色

  - **`setupHeader`**（顶栏 stack 重建）
    - 删除 `openButton` 声明与所有关联代码（including line 291、748、769、以及打开面板的钩子如仍存在）
    - 删除 `wrapButton`（顶栏 icon）声明与关联代码
    - 新增 `copySegmented: NSSegmentedControl`（2 段，`.momentary` mode）：
      - Segment 0：image = `doc.on.doc`，width 30，action = `copyAllText`（直接复制全文）
      - Segment 1：image = `chevron.down`，width 18，action = popUp `copyMenu` at segmented control frame bottom
      - `segmentStyle = .texturedRounded`
    - 新增 `overflowButton: NSButton`（`ellipsis.circle`，配置同 configureIconButton），action = popUp `overflowMenu`
    - `revealButton` 图标改为 `folder`
    - `controls` 拆两个子 stack：
      - `viewModeGroup = NSStackView(views: [modeControl])`，spacing 0
      - `actionGroup = NSStackView(views: [copySegmented, revealButton, overflowButton])`，spacing 8
      - 外层 stack `[viewModeGroup, actionGroup]`，spacing 20
    - modeControl 隐藏时 viewModeGroup 自动折叠（利用 NSStackView 的 hidden view 隐藏）——保留既有 `modeControl.isHidden` 触发点

  - **新增 `configureOverflowMenu()`**
    - `overflowMenu` 添加 checkable `NSMenuItem(title: "Wrap Lines", action: #selector(toggleWrap:), keyEquivalent: "")`，`.state = wrapsLines ? .on : .off`
    - `overflowMenu.delegate = self`，在 `menuNeedsUpdate` 里刷新该项 state
    - 保留既有 `toggleWrap(_:)` 方法体不变

  - **`configureCopyMenu`**（不变，继续为 copySegmented segment 1 提供菜单）

  - **`setupTabSection`** + Open section 布局
    - Open section 增加 `closeAllButton: NSButton`（bezelStyle `.inline` 或 borderless，title = "Close All"，font 11pt system regular，`contentTintColor = .secondaryLabelColor`，target/action = `closeAllTabsClicked:`）
    - Open section 顶层 stack = `[closeAllButtonRow, tabStack]`，spacing 8
      - closeAllButtonRow 是一个 horizontal stack `[NSView spacer, closeAllButton]`，让 button 右对齐
    - 显隐由 `updateCloseAllVisibility()` 每次 tabs 变化时调用：`closeAllButtonRow.isHidden = tabs.count < 2`

  - **新增 `closeAllTabsClicked(_:)`**
    - 遍历 tabs 数组做完整关闭（复用现有 close-tab 逻辑，从末尾向前 close 或直接清空 + 关闭 window 逻辑对齐既有 single-close 语义）
    - close all 后若 tabs 为空 → 走 empty state（既有 renderEmpty 分支）

- **dependencies**：无
- **reuse_candidates**：
  - `copyAllText()` 既有（line 2320）→ Copy segment 0 直接调用
  - `copyMenu.popUp(...)` 既有形式（line 2288）→ Copy segment 1 复用（相对 copySegmented 定位）
  - `configureIconButton` 既有（line 2178）→ revealButton / overflowButton 继续用
  - `toggleWrap` 既有（line 2199）→ overflow menu item 直接指向
  - `NSWorkspace.activateFileViewerSelecting` 既有（line 2208）→ Reveal 保留
  - 单 tab close 逻辑 → close all 复用（找到既有 `closeTab` / onClose 回调 pattern，遍历）
- **acceptance**：
  1. `swift build` 通过，无 warning 回退
  2. `swift run peeky <某文本文件>` 打开：顶栏右侧仅 `[modeControl（可能隐藏）] [Copy segmented 2段] [Reveal folder] [⋯]`；empty state 无 icon 按钮
  3. Copy segment 0 单击 = 剪贴板得全文；segment 1 单击 = 弹菜单（含既有 7 项）
  4. Reveal 按钮 tooltip = "Reveal in Finder"，图标为 folder；点击 = 系统 Finder 高亮该文件
  5. ⋯ 菜单展开唯一项 "Wrap Lines"，勾选切换 = wrapsLines toggle 生效（textView 实际换行行为改变）
  6. 打开 5 个文件 → 侧栏 Open tab 显示 5 卡片，close X 世界坐标 x 严格相等，y 之间差恰为 50（46 + 4 spacing）；opacity 全 1.0
  7. tabs 数 ≥ 2 时侧栏顶部显示 "Close All"（灰字右对齐）；点击 = 全部 tab 清空 → empty state
  8. tabs 数 = 1 时 Close All 隐藏
  9. 冒烟：多次打开-关闭切换、mode 切换、wrap 切换、copy 变体六项、reveal、close all 全通
  10. §Self-check 中两块单屏自检的 7 条逐条口述过关

## Dependency Graph

```
T1 (单单元、无依赖)
```

## Execution Waves

- Wave 1（无依赖）：T1

## Testing / 验收路径

本 unit 是纯 AppKit 视图/控制器层重构，无叶子纯函数新增；按 PATTERNS.md 约定「AppKit 视图/控制器层按架构师裁定走构建 + 冒烟清单验收」，不派 `@test-author`，直接派 `@function-implementer` + 我做人工冒烟：
- `swift build` + `swift run peeky ...` + 上述 acceptance 10 条
- 现有测试全绿（Tests/PeekyKitTests 165 用例基线不动）

Copy 按钮的语义拆分 `copyAllText`/`copySelection` 等仍是既有纯函数（如 `selectionCopyPayload`），既有测试覆盖有效，无需新增测试。

## Living Documentation

- **PATTERNS.md**：若 split-button（NSSegmentedControl 承载）成为本 repo 通用 UI pattern，可补一条"含菜单动作按钮采用 NSSegmentedControl 2 段模式（主段 + chevron 段）"。仅在本次落地即形成惯例时更新，否则暂不入册。
- **PROJECT.md**：功能状态表无新增/移除功能，Copy 五件套仍存在，故不动。
- **BACKLOG.md**：本 plan 落地过程用其记录 T1 状态。

## Revision · 2026-07-23（用户 T1 验收后指令）

用户看过 T1 落地效果后指出信息层级仍不对：Copy split-button 的 dropdown 里塞了**选区级**语义（Copy Selection、Copy Path:Line）与**跨语义**动作（Open in Editor），与顶栏"文件级"总体名词冲突；Copy File 与 Copy All 视觉难辨；Open in Editor 实际不 work。用户明确指令：

- 顶栏 4 个独立 Copy button：Copy File Content / Copy File Name / Copy Absolute Path / Copy Relative Path（各自独立、intuitive 图标）
- 删除：Open in Editor（不 work）、Copy Selection（无用；原生 ⌘C 已由 NSTextView 承接选区复制）、Copy File（文件对象复制，与 Copy All 混淆）
- Copy Path:Line 移到选区浮动 UI：选中非空文本区域后在选区边缘出现浮动按钮，点击复制 `path:line`

由此本 plan 增补 revised T1 与新增 T2。

### D8 · 顶栏 Copy 拆成 4 个独立按钮，删除 split-button 与 copyMenu

**违反规则识别**：
- 前版 copyMenu dropdown 混装了三类语义——**文件级**（Content、AbsPath、RelPath、File）、**选区级**（Selection、Path:Line）、**跨应用**（Open in Editor）。放在同一菜单构成一个视觉并列组，找不到共同总体名词——违反 §1.3 并列即同级。
- 用户在无选区时打开菜单，选区级 item 的描述文本无法自解释（"Copy Selection" 复制什么？"Copy Path:Line" 行号取哪个？）——违反 §1.8 组件隐喻贴合与 §0 每个视觉差异编码信息差异（选区级 item 与文件级 item 视觉全同装但语义前置条件不同）。
- Copy All vs. Copy File 字面近似语义远异——违反 §1.8。

**决策**：顶栏 Copy 相关变为 4 个独立 icon button（`.momentary` NSButton，同装、tooltip 精确）：

| 按钮 | SF Symbol | tooltip | action |
|---|---|---|---|
| Copy File Content | `doc.on.clipboard` | Copy File Content | `copyAllText()` |
| Copy File Name | `character.textbox` | Copy File Name | 新增 `copyFileName()` |
| Copy Absolute Path | `link` | Copy Absolute Path | `copyAbsolutePath()` |
| Copy Relative Path | `arrow.turn.up.right` | Copy Relative Path | `copyRelativePath()`；无 repo root 时 `isEnabled = false` |

依据：
- §1.3 并列即同级——4 项共同总体名词收敛为"关于当前文件的一段信息复制到剪贴板"，全部文件级、无选区/外部应用依赖。
- §1.4 同级同装——4 个 button 全 icon-only NSButton，同尺寸同 bezelStyle，唯一视觉差异是各自图标（编码"复制哪种信息"这个信息差异，符合 §0）。
- §1.6 并列数 ≤4——恰好 4 项，等于阈值。
- §1.8 组件隐喻——每个 icon 独立承担一种复制语义，不再有"点了才发现是菜单"的隐喻错位。
- Copy Relative Path 的 isEnabled 状态编码"当前文件是否在 repo 内"信息差异（§0），不需要动态显隐（保持位置稳定，避免右侧 button row 抖动）。

图标选择依据（intuitive 优先）：
- Content = `doc.on.clipboard`：文档 → 剪贴板，最直接的"复制文档内容"隐喻
- Name = `character.textbox`：字符方框，暗示"文件的名字"这段字面文本
- AbsPath = `link`：完整链接（macOS/URL 通用"绝对定位"符号）
- RelPath = `arrow.turn.up.right`：转弯箭头，暗示"从某参考点相对定位"，与 `link` 视觉充分区分

### D9 · 选区触发浮动按钮承载 Copy Path:Line（新单元 T2）

**违反规则识别（前版）**：Copy Path:Line 是**选区级动作**——行号取选区首行，无选区无语义。把它塞进文件级顶栏 dropdown 违反 §1.3；用户不在预览区选文本就打开菜单会读到"Copy Path:Line" 却无从判断复制的是哪行——违反 §1.8 与 §0。

**决策**：Copy Path:Line 从菜单移到**选区触发的浮动动作**——只在 textView 有非空选区时出现在选区边缘的一个小浮动按钮，点击后复制 `path:line`（line 取选区首行）。

- 出现条件：`textView.selectedRange().length > 0` 且窗口 key
- 出现位置：选区**首行的顶部右侧上方 8pt**（若首行紧贴 textView 顶或右缘则位置反向就近校正保证可见）
- 出现时机：选区变动后 debounce 150ms 稳定再出现（避免用户拖选过程中闪现）
- 消失条件：选区变空 / 窗口失活 / 点击浮动按钮完成复制 / textView 内容变化
- 视觉：圆角矩形背景（`textBackgroundColor` + 边框 `separatorColor`），内含 `link.badge.arrow.up.right` icon（或类似）+ "path:line" mini label，字号 10pt secondaryLabel，整体尺寸约 26×110pt
- 隐喻贴合（§1.8）：浮动按钮出现在选区边缘 = "对这个选区做一个动作"；不与顶栏文件级按钮位置冲突

**依据**：
- §1.3 并列即同级——选区级动作应住在选区上下文，不入文件级并列组。
- §0 每个视觉差异编码信息差异——浮动按钮"仅在有选区时出现"这一显隐差异，本身编码"存在可用的选区级动作"这一信息。
- §1.8 组件隐喻贴合——浮动 hover UI 是选区级 action bar 的标准隐喻（macOS 系统级 text selection 也有类似浮出，如触控板双指长按选文后的建议）。

### D10 · Edit 主菜单同步收敛

AppDelegate 的 Edit 菜单原有六项要与顶栏语义一致：
- **保留**：Copy All（改标 "Copy File Content"，语义与顶栏 button 一致）、Copy Absolute Path、Copy Relative Path
- **新增**：Copy File Name（无默认快捷键）
- **删除**：Copy File、Copy Path:Line、Open in Editor
- ⌘C（原生 NSText.copy）与 ⌘A（Select All）保持

依据：Edit 菜单是顶栏 button 的键盘等价入口，语义必须与顶栏 button 集完全对齐（§0 跨屏一致）。

### Work-Unit Specs · Revised

#### T1'（替换原 T1，同一文件持续演进）· 顶栏 4 button 化 + Edit 菜单同步 + 死代码清理

**file_path**：`Sources/PeekyKit/PreviewWindowController.swift`、`Sources/PeekyKit/AppDelegate.swift`、`Tests/visible/previewSelectionVisible.test.swift`（删除）

**改动列表**：

在 `PreviewWindowController.swift`：
- **删除字段**：`copySegmented`、`copyMenu`、`copyRelativePathMenuItem`
- **新增字段**：`copyContentButton: NSButton`、`copyNameButton: NSButton`、`copyAbsPathButton: NSButton`、`copyRelPathButton: NSButton`
- **删除方法**：`configureCopyMenu()`、`showCopyMenu(_:)`、`copySegmentedClicked(_:)`、`copyAllMenuAction`、`copySelectionMenuAction`、`copyAbsolutePathMenuAction`、`copyRelativePathMenuAction`、`copyFileMenuAction`、`copyPathLineMenuAction`、`openInEditorMenuAction`、`copySelection()`、`selectionCopyPayload(...)`（`nonisolated static`）、`copyFileReference()`、`openInEditor()`、`copyPathLineReference()`（移到 T2，暂保留为 public 方法供 T2 调用）
- **新增方法**：`copyFileName()`——`NSPasteboard.general.setString(url.lastPathComponent, forType: .string)`
- **保留方法**：`copyAllText()`、`copyAbsolutePath()`、`copyRelativePath()`、`hasRepoRootForActiveFile`
- **setupHeader 内**：
  - actionGroup 改为 `[copyContentButton, copyNameButton, copyAbsPathButton, copyRelPathButton, revealButton, overflowButton]`
  - 每个 copy button 用现有 `configureIconButton` 加相应 SF Symbol + tooltip
  - 4 个 copy button + reveal + overflow 共 6 项 → **拆成两个子 stack**："copy 组 [Content, Name, Abs, Rel]" + "location 组 [Reveal, Overflow]"，两小组各自组内 spacing 8，小组间 spacing 12（组间距 > 组内间距即可；≤4 条约束在小组内成立）
  - actionGroup 变为 `[copyGroup, locationGroup]`，spacing 12
  - 保持 viewModeGroup / actionGroup 之间的 20pt 大组间距
- **isEnabled 联动**：
  - 全部 6 个动作 button（4 copy + reveal + overflow）随文件加载状态启用/禁用（原 `copySegmented.isEnabled = true/false` 位置替换）
  - `copyRelPathButton.isEnabled = hasRepoRootForActiveFile`（额外条件）在每次 render 后同步
- **menuNeedsUpdate**：删除 copyMenu 分支，只保留 overflowMenu 分支

在 `AppDelegate.swift`：
- **Edit 菜单**：
  - 移除 `Copy File`、`Copy Path:Line`、`Open in Editor` 三个 `NSMenuItem` 及其分隔符（`editMenu.addItem(.separator())` 相应调整）
  - 修改 "Copy All" 标题为 "Copy File Content"，`action` 与快捷键（⌥⌘C）保留
  - 新增 "Copy File Name" `NSMenuItem`：无默认 keyEquivalent，`action = #selector(copyFileNameAction(_:))`
  - `copyRelativePathMenuItem` 逻辑保留（无 repo 时 hidden）
- **删除 @objc 方法**：`copyFileAction`、`copyPathLineAction`、`openInEditorAction`
- **新增 @objc 方法**：`copyFileNameAction(_:)` → 转发 `activeWindowController()?.copyFileName()`
- **validateMenuItem**：`copyActions` set 更新（增 copyFileNameAction，删 copyFileAction/copyPathLineAction/openInEditorAction）

在 `Tests/`：
- **删除文件**：`Tests/visible/previewSelectionVisible.test.swift`（`selectionCopyPayload` 已删）

**acceptance**：
1. `swift build` 通过；`./.build/debug/PeekyTests` 全绿（预期从 227 → 223：删掉 4 个 selectionCopyPayload 测试）
2. 打开一个在 repo 内的文本文件（如本 repo 的 `AGENTS.md`）：顶栏动作组从左到右 = `[copyContent 📄] [copyName 🔤] [copyAbs 🔗] [copyRel ↰] · gap · [reveal 📁] [overflow ⋯]`，四个 copy button 图标视觉清晰可辨
3. 每个 copy button 点击 → 剪贴板内容对应正确（内容/文件名字符串/绝对路径/相对路径）
4. 打开一个 repo 外的临时文件（如 `/tmp/foo.txt`）：copyRelPath 灰置（`isEnabled=false`），其余三个正常
5. Reveal 图标 folder；点击 = Finder 高亮该文件
6. ⋯ 菜单一项 Wrap Lines，勾选切换生效
7. 主菜单 Edit → 见 "Copy File Content"（⌥⌘C）/ "Copy File Name" / "Copy Absolute Path"（⇧⌘C）/ "Copy Relative Path"（⌥⇧⌘C）四项 + 原生 Copy(⌘C) + Select All(⌘A)。无 "Copy File" / "Copy Path:Line" / "Open in Editor"
8. 无打开文件：4 个 copy 按钮 + Reveal + Overflow 全 disabled；Edit 菜单四项也 disabled

#### T2 · 选区触发浮动 Copy Path:Line 按钮

**file_path**：`Sources/PeekyKit/PreviewWindowController.swift`（+ 若需可拆出新文件 `SelectionActionOverlay.swift`）

**改动列表**：
- **新增**：一个浮动的 subview `selectionActionButton: NSButton`（borderless、圆角背景、icon `link.badge.arrow.up.right` + 内联 "path:line" 10pt label），初始 `isHidden = true`
- 该 button 加到 `scrollView.contentView`（clip view 的 subview 而非 documentView subview）——保证浮动不参与文档滚动，位置由代码动态计算
- **观察**：`NSTextView.didChangeSelectionNotification`（对 textView.centerSelectionInVisibleArea 无副作用）
- **debounce**：`selectionUpdateTimer: Timer?`，selection change 后 150ms 稳定再评估显隐
- **显隐/定位逻辑**（新方法 `updateSelectionActionButton()`）：
  - 若 window 非 key、或 selectedRange.length == 0、或 activeTab 空 → hide，return
  - 计算选区首行 boundingRect（`layoutManager.boundingRect(forGlyphRange:in:)`，取首行片段）
  - 转到 scrollView.contentView 坐标系
  - 按钮定位：`x = rect.maxX - buttonWidth`（右对齐选区末端）；`y = rect.minY - buttonHeight - 4`（选区顶部上方 4pt）；边界收敛（避免超出可视区上/右缘）
  - `isHidden = false`
- **点击 action** `selectionCopyPathLineClicked(_:)`：调 `copyPathLineReference()`（保留自 T1'）+ 短暂显示 checkmark（可选：0.6s 后 hide 或立即 hide）
- **主动隐藏点**：文档内容切换（renderActiveTab 开头）、窗口失活（NSWindow.didResignKeyNotification）、textView 内容 setAttributedString 后
- 与 gutter / overlay 绘制无干扰（两者是 layoutManager 侧的绘制层，selectionActionButton 是 scrollView 上层 subview）

**acceptance**：
1. `swift build` 通过
2. 在打开的任意文本文件里用鼠标拖选一段（≥1 字符）→ 停顿约 150ms → 选区右上方出现浮动按钮（`link.badge.arrow.up.right` + "path:line"）
3. 点浮动按钮 → 剪贴板得 `<绝对路径>:<选区首行号>`；按钮消失
4. 松开选区（点空白处）→ 按钮消失
5. 拖动过程中选区快速变化 → 按钮不闪现（debounce 生效）
6. 切换 tab / 关文件 / 窗口失活 → 按钮立即消失
7. 选区靠近 textView 顶部（首几行）→ 按钮位置自动反向就近校正（不越 viewport 顶）
8. 无 Path:Line 快捷键（Edit 菜单已不含该项）；此功能仅由浮动按钮承担
9. 现有 165→现 223（T1' 后）测试全绿

**dependencies**：T1'（同文件、串行、T1' 先完成）

## Revision 2 · 2026-07-23（用户 T2 验收：markdown 场景未触发）

用户在 `SKILL.md`（markdown）验收时报 T2 浮动按钮"压根没出现"。根因：markdown 渲染走 `WKWebView`（`markdownWebView.isHidden = false` 时覆盖 NSTextView 所在 scrollView，PROJECT.md 关键决策记录已声明），选区变化发生在 WebView 内、`NSTextView.didChangeSelectionNotification` 不 fire，T2 的 debounce 链根本没启动；同时浮动按钮承载在 `scrollView.contentView`（clip view），markdown 场景该 view 被 WebView 遮盖，即便触发也不可见。

写 T2 spec 时未把"markdown 走 WebView"事实纳入——本 revision 通过新增 T3 补齐 WebView 场景。

### D11 · 浮动按钮承载 view 上提到 contentView

**动因**：非 markdown 场景住 `scrollView.contentView`、markdown 场景需覆盖 `markdownWebView`——两条渲染路径的目标 view 不同。选浮动按钮的承载 view = 两者共同上层 `contentView`（controller 根 view），坐标系统一，跨路径通用。

**决策**：
- `selectionActionButton.superview` 从 `scrollView.contentView` 改为 `contentView`
- 定位坐标全部转换为 `contentView` 坐标系：
  - NSTextView 路径：`textView.convert(rect, to: contentView)` 代替原 `to: scrollView.contentView`
  - WebView 路径：`markdownWebView.convert(rect, to: contentView)`
- 边界收敛用 `contentView.bounds`，同时对齐 header 底部（不让按钮跑到工具栏之上）

### D12 · WebView 侧选区事件桥接（JS ↔ Swift）

**决策**：
1. `setupMarkdownWebView` 创建 `WKUserContentController` 并加 `add(self, name: "peekySelection")` handler
2. 在 configuration 里注册 `WKUserScript`（injectionTime `.atDocumentEnd`，forMainFrameOnly true）：
   ```
   document.addEventListener('selectionchange', function() {
     const sel = window.getSelection();
     if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
       window.webkit.messageHandlers.peekySelection.postMessage({ hasSelection: false });
       return;
     }
     const range = sel.getRangeAt(0);
     const rects = range.getClientRects();
     const first = rects.length > 0 ? rects[0] : range.getBoundingClientRect();
     window.webkit.messageHandlers.peekySelection.postMessage({
       hasSelection: true,
       text: sel.toString(),
       x: first.left, y: first.top, width: first.width, height: first.height
     });
   });
   ```
3. controller 实现 `WKScriptMessageHandler`：收 payload → debounce 150ms（复用既有 `selectionUpdateTimer`）→ 调 `updateSelectionActionButtonForWebView(payload)`

### D13 · Markdown 场景的源行号 heuristic

**决策**：`path:line` 里的 line 用轻量 heuristic 而非侵入渲染层：
- WebView JS 回传选区**文本**（`sel.toString()`）
- Swift 侧在 `document.text`（源 markdown）里 `range(of: selectedText)` 首次匹配位置，从位置计算行号（`text.prefix(matchIndex).count("\n") + 1`）
- 命中 → line 号为该行；未命中（选区跨多个渲染块、或含渲染差异的字符）→ 降级为 line 1，同时 tooltip 提示"markdown 场景行号取首行"

依据：不改 MarkdownHTMLRenderer 语义、无第三方依赖、绝大多数常见选区（单句/单段）唯一匹配就精确；用户"看完顺手抄 path:line"的核心用例已覆盖。若后续需要严格精度再走 data-source-line 注入方案（届时另立 plan）。

### Work-Unit Specs · T3

#### T3 · Markdown WebView 场景的 T2 覆盖

**file_path**：`Sources/PeekyKit/PreviewWindowController.swift`

**改动列表**：
1. `selectionActionButton` 从 `scrollView.contentView` 迁到 `contentView`：
   - `contentView.addSubview(selectionActionButton, positioned: .above, relativeTo: nil)`（保证覆盖 scrollView + markdownWebView）
   - 移除对 `scrollView.contentView` 的 `NSView.boundsDidChangeNotification` 观察，改在 scrollView 滚动 + WebView 内滚动两侧独立回调
     - scrollView.contentView boundsDidChange 保留（复用既有；只是移到 hidden 状态检查后触发 update）
     - markdownWebView：注入 `window` scroll listener 也 postMessage 一次（复用 `peekySelection` handler，其中一个字段 `type='scroll'` 通知重定位）；简化实现：JS 里 `window.addEventListener('scroll', function() { /* 触发同 selectionchange 的 postMessage 但 text 与 hasSelection 保持前值 */ })` 会造成重复逻辑，务实做法：**滚动时不重定位**，用户滚屏浮动按钮短暂错位可接受，选区一变化按钮自然重算（若用户滚屏后不点选区，按钮无需存在）
2. `updateSelectionActionButton()`（NSTextView 路径）坐标 to 系改为 `contentView`：
   - 转换：`textView.convert(inTextView, to: contentView)`
   - 边界收敛：`clipBounds = contentView.bounds`；额外收敛上边界为 `headerView.frame.maxY + 4`
3. 新增 `updateSelectionActionButtonForWebView(payload:)`：
   - payload 包含 `{ hasSelection, text, x, y, width, height }`（CSS 像素，相对 WebView viewport）
   - `hasSelection == false` → 隐藏
   - `hasSelection == true`：
     - `webViewRect = NSRect(x: payload.x, y: payload.y, width: payload.width, height: payload.height)`
     - `rectInContent = markdownWebView.convert(webViewRect, to: contentView)`
     - 按钮尺寸/定位同 NSTextView 路径（选区首行右上方 4pt，越界反向就近）
4. `setupMarkdownWebView()` 添加 configuration：
   - `let controller = WKUserContentController()`；`controller.add(self, name: "peekySelection")`
   - `let script = WKUserScript(source: <上文 JS>, injectionTime: .atDocumentEnd, forMainFrameOnly: true)`；`controller.addUserScript(script)`
   - `let config = WKWebViewConfiguration()`；`config.userContentController = controller`
   - **问题**：`markdownWebView` 当前是 `WKWebView()` 无参构造，configuration 无法后改。要么改成 `WKWebView(frame: .zero, configuration: config)`（重构初始化），要么在 controller 单例上后加 handler + userScript（`markdownWebView.configuration.userContentController.add(self, name: ...)` 支持后加）。**取后一路径**：字段声明保持 `WKWebView()`，在 `setupMarkdownWebView` 里 `markdownWebView.configuration.userContentController.add(self, name: "peekySelection")` + `.addUserScript(script)`。
5. controller 实现 `WKScriptMessageHandler`：
   - 已有 protocol conformance 检查：若 controller 未声明，加 `WKScriptMessageHandler` 到类型 conformance 列表
   - ```
     nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
         guard message.name == "peekySelection" else { return }
         let body = message.body
         Task { @MainActor in self.handleWebViewSelectionPayload(body) }
     }
     ```
   - `handleWebViewSelectionPayload(_:)`：解 `[String: Any]`，若 `hasSelection == false` → 立即隐藏（不 debounce），否则 debounce 150ms 走 `updateSelectionActionButtonForWebView`
6. 隐藏点补充：
   - `renderMarkdownWeb` 开头：`selectionActionButton.isHidden = true`（清除上一文档遗留位置）
   - `markdownWebView.isHidden = true` 的所有点：连带隐藏浮动按钮
7. `copyPathLineReference()` 需支持 markdown 场景：
   - 目前 `currentReferenceLine()` 取 textView 选区首行；markdown 场景 textView 无选区
   - 新增字段 `webViewSelectionLine: Int?`，`handleWebViewSelectionPayload` 里通过 heuristic（`document.text` 匹配 `payload.text` 首次位置 → 换行数）填入；`nil` 时降级为 `1`
   - `copyPathLineReference` 判断当前渲染路径：markdown 用 `webViewSelectionLine`（无则 1），非 markdown 走原 `currentReferenceLine()`
   - 引入判定属性 `isMarkdownWebActive`（既有；`renderMarkdownWeb` 中已置 true，非 markdown 路径未置回 false——需要在 `renderPlain`/`renderError` 开头 `isMarkdownWebActive = false`；确认既有代码是否已做，未做则补）

**acceptance**：
1. `swift build` 通过；`./.build/debug/PeekyTests` 全绿（预 223）
2. 打开 markdown 文件（如 `SKILL.md`），选中一段任意文本 → 停顿 150ms → 浮动按钮浮出选区首行右上方（`link.badge.arrow.up.right` + "path:line"）
3. 点浮动按钮 → 剪贴板得 `<绝对路径>:<selectedText 首次匹配在源文件的行号>`；按钮消失
4. 松开选区（点空白处）→ 按钮消失
5. 选中一段在源文件里唯一的句子 → line 号精确匹配
6. 选中的文本在源文件里多次出现 → line 号取首次匹配
7. 选中的文本在源文件里查不到（例：跨渲染块的表格合并文本）→ line 号降级为 1
8. 切换到非 markdown 文件（如 `.json`）→ 浮动按钮仍在 NSTextView 场景工作（回归验证 T2）
9. 同一 controller 内 markdown 与非 markdown tab 交替切换 → 浮动按钮跟随当前渲染路径正确显隐、无残影

**dependencies**：T1'、T2（同文件、串行）

## Status

Completed —— T1 / T1' / T2 / T3 全部交付并通过用户实机验收。收尾修补：浮动按钮 visibility（accent 深底 + 白字 12pt medium + shadow + 28pt 高）+ 源行号 heuristic 抽为 `heuristicSourceLine(selected:in:)` 纯函数（多起点多长度短窗口采样，兜过 markdown 语法字符插入位置）。测试 223 用例全绿。
