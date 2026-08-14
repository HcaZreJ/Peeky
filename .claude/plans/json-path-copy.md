# Feature: JSON 节点路径一键复制

## Overview
JSON / JSONL 预览中，光标或选区所在行对应 JSON 树里的某个节点。本功能把该节点的访问路径算出来，
以 jq 可直接执行的表达式形态（`.users[0].user.phone`）一键复制到剪贴板，并在底部状态栏常驻显示，
让用户复制前看得见拿到的是什么。

## Intent Brief
- **Goal**：选中 JSON 里的一行 → 一键拿到该行节点的树路径 → 直接粘进 `jq` 命令使用。
- **Motivation**：在大 JSON 里定位到某个字段后，手写 jq 路径要人肉数层级，容易错。
- **Known context**：JSON / JSONL 渲染走 `NSTextView` + pretty-print 文本；折叠态由
  `JSONFoldComposer` 提供 visible↔source 双向坐标映射；`PreviewWindowController` 已有
  选区浮动 chip（`path:line`）与底部状态栏（Ln/Col/选中数/size）两套现成接线。
- **Constraints**：叶子逻辑写成无状态 `enum` / `struct` 命名空间静态纯函数；零新增第三方依赖；
  大文件不阻塞主线程且不显著抬高常驻内存；顶栏已有 4 个 Copy 按钮 + Reveal + ⋯ 溢出菜单，空间紧张。
- **Non-goals**：不做路径反向跳转（输入路径定位到行）；不做 jq / 点分之外的第三方路径方言；
  不改折叠、高亮、gutter 的既有行为。
- **Success criteria**：
  - JSON：光标放到任意行 → 状态栏显示该行 jq 路径 → 点击 `jq path` chip →
    剪贴板内容能直接 `jq '<粘贴>' file.json` 跑出该行的值。
  - JSONL：路径相对当条记录的根（不含记录序号），粘进 `jq '<粘贴>' file.jsonl` 得到的是
    **每条记录**在该路径上的值——这是 jq 处理流式输入的标准语义，也是 JSONL 唯一合理的路径定义。
- **Unknowns**：无阻塞项。

## Alignment Gate
**I will implement**
- `JSONPathMap`：pretty JSON 文本 → 每逻辑行的节点路径（纯函数叶子模块 + 双层测试），
  以父指针树存储，避免逐行物化路径数组。
- 两种路径序列化：jq 表达式（默认）与 dot 形态（`users.0.user.phone`，⌥ 点击）。
- 选区浮动 `jq path` chip，与既有 `path:line` chip 成组并排；仅 JSON / JSONL 且结构解析成功时出现。
- 底部状态栏追加当前路径显示（只读，中段截断）。
- 折叠态坐标经 `JSONFoldComposer.sourceRange(forVisible:)` 归一到源坐标后再查路径。
- `RenderedPreview.jsonStructureIsValid`：把"JSON 解析成功"这一事实从渲染层显式传给控制器。

**I will not implement**
- 顶栏常驻按钮（决策依据见下）。
- Markdown / 源码 / XML 等非 JSON 文件的任何路径能力。

**决策：浮动 chip 而非顶栏 button。**
路径是光标位置的函数，不是文件的函数；顶栏那 4 个 Copy 按钮全是文件级、任何时候按下都有确定语义，
而"当前节点路径"在无选区或非 JSON 文件时无意义，放顶栏会长期是一个灰按钮。浮动 chip 与既有
`path:line` 同构（同一套定位/显隐逻辑，直接复用），且出现位置就在用户刚选中的那一行旁边，手不用移动。
状态栏的常驻路径显示补上 chip 的短板——chip 只写"jq path"，看不见内容；状态栏让用户复制前先看见。

**Acceptance**
- `PeekyTests` 全量零失败。
- dev 版实测：浅色 / 深色各一次；光标移动时状态栏路径实时更新；chip 复制的表达式在真实 `jq` 中可执行；
  非 JSON 文件的 `path:line` chip 行为无回归。

## Assumption Ledger
| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| 默认复制 jq 表达式 `.users[0].user.phone` 而非用户举例的 `users.0.user.phone` | high | low | 已决策：用户诉求"直接塞进 jq"是硬约束，dot 形态 jq 不接受；两种都做，dot 走 ⌥ 点击 |
| JSONL 的路径相对每条记录的根（不带记录序号前缀） | high | low | JSONL 逐条喂 jq 是标准用法，记录序号不属于路径；已写进 Success criteria |
| 光标（零长度选区）也显示路径，chip 仍只在非空选区出现 | high | low | 状态栏本就跟随光标，chip 沿用既有非空选区规则 |

## System Invariants
- **最长同步请求路径**：新增计算只有 `JSONPathMap.build`（单遍 UTF-16 扫描）与一次
  O(log n) 行号二分 + O(depth) 父指针回溯 + 字符串拼接。无 LLM / HTTP / DB 调用，
  用户可见路径上外部调用数为 0。build 与 `JSONFoldMap.build` **串行**放在
  `beginFoldContext`（`PreviewWindowController.swift:1756`）那一个后台 block 内——串行保证
  两者各自 `Array(prettyText.utf16)` 的瞬时峰值不叠加。
- **内存预算**：输出为 `nodes: [Node]`（每节点 = parent `Int32` + 一个 `JSONPathSegment`，
  节点数 ≤ 行数）+ `lineNode: [Int32]`（每行 4 字节）。80 MB 级 JSON（pretty 后约 5M 行）
  量级在 100-150 MB，与 `JSONFoldMap` 的 `lineDepths` + `regions` 同一数量级。
  逐行物化 `[[JSONPathSegment]]` 会到 650 MB（实测），本设计明确不采用。
- **后台任务与请求事务的锁边界**：无事务、无锁。全部可变状态 main-actor 隔离，后台 block 只读
  一个不可变 `String`；落地复用既有的 `foldRenderGeneration == generation && activeTabID == tabID`
  双代际 guard（`PreviewWindowController.swift:1760`），不新增代际计数器。
- **每个写路径的幂等性**：唯一写动作是 `NSPasteboard.clearContents() + setString`，
  重复点击写入同一字符串；状态栏 label 赋值同样幂等。
- **CI 可达性**：新增测试写进既有 `Tests/visible/` 与 `Tests/hidden/`，不新增测试目录。
  `Package.swift:81-87` 的 `PeekyTests` target `path: "Tests"` 无 exclude，两个子目录全量编入。
  仓库唯一的 workflow `.github/workflows/build-app.yml`（`workflow_dispatch` + `push: tags: v*`）
  只做 build / package / release，不含测试 step——测试闸门是 DEVFLOW 记录的本地
  `swift build --product PeekyTests && ./.build/debug/PeekyTests`，本 plan 沿用该闸门。
- **migration**：无数据库、无 migration。
- **外部输入边界**：输入是用户本地文件内容，去向是剪贴板与 `NSTextField.stringValue`，
  不进 prompt / SQL。但**剪贴板内容的实际落点是 shell 命令行**（`jq '<粘贴>' file.json`），
  因此 key 序列化除 jq 字符串转义外，还必须把单引号输出为它的 unicode 转义序列
  （反斜杠 u 0 0 2 7），
  防止第三方 dump 里形如 `x'; rm -rf ~; '` 的 key 复制出去后闭合用户的引号变成可执行命令。
- **回滚路径**：纯增量——一个新文件（`JSONPathMap.swift`）+ `PreviewRenderer` 加一个带默认值的
  字段 + `PreviewWindowController` 局部接线，共三个文件。单 commit `git revert` 完整回退，
  无持久化数据残留。

## Work-Unit Specs

```yaml
- id: U1
  title: JSONPathMap —— pretty JSON 文本的逐行节点路径索引
  file_path: Sources/PeekyKit/JSONPathMap.swift
  functions:
    - name: JSONPathSegment
      kind: enum
      cases: [key(String), index(Int)]
      notes: Equatable + Sendable

    - name: JSONPathMap.Node
      kind: struct
      fields: "parent: Int32（-1 表示根）, segment: JSONPathSegment"
      notes: Equatable + Sendable

    - name: JSONPathMap.build
      inputs: [prettyText: String]
      outputs: |
        JSONPathMap(nodes: [Node], lineNode: [Int32])。
        父指针树：nodes 每项是一个路径段 + 其父节点下标；lineNode 每逻辑行一项，
        存该行所指节点在 nodes 中的下标，-1 表示该行指向根（路径为空）。
        逐行物化 [[JSONPathSegment]] 的写法内存要到 650 MB 量级，不采用。
      behavioral_contract: |
        单遍 UTF-16 词法扫描 pretty-print 后的 JSON 文本（2 空格缩进，
        JSONSerialization.prettyPrinted 产物），为每一条逻辑行（按 "\n" 切分）
        求出该行所指节点。

        **行路径在该行第一个确定节点处定格**——同一行内之后出现的逗号、
        闭括号只影响后续行，不回改本行。这一条是全部歧义的裁决规则。

        节点归属规则：
        - object 内的 `"key": ...` 行 → 父容器节点 + .key(key)
        - array 内元素起始行（元素第一个非空白字符所在行）→ 父容器节点 + .index(i)，
          i 从 0 起，按同级逗号递增；下标计数器属于该 array 栈帧，
          嵌套容器的进出不影响它
        - 容器闭括号 `}` / `]` 所在行（含 `},` `],` 这种带尾随逗号的形态）
          → 该容器自身的节点
        - 其余行（根开括号行、空行、纯延续行）→ 该行开始时栈顶容器的节点
        - 嵌套时以最内层为准：`"user": {` 行归 [.., .key("user")]

        字符串字面量内的括号、引号、逗号按内容忽略（处理 \" 与 \\ 转义）。
        一个字符串后跟（跳过空白后的）`:` 判定为 key，否则是 value。

        **JSONL 记录边界**：扫到空行时，看它之前最近的一个非空白字符
        （跳过空格 / 制表 / 换行 / 回车）：
        - 是 `[` 或 `{` → 这个空行是**空容器的内部**，不清栈，该行路径照常退化为栈顶容器节点
        - 其它字符（`}` `]` 数字 引号 等，即一条记录的结尾或坏行的中断处）
          → 整栈清空、数组下标计数归零

        两条分支缺一不可：
        - 清栈这一支防止 JSONL 里一条括号不配对的坏行（JSONFormatter.swift:41-45
          原样输出坏行，记录间用 "\n\n" 拼接，见 :47-49）把残留栈帧泄漏给之后所有记录，
          使后续每一条记录的路径都带上一段看似合法、实则错误的前缀。
        - 不清栈这一支是因为 **pretty JSON 内部确实会出现空行**：Foundation 的
          `JSONSerialization.prettyPrinted` 把空容器输出成三行——
          `  "tags" : [` / 空行 / `  ],`（空对象与根空容器同构，均已实测）。
          缺这一支时，任何含空数组 / 空对象的 JSON，其后所有行的路径都会因误清栈而丢失前缀
          （`{"a":{"tags":[],"z":1}}` 里 `"z"` 行会算成 `.z` 而不是 `.a.z`）。

        任何输入都不抛错、不 trap：括号不配对时已闭合部分正常产出，
        未闭合部分沿用当时的栈状态直到下一个空行或文本结束。
        lineNode.count 恒等于文本按 "\n" 切分的段数（空文本为 1 行、-1）。

      canonical_fixture: |
        以下文本（JSONSerialization.prettyPrinted 的真实形态）逐行期望值，
        测试必须逐行断言：

        行0  {                        → []
        行1    "users": [             → [key(users)]
        行2      {                    → [key(users), index(0)]
        行3        "id": 1            → [key(users), index(0), key(id)]
        行4      },                   → [key(users), index(0)]      ← 不是 index(1)
        行5      {                    → [key(users), index(1)]
        行6        "id": 2            → [key(users), index(1), key(id)]
        行7      }                    → [key(users), index(1)]
        行8    ],                     → [key(users)]
        行9    "counts": [            → [key(counts)]
        行10     10,                  → [key(counts), index(0)]
        行11     20                   → [key(counts), index(1)]
        行12   ],                     → [key(counts)]
        行13   "a": {                 → [key(a)]
        行14     "b": "x"             → [key(a), key(b)]
        行15   }                      → [key(a)]
        行16 }                        → []

        JSONL 坏行隔离（必测）：
        `{"a":1}` / 空行 / `{"b": [1,2` / 空行 / `{"c":3}`
        （每条记录本身还会被 pretty 展开，测试按真实拼接形态构造）
        最后一条记录的 "c" 行必须是 [key(c)]，不能是 [key(b), index(2), key(c)]。

        空容器不误清栈（必测，用 prettyPrinted 真实产物构造）：
        - ["tags": [], "z": 1] → "z" 行 [key(z)]；空行本身 [key(tags)]
        - ["meta": [:], "z": 1] → 同构
        - ["a": ["tags": [], "z": 1]] → "z" 行必须是 [key(a), key(z)]（最能暴露误清栈）
        - ["list": [[], [1]]] → 第二个元素仍是 index(1)
        - 根空容器 [] 与 [:] → 各行路径为 []，不崩溃
        - 组合回归：一个 JSONL，某条记录含空数组，另有一条括号不配对的坏行 →
          空容器不清栈与坏行隔离两条规则同时成立

    - name: JSONPathMap.path
      inputs: [line: Int]
      outputs: "[JSONPathSegment]"
      behavioral_contract: |
        0-based 行号查路径：取 lineNode[line]，沿 parent 回溯到 -1，反转得根→叶顺序。
        越界（负数或 >= lineNode.count）返回空数组。O(depth)，不缓存。

    - name: JSONPathMap.jqExpression
      inputs: ["path: [JSONPathSegment]"]
      outputs: String
      behavioral_contract: |
        序列化为 jq 可直接执行、且可安全放进 shell 单引号的路径表达式。
        - 空路径 → "."
        - .key(k)：k 匹配 ^[A-Za-z_][A-Za-z0-9_]*$ 时输出 ".k"；
          否则输出 ".\"<escaped>\""
        - .index(i) → "[i]"
        - 首段是 index 时输出 ".[0]"（jq 接受）
        - 拼接示例：[key("users"), index(0), key("user"), key("phone")]
          → ".users[0].user.phone"

        escaped 规则：
        - \ → \\ ，" → \"
        - 换行 \n、制表 \t、回车 \r 用短转义
        - 其余 < 0x20 的控制字符 → \u00XX（小写 hex）
        - **单引号（U+0027）→ 六字符 unicode 转义序列 `反斜杠 u 0 0 2 7`**：
          剪贴板内容的落点是 `jq '<粘贴>' file.json`，裸单引号会闭合用户的 shell 引号。
          必须用 jq/JSON 的 unicode 转义，**不是** shell 拼接技巧
          `单引号 反斜杠 单引号 单引号`——后者产生的表达式含 `\'`，
          不是合法的 JSON/jq 字符串转义，写进 .jq 脚本 `jq -f` 执行会报
          `Invalid escape`（已在 jq-1.7.1 实测两种形态）。unicode 形态是自包含的：
          任何上下文都是同一个合法 jq 表达式，且不含裸单引号，放进 shell 单引号同样安全。
          这个表达式还会显示在底部状态栏（U2），自包含形态对读者也可读。

    - name: JSONPathMap.dotPath
      inputs: ["path: [JSONPathSegment]"]
      outputs: String
      behavioral_contract: |
        序列化为点分形态（lodash / 日常记法）。
        - 空路径 → ""
        - .key(k) → k 原文（不转义、不加引号）
        - .index(i) → String(i)
        - 段间以 "." 连接：[users, 0, user, phone] → "users.0.user.phone"

  dependencies: []
  reuse_candidates: |
    Sources/PeekyKit/JSONFoldMap.swift 已有一个成熟的 UTF-16 单遍扫描器（字符串字面量与
    转义处理、按行推进、常量命名风格），本单元沿用其扫描骨架。但**容错语义必须不同**：
    JSONFoldMap 对未闭合帧只是不产 region（良性），本单元的未闭合帧会污染后续路径，
    故新增"空行清栈"这条硬边界。JSONFormatter 只做 pretty-print，不产结构索引。
  acceptance: |
    Tests/visible/jsonPathMapVisible.test.swift（@Suite("Visible_jsonPathMap")）
    + Tests/hidden/jsonPathMapHidden.test.swift（@Suite("Hidden_jsonPathMap")，
    suite 名须与 scripts/run-hidden-tests.sh 的 --filter "Hidden_<unit>" 对齐）全绿；
    canonical_fixture 逐行断言 + JSONL 坏行隔离用例必须在内；PeekyTests 全量零失败。

- id: U2
  title: PreviewWindowController 接线 —— jq path chip + 状态栏路径显示
  file_path: Sources/PeekyKit/PreviewWindowController.swift（另触及 PreviewRenderer.swift）
  functions:
    - name: RenderedPreview.jsonStructureIsValid
      file: Sources/PeekyKit/PreviewRenderer.swift
      behavioral_contract: |
        新增 `let jsonStructureIsValid: Bool`，init 默认值 false，不破坏既有调用点。
        .json 成功分支（:79-85）传 true，catch 分支（:87-93）传 false；
        .jsonl 分支（:103-109）传 true——坏行由 U1 的空行清栈隔离在本条记录内，
        其余记录路径正确。其它 kind 用默认值。
        依据：catch 分支照样 usesJSONHighlighting: true，控制器据此建折叠上下文时
        sourceText 是**未格式化的原文**（既非 2 空格缩进也不保证括号配对），
        在其上建路径索引会产出看似合法的错误路径。

    - name: jsonPathMap 状态字段
      behavioral_contract: |
        新增 `private var jsonPathMap: JSONPathMap?`，与 foldMap 同生命周期：
        - `beginFoldContext`（:1747）新增 `buildsPathMap: Bool` 形参，
          在 :1756 那个后台 block 内于 JSONFoldMap.build **之后串行**构建（峰值不叠加），
          回主线程在 :1760 既有的双代际 guard 通过后与 foldMap 一并落地。
        - `clearFoldContext`（:1770）内 `jsonPathMap = nil`，与 `foldMap = nil`（:1773）同一区。
          这一点关键：clearFoldContext 被 renderActiveTab() 在每次渲染开头无条件调用，
          漏掉会导致切到 .txt tab 后状态栏仍显示上一个 JSON 的路径。
        - 调用点 :1567 传 `buildsPathMap: rendered.jsonStructureIsValid`。
        - **落地后刷新 UI**：map 落地的主线程回调里调用 `updateStatusBar()` 与
          `updateSelectionActionButton()`。否则大文件打开后状态栏路径要等用户点一下才出现
          （render() 末尾 :1617 的那次 updateStatusBar 发生在后台 build 完成之前）。
          map 未就绪时状态栏不追加路径段，也不显示占位文案，落地即补上。

    - name: currentJSONPath
      outputs: "[JSONPathSegment]?"
      behavioral_contract: |
        jsonPathMap 为 nil 时返回 nil。否则：textView.selectedRange() →
        经 foldComposition 映射到源坐标（`JSONFoldComposer.sourceRange(forVisible:)`，
        无折叠上下文时恒等）→ 用 statusBarSourceLineStarts 走 lineStartIndex(for:in:)
        得**0-based** lineIndex → `jsonPathMap.path(line: lineIndex)`（不 +1；
        updateStatusBar 在 :2127 的 +1 只用于展示行号）。
        折叠态下光标落在 chip 上时源坐标映射到 openLine，路径正好是该容器自身，无需特判。

    - name: copyJSONPath
      behavioral_contract: |
        currentJSONPath() 为 nil 时静默不作为。
        NSEvent.modifierFlags 含 .option → dotPath，否则 jqExpression，写入剪贴板
        （clearContents + setString，与 copyPathLineReference :2737 同款）。

    - name: setSelectionChipsHidden
      behavioral_contract: |
        先抽出 `private func setSelectionChipsHidden(_ hidden: Bool)` 同时管两个 chip，
        再把现有 13 处 `selectionActionButton.isHidden = true` 逐点替换
        （:1006, 1018, 1024, 1032, 1038, 1067, 1106, 1256, 1499, 1511, 1643, 1657, 2533）。
        漏掉任一处（尤其 windowDidResignKey / showPlainText / showEmptyState）
        都会出现"切到别的 tab 后 jq chip 还浮在屏幕上"。

    - name: 浮动 chip 成组布局
      behavioral_contract: |
        `positionSelectionActionButton(anchorRect:)`（:1081）现在硬编码单个按钮、
        `origin.x = anchorRect.maxX - width` 后 clamp 到右缘（:1097）；两个 chip 各自
        走一遍会被 clamp 到同一个 x 完全重叠。改为**按组布局**：
        先各自 sizeToFit 求宽（jq chip 在左、path:line 在右，间距 6pt），
        求出组总宽 → 组整体右对齐 anchorRect.maxX → 组整体做越界校正
        （越过 headerBoundary 时翻到锚点下方；两轴 clamp 进 contentView.bounds）
        → 再按组内偏移分配给两个按钮。
        jq chip 只在 currentJSONPath() 非 nil 时参与布局与显示；为 nil 时组退化为
        单个 path:line chip，位置与现状逐像素一致。
        样式沿用 selectionActionButton（accentColor 底 + 白字 + 6pt 圆角 + 阴影），
        标题 "jq path"，SF Symbol "curlybraces"，
        toolTip 写明 "Click: jq path · ⌥Click: users.0.user.phone"（⌥ 形态无其它可见提示）。

    - name: 状态栏路径段
      behavioral_contract: |
        updateStatusBar（:2117）左侧文案在 Ln/Col（及选中数）之后以三空格分隔追加
        当前 jq 路径。路径为 nil 或为根（"."）时不追加。
        过长时中段省略：超过 60 字符则保留首 28 + "…" + 末 28。
        中段截断规则抽成 `JSONPathMap` 或本文件内的静态纯函数并加双层测试。

  dependencies: [U1]
  reuse_candidates: |
    复用 selectionActionButton 的样式构造（:938-967）、positionSelectionActionButton 的
    越界校正思路（:1081-1102）、updateStatusBar 的源坐标映射与行号二分（:2117-2138）；
    不新写坐标换算，不新增代际计数器。
  acceptance: |
    - swift build 通过；PeekyTests 全量零失败（含新增的中段截断纯函数测试）。
    - 冒烟清单（浅色 / 深色各跑一次）：
      1. 打开 sample.json，光标移到 "phone" 行 → 状态栏出现 `.users[0].user.phone`
      2. 选中该行 → 出现两个 chip，jq path 在左、path:line 在右，不重叠
      3. 点 jq path → 剪贴板内容 `jq '<粘贴>' sample.json` 能跑出该行的值
      4. ⌥ 点 jq path → 剪贴板是 `users.0.user.phone`
      5. 选区拖到窗口最右缘 → 两个 chip 仍不重叠、不出界
      6. 折叠 users 数组后把光标放在折叠行 → 路径是 `.users`
      7. 切到一个 .txt tab → 状态栏无路径段、jq chip 不出现、path:line chip 行为如常
      8. 打开一个语法错误的 .json → 无路径段、无 jq chip（不显示推测路径）
      9. 打开 .jsonl → 路径相对当条记录根；含坏行的文件里，坏行之后的记录路径正确
```

## Dependency Graph
```
U1 (JSONPathMap) → U2 (PreviewRenderer 字段 + PreviewWindowController 接线)
```

## Execution Waves
- Wave 1：U1（`@unit-developer`，test-first）
- Wave 2：U2（`@unit-developer`；AppKit 接线部分按 PATTERNS.md:31 走"构建 + 手动冒烟"验收，
  可测的纯函数部分（路径中段截断）仍走双层测试）

## Documentation Impact
- `PROJECT.md:16`（JSON / JSONL 交互那行）追加节点路径复制与状态栏路径显示，
  纯函数模块清单补 `JSONPathMap`。
- `PROJECT.md:19`（顶栏 / 浮动按钮那行）把浮动 chip 描述为成组的两个。
- `PROJECT.md` 模块地图的叶子纯函数模块列表补 `JSONPathMap`。
- `PROJECT.md` 核心 Data Model 概览补 `JSONPathSegment` / `JSONPathMap`，
  并在 `RenderedPreview` 一条里补 `jsonStructureIsValid`。

## Status
Completed
