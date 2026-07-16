# Feature: peek-native —— fork peeky 为基底的全原生转型

## Overview
peek 因 web 栈冷启感知（内容可读 ~1.0s，WebKit 进程树 ~200ms 为架构固有）被用户裁定放弃 TypeScript 渲染栈；fork `zhangzhejian/Peeky`（口头授权）为基底做全原生 macOS app，目标"弹出即可读" ~0.4s，并保住 peek 的四项差异化底线。web 栈 peek 存档于 `~/Documents/peek` @ `64bb100`。

当前最高优先级 = **批次 1「渲染重做 + 复制可用性」**：用户以日常使用反馈裁定（2026-07-15，issues #5-#10），要求 md/json/jsonl/源码文件"快、好看、好用"的渲染与完整复制能力。

## Intent Brief
- **Goal**：`peek <path>` → 原生窗口 ~0.4s 内容可读；四项底线全保：① repo-aware 树 + 相对 repo root 路径复制 ② JSONL 记录流/表格 ③ VSCode Dark Modern 高亮保真 ④ CLI 唤起。渲染质量达标：JSON/JSONL 树好用、Markdown 达 GitHub 级排版、源码原色高亮、全内容可选中可复制。
- **Motivation**：用户对启动速度零容忍（"慢不可接受，否则不如用 yazi"）；对渲染质量与复制可用性零容忍（2026-07-15："我只管结果，我要一个快、好看、好用的渲染器"）。
- **Known context**：
  - peeky：Swift 6 SPM 零依赖纯 AppKit，functional-core（叶子纯函数模块 + 单一有状态 `PreviewWindowController`）；tabs/多窗口/`peeky://open`/`path:line` CLI/Markdown 大纲/JSONL 记录流/三级性能预算/Ghostty OSC-8 已现成。
  - **地基已具备（2026-07-15 核验，44 测试全绿）**：PeekyKit 库 target + PeekyTests（swift-testing executable 型，suite 命名 `Visible_<unit>`/`Hidden_<unit>`，`scripts/run-hidden-tests.sh <unit>` 只输出 PASSED: X/Y）；`RepoRoot.discover(from:)`、DirectoryLister、FileTreeView、build-app.sh codesign/--install 均已实现——即原 W0a/W0b/W1a/W2a/W2b 已完成。
  - **JSC+Shiki spike 已验证**：esbuild 打包 shiki fine-grained core（JS 正则引擎）≈588K bundle；Swift `JSContext` eval 12ms + init 8ms + 首次 tokenize 349ms（冷 JIT，后台预热消化）；token 为 VSCode 原色。
  - **渲染选型调研（2026-07-15，三报告，来源已核验）**：① JSON 最佳实践 = 真树控件（NSOutlineView）+ 惰性索引 + 折叠摘要 + 大数组分桶 + path bar，jless/OK JSON/Chrome DevTools 均无缩进竖线；② Markdown "好看"来源 = GitHub Primer 排版数值（限宽阅读列/1.5 行高/比例标题/代码块浅底/克制表格），解析层官方 swiftlang/swift-markdown 为唯一满足零 WebKit+GFM 全覆盖+长期维护的选择；③ gutter 折行行号有权威解法（Apple 论坛 thread 683064：NSRulerView + enumerateTextLayoutFragments 仅首 lineFragment 编号 + viewport-only），STTextView 为 GPLv3/商业双许可、CodeEditSourceEditor 强制拖 34MB grammar 二进制，均不引入。
  - 用户四决策（2026-07-15）：**1A** JSON/JSONL 换 NSOutlineView 树 + 原文双视图；**2A** Markdown 用 swift-markdown + 排版规范（依赖获批）；**3A** 保留手写 NSTextView 修 gutter + 开启选中复制；**4A** 保持只读，⌘E 交默认编辑器（编辑请求 wontfix，见 `.out-of-scope/file-editing.md`）。
  - issue 映射：#5→R4a，#6→R1/R4c/R4d，#7→R4b，#8→R2/R4f，#9→R0/R3/R4e，#10→closed（4A）。
- **Constraints**：peeky repo 铁律（functional-core、零 SPM 依赖默认、三级性能预算、主线程纪律）；**swiftlang/swift-markdown 为唯一获批 SPM 依赖（2026-07-15 用户批准）**；shiki-bundle.js 为构建期生成物 checked-in（运行期零 Node、零 server、零 WebKit）。
- **Non-goals**：跟随上游 release 分支；编辑功能（`.out-of-scope/file-editing.md`）；跨平台；JSON 树内搜索过滤（后续批次评估）。
- **Success criteria**：交替冷启实测 time-to-window ≤ 450ms 且弹出即可读；四底线逐项验收；issues #5-#9 验收判据逐条通过；叶子纯函数模块双层测试全绿。

## Alignment Gate
- **I will implement**：批次 1（R0-R5，见下）；后续批次（W4b/W5）。
- **I will not implement**：上游 release 正则高亮合入；Tauri/Electron/WebView 任何回归；文件编辑。
- **Open assumptions**：80MB 索引内存倍率（R1 spike 验收关闭）。
- **Acceptance criteria**：同 Success criteria + issues #5-#9 判据。

## Assumption Ledger
| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| 高亮引擎 = JSC+Shiki | 决策 | — | closed（2026-07-03 裁定；2026-07-15 调研复核成立） |
| 渲染四决策 1A/2A/3A/4A | 决策 | — | closed（2026-07-15 用户裁定） |
| swift-markdown 依赖引入 | 决策 | — | closed（2026-07-15 用户批准） |
| 主战场 = peeky repo | high | low | closed（用户持续在本 repo 推进，2026-07-15 事实确认） |
| 80MB JSON 索引内存与速度 | 实测 | — | closed（spike 2026-07-15：430 万节点构建 0.35s（判据 ≤5s）；峰值 RSS 955MB ≈12×，架构师裁定接受——一次性上限场景成本；Node 布局压缩/惰性子树索引记后续优化） |
| 首次 tokenize 349ms 可由启动后台预热消化 | high | low：首文件高亮迟 ~300ms | R4e 验收关闭 |
| VS Code/Cursor 可识别并带行号定位参数打开 | medium | low：退化为仅打开文件 | R4b 验收关闭 |
| JSONL 表格列推导可复用 peek 的 collectColumns 语义 | high | low | W4b spec 时定 |
| DirectoryLister 排序 tie-break 契约 fixture 级未测（本机 APFS 大小写不敏感） | high | low | 接受（架构师裁定 2026-07-04） |
| R4a gutter 走 TextKit1 enumerateLineFragments 等价方案（textView 钉死 TK1） | 决策 | — | closed（架构师派发时授权的等价路线，行为契约逐条达标） |
| R4c JSON 树值颜色用系统语义色（非 dark_modern 绝对色） | 决策 | — | closed（架构师裁定：树背景自适应外观，浅色模式可读性优先） |
| 终审两 FAIL（Markdown 代码块无高亮/引用块缺色条）+ 三资源债（弃流不取消/grammarStates 泄漏/截断无占位） | 已修 | — | closed（R6a/R6b 修复，合并态 113 测试+三单元 hidden+smoke 全绿；bundle 寻径改多候选、codesign 密封恢复） |

## Work-Unit Specs

### 批次 1 · Wave 1 — 地基（无依赖）
```yaml
- id: R0
  title: shiki bundle 构建脚本 + checked-in 产物
  file_path: scripts/build-shiki-bundle.mjs + Resources/shiki-bundle.js
  behavioral_contract: |
    esbuild 打包 shiki fine-grained core（JS 正则引擎）+ 语言
    python/typescript/javascript/json/yaml/toml/bash/swift/ini +
    microsoft/vscode 的 dark_modern.json 作自定义主题；产物单文件
    Resources/shiki-bundle.js checked-in（构建期用 Node，运行期零 Node）；
    暴露全局入口 highlightLines(text, lang) 与分块续排入口
    （grammarState 传递）；启用 tokenizeMaxLineLength（超长行输出纯文本 token）。
    脚本幂等可重跑，锁定 shiki 版本。
  acceptance: bundle 生成 ≤1MB；node 侧 smoke（对 3 语言样例 tokenize 输出非空
    且含 dark_modern 颜色）通过。
```

### 批次 1 · Wave 2 — 纯函数层（不同文件可并行）
```yaml
- id: R1
  title: JSON/JSONL 惰性索引（纯函数，双层 TDD）
  file_path: Sources/PeekyKit/JSONTreeIndex.swift（新）
  dependencies: []
  functions:
    - name: JSONTreeIndex.build
      signature: "static func build(text: String, kind: FileKind) -> JSONTreeIndex"
      behavioral_contract: |
        单遍扫描构建节点表，不物化值字符串：每节点
        { type: object/array/string/number/bool/null, keyRange: Range<String.Index>?,
          valueRange: Range<String.Index>, childCount: Int, 子节点惰性可达
          （firstChild/nextSibling 索引或等价结构） }。
        值文本按需从原文 substring（value(at:) 访问器）。
        kind == .jsonl：每行一条顶层记录节点，坏行节点标记 invalid
        （与现有 JSONLineRecord 坏行语义一致）。
        kind == .json 且语法错误：返回截至错误处的部分索引 + errorOffset。
      error_cases:
        - { condition: "空输入/全空白", behavior: "空索引（零节点），不 throw" }
        - { condition: "嵌套深度 > 512", behavior: "该子树截断为 leaf 节点并标记 truncated" }
  reuse_candidates: |
    JSONFormatter 现有正则高亮/折叠逻辑面向文本流，不复用；JSONLineRecord
    的坏行语义沿用。JSONSerialization 不用（全量物化，违背惰性目标）。
  acceptance: |
    visible + hidden 全绿；spike 判据：脚本生成 80MB 样本，索引构建（后台）≤5s、
    进程内存增量 ≤2× 文件大小——超限则上报架构师重估（降级策略：深度截断）。

- id: R2
  title: Markdown 渲染器重写（swift-markdown + 排版规范，双层 TDD）
  file_path: Sources/PeekyKit/MarkdownRenderer.swift + Package.swift（加依赖）
  dependencies: []
  behavioral_contract: |
    Package.swift 引入 swiftlang/swift-markdown（固定版本）。MarkdownRenderer
    重写为 MarkupVisitor：AST → NSAttributedString，输出兼容既有
    RenderedPreview（含 outline 大纲提取）。GFM 全特性：表格（NSTextTable，
    细边框+表头加粗浅底+斑马纹）、任务列表勾选框、删除线、自动链接、
    围栏代码块（语言标记透传 SyntaxHighlighter 现有接口）。
    排版数值（GitHub Primer 派生）：正文 16pt、行高 1.5、段距 1em（paragraphSpacing，
    源文本空行零高度）；标题 2/1.5/1.25/1em 比例，h1/h2 底边线，上间距 > 下间距；
    代码块 85% 等宽字号 + 主题底色块 + 内边距，行内代码胶囊底；
    引用块左侧色条 + 次级文字色。颜色全走语义色/主题常量（暗浅色自适应）。
  reuse_candidates: |
    visitor 结构参照 Markdownosaur（Apache-2.0，仅抄结构不引依赖）；
    SyntaxHighlighter/分片布局泵/大纲侧栏管线复用。
  acceptance: visible + hidden 全绿（AST→属性断言：每特性至少一用例）；8MB 富格式化预算沿用。

- id: R3
  title: HighlightService（JSContext 封装，双层 TDD）
  file_path: Sources/PeekyKit/HighlightService.swift（新）
  dependencies: [R0]
  behavioral_contract: |
    R0 bundle 的 JSContext 单例封装：后台串行队列执行 tokenize；
    app 启动即预热（eval + init + 空 tokenize）；API：
    highlight(text:language:) 分块返回逐行 token（grammarState 续排，
    首屏行区间优先），回调携带行号区间供原位上色；
    1.5M UTF-16 预算沿用（超限返回 nil 表示纯文本回退）；
    language 由 FileKind/扩展名映射（py/ts/js/json/yaml/toml/sh/swift/ini/config）。
    主线程零重活（tokenize 全在后台队列）。
  error_cases:
    - { condition: "bundle 加载失败/JS 异常", behavior: "整体降级纯文本，记录一次性日志，不崩溃" }
    - { condition: "未知扩展名", behavior: "返回 nil（纯文本）" }
  acceptance: |
    visible + hidden 全绿（py/ts/json 小样例 token 颜色断言 = dark_modern 原色；
    超预算返回 nil；坏 bundle 降级）。
```

### 批次 1 · Wave 3 — UI 接线（PreviewWindowController 热点，严格串行，顺序 = 用户痛点优先级）
```yaml
- id: R4a
  title: gutter 重修 + 全文可选中复制
  file_path: Sources/Peeky/PreviewGutterView.swift + PreviewWindowController.swift
  dependencies: []   # Wave 3 链首
  behavioral_contract: |
    行号视图按权威方案重实现：作 scrollView 的 verticalRulerView，
    drawHashMarksAndLabels 内用 NSTextLayoutManager.enumerateTextLayoutFragments
    仅枚举 viewport 范围，每个 fragment 只在首个 textLineFragment 处绘逻辑行号
    （折行后续视觉行不编号）；滚动同步用 convert(NSZeroPoint, from: textView)
    坐标平移；frameDidChangeNotification + NSText.didChangeNotification 触发重绘；
    clipsToBounds 显式 true（macOS 14+ 默认 false 的既有坑）。
    JSONL 记录标记/坏行红标语义保留。所有渲染模式：textView
    isEditable=false、isSelectable=true（系统级选中 + ⌘C）。
  acceptance: |
    构建 + 冒烟（架构师，= issue #5 判据）：80MB JSON/JSONL 往复滚动行号
    与逻辑行一致；折行仅首视觉行编号；三类渲染视图可选中可 ⌘C；不可编辑；
    滚动无肉眼卡顿。

- id: R4b
  title: 复制五件套 + ⌘E 用编辑器打开
  file_path: PreviewWindowController.swift + AppDelegate.swift（菜单）
  dependencies: [R4a]
  behavioral_contract: |
    工具栏 copy 按钮挂 NSMenu + Edit 主菜单 + 快捷键，六项：
    ① 复制全文（当前 tab 原始文本）② 复制绝对路径 ③ 复制相对 repo root 路径
    （既有 RepoRoot.discover(from:)；无 repo 时该项隐藏）④ 复制文件本体
    （NSPasteboard.writeObjects([fileURL as NSURL])，Finder 可粘贴出文件）
    ⑤ 复制 path:line（选中行首行号，无选中时当前可视首行）
    ⑥ ⌘E 用系统默认编辑器打开当前文件——默认 app 为 VS Code/Cursor 时
    经其 CLI 协议带 path:line 定位，其余 NSWorkspace 直开。
  acceptance: |
    冒烟（= issue #7 判据）：六项入口存在、粘贴/打开结果逐项正确；
    无 repo 文件时相对路径项不出现。

- id: R4c
  title: JSON 树视图核心
  file_path: Sources/Peeky/JSONOutlineView.swift（新） + PreviewWindowController.swift（接线）
  dependencies: [R1, R4b]
  behavioral_contract: |
    view-based NSOutlineView over JSONTreeIndex，惰性 children；
    JSON/JSONL 默认视图 = 树。行呈现：key 着语义色、值按类型着色
    （dark_modern 语义色），值单行截断尾省略号；折叠态单行摘要
    `{…} N keys` / `[…] N items`；子项 >100 按 [0…99]/[100…199] 分桶
    懒展开；层级仅由系统缩进 + disclosure 三角表达（界面零缩进竖线）；
    JSONL 顶层每记录一节点，坏行节点红标 + 原文摘要。
    索引后台构建期间显示原文文本视图，就绪后无闪切换。
  acceptance: |
    冒烟（= issue #6 判据核心）：80MB JSON 可打开可浏览；展开万级数组
    不卡（分桶生效）；无缩进竖线；JSONL 坏行红标保留。

- id: R4d
  title: JSON 树交互层
  file_path: Sources/Peeky/JSONOutlineView.swift + PreviewWindowController.swift
  dependencies: [R4c]
  behavioral_contract: |
    折叠命令族：单击三角 toggle；Option+点击递归展开该子树；
    菜单/快捷键：全部展开、全部折叠、折叠到第 N 层（1/2/3）。
    空格 = 选中节点值全文 popover（长值查看）。
    常驻 path bar：显示选中节点 key path，点击弹复制菜单
    （点语法 .foo[3].bar / jq 风格两种）。右键节点：Copy Value / Copy Key /
    Copy Path。树/原文切换按钮：原文 = 现有文本管线（自由选中复制）。
  acceptance: 冒烟（= issue #6 判据交互项）：逐条交互可用。

- id: R4e
  title: 高亮接入 + Dark Modern 主题统一
  file_path: PreviewRenderer.swift + PreviewWindowController.swift
  dependencies: [R3, R4d]
  behavioral_contract: |
    源码类 FileKind 渲染路径接 HighlightService：纯文本立即显示，
    token 分块到达后原位上色（首屏行区间优先泵送，与既有分片布局泵同构）；
    编辑器区底色/前景/选择色统一 Dark Modern 语义（源码/JSON 原文/
    Markdown 代码块一致）；超 1.5M 预算保持纯文本。
  acceptance: |
    冒烟（= issue #9 判据）：py/ts/js/json/yaml/toml/sh/swift/ini 以
    VSCode Dark Modern 原色高亮；预热后打开文件首屏高亮无感知延迟
    （<100ms）；超预算文件纯文本可读。

- id: R4f
  title: Markdown 接线 + 限宽阅读列
  file_path: PreviewWindowController.swift + PreviewRenderer.swift
  dependencies: [R2, R4e]
  behavioral_contract: |
    Markdown 模式：textContainer 定宽阅读列（约 72 字符 × 正文字宽）
    水平居中，窗口窄于列宽时贴边自适应；R2 渲染器替换接入调用点；
    大纲侧栏/行跳转兼容。
  acceptance: |
    冒烟（= issue #8 判据）：GFM 样例文件对照 5 条排版规范逐条勾验；
    8MB 长文滚动流畅；大纲点击跳转正常。
```

### 批次 1 · Wave 4 — 收尾（架构师亲自）
```yaml
- id: R5
  title: 集成验证 + 双审计 + 文档更新
  behavioral_contract: |
    swift test 全量 + release 构建；@spec-compliance-reviewer 与
    @quality-security-reviewer 并行终审，FAIL 项修净；对照 Living
    Documentation 表更新 PROJECT/PATTERNS/TECHSTACK/DEVFLOW；
    issues #5-#9 逐条验收后关闭；BACKLOG 清空；plan 级 commit。
```

### 后续批次（本批不派发）
```yaml
- id: W4b
  title: JSONL 表格视图（NSTableView 备选渲染 + collectColumns 列推导纯函数移植，双层 TDD）
  dependencies: [R4d]
- id: W5
  title: 端到端验收：交替冷启计时（time-to-window ≤450ms）+ 四底线逐项验收 + peek repo 归档
```

## Dependency Graph
```
R0 ── R3 ──────────┐
R1 ────────────┐   │
R2 ──────────┐ │   │
             │ │   │
R4a ── R4b   │ │   │
        │    │ │   │
       R4c ◀─┼─┘ (R1)
        │    │
       R4d   │
        │    │
       R4e ◀─┴─ (R3)
        │
       R4f ◀── (R2)
        │
       R5
后续批次：R4d → W4b；全部 → W5
```
无环。`PreviewWindowController.swift` 为单文件热点：R4a→R4b→R4c→R4d→R4e→R4f 严格串行。

## Execution Waves
批次 1（本 BACKLOG）：Wave 1 = R0 ∥（R1/R2 测试先行）；Wave 2 = R1 ∥ R2 ∥ R3；Wave 3 = R4a→R4f 串行链；Wave 4 = R5。
后续批次：W4b、W5——批次 1 验收后再拆 BACKLOG 送批。

## Status
In Progress —— 批次 1（R0-R6b + 验收整改）已完成并合入 main（2026-07-16）：全量 113 测试、三单元 hidden 满额、双审计终审 FAIL 全修、用户实机复验通过 gutter/复制/JSON 树三域（issues #5-#7 已关闭）。用户复验遗留与新需求以 issues 管理：#8（Markdown 空行间距/code block 左 padding/大纲跳转置顶/表格场景复核）、#9（高亮主题浅暗统一/Python token 覆盖度）、#11（侧栏三区改 tabs）。后续批次 = 上述 issues + W4b/W5，细化后另拆 BACKLOG 送批。
