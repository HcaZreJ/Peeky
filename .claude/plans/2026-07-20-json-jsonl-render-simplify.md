# Feature: JSON/JSONL 渲染彻底简化 + 集中式主题源

## Overview

把 JSON 和 JSONL 的渲染统一为**唯一一种形态**:pretty-print 缩进的文本 + string/number/key/bool/null/标点语义分色 + NSTextView 原生选中复制,跟随系统 light/dark 外观。删除折叠树视图(NSOutlineView)与 tree/text/raw 模式切换。大文件(几万行 conversation history)靠**只给可视区上色的惰性高亮**扛住。

配色抽成一个**集中式、语义化的主题源** `PeekyTheme`:light/dark 两套 palette,每套是一组语义命名的 hex 常量;渲染逻辑只按语义 token 取色,不写死颜色。后续换配色 = 改几个 hex 常量,零逻辑改动。

本次只把主题源接到 JSON/JSONL 渲染区 + 其 gutter;侧边栏 / 源码高亮 / Markdown 的全 app 主题对齐留作后续独立工程。

## Intent Brief

- **Goal**:JSON/JSONL 打开即得"缩进好 + 分色 + 可选中复制"的单一可读视图,跟随系统明暗。
- **Motivation**:现有默认的全展开折叠树反而降低可读性;tree/raw/text 三种模式主题不统一(树白底、JSON raw 深色 Dark Modern、JSONL 白底)造成"切来切去主题变"的割裂感。用户真实用途:读 `~/.claude/settings.json`(JSON)与 `~/.claude/projects/{project}/{uuid}.jsonl`(几万行对话历史)。
- **Known context**:pretty-print(`JSONFormatter.prettyJSON`/`prettyJSONLines`)、分色雏形(`SyntaxHighlighter.highlightJSON` 正则)、NSTextView 选中复制(`isSelectable=true` + ⌘C 原生)均已存在,埋在非默认的 Text 模式里。viewport-only 惰性渲染有先例(`PreviewGutterView` 行号)。
- **Constraints**:纯 AppKit 无 WebView;functional-core(格式化/高亮/主题为无状态静态纯函数,状态只住 `PreviewWindowController`);主线程纪律(重算后台、UI 回主线程);只读查看器;换配色成本必须 = 改几个 hex 常量。
- **Non-goals**:侧边栏/源码高亮/Markdown 的全 app 主题统一(另开 issue);编辑功能;新增第三方依赖;JSON 图形节点图视图。
- **Success criteria**:JSON/JSONL 打开只呈现一种 pretty-print 分色文本视图;明暗跟随系统各一套成熟配色;可鼠标选中任意片段 ⌘C 复制;几万行 jsonl 打开与滚动流畅(可视区上色,不因体量丢色或卡顿);换任一 token 颜色只需改 `PeekyTheme` 的 hex 常量。
- **Assumptions**:见 Ledger。
- **Unknowns**:大 jsonl pretty-print 后文本体量(可能 100MB+ 级)在 NSTextStorage + 惰性布局下的实测内存/流畅度——用冒烟实测验证,必要时对 formatted 输出设合理上限降级。

## Alignment Gate

**I will implement**
- JSON/JSONL 唯一渲染 = pretty-print + 语义分色 + 原生选中复制,跟随系统 light/dark。
- 集中式 `PeekyTheme` 主题源(light/dark 双 palette,语义 token,纯 hex 常量);dark = VSC Dark Modern 色值,light = GitHub Light 初始色值。
- 原生 Swift `JSONHighlighter` tokenizer(替代正则,支持按范围 tokenize 以服务 viewport 惰性上色)。
- viewport-only 惰性上色(layoutManager temporary attributes,只算可见区,挂代际防护)。
- 彻底删除 `JSONOutlineView` + `JSONTreeIndex` + 其测试 + tree/text 切换 UI + 相关 per-tab 状态。
- gutter 行号、坏行红标(用主题色)、layout pump、记录分隔保留。

**I will not implement**
- 侧边栏 `FileTreeView` / 源码高亮 / Markdown 阅读列的主题对齐(记 issue,后续工程)。
- JSON 折叠、path bar、空格值预览 popover、记录尾"object - N keys"摘要注解(随极简目标移除)。
- 任何编辑能力、新第三方依赖。

**Open assumptions**:见 Ledger 中 Status ≠ resolved 的行。

**Acceptance criteria**
- 打开 json/jsonl:单一 textView 视图,pretty-print + 语义分色,明暗跟随系统。
- 鼠标选中 + ⌘C 复制所见文本可用。
- 几万行 jsonl 冷启与滚动流畅,可视区始终有色。
- 全量 `swift build -c release` 通过;纯函数模块 visible+hidden 全绿;AppKit 层冒烟清单通过。
- 改 `PeekyTheme` 任一 token 的 hex 常量即换色,无需动其它文件。

## Assumption Ledger

| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| light 初始用 GitHub Light 色值即可(不满意改 hex 常量换) | high | low | resolved(用户授权先做,换色成本已定为改常量) |
| dark 复用 VSC Dark Modern 色值 | high | low | resolved(用户指定) |
| 跟随系统 light/dark(非固定单主题) | high | medium | resolved(用户指定) |
| JSONL 每条记录全展开 pretty-print、记录间空行分隔 | high | medium | assumed(用户"每一行都 indent 好";可用后按体感调) |
| 移除记录尾摘要注解与 path bar/popover 属于"极简"预期内 | medium | low | assumed(低影响,用后可回补) |
| 大 jsonl pretty-print 文本在惰性布局+viewport 上色下可流畅 | high | high | verified：5 万行(6.8MB)+ 2MB 单行值冒烟均启动运行不卡死；viewport 逐行上色跳过 >64KB 超长行 |
| SPM 自动 glob 源文件,删文件无需改 Package.swift | high | low | 构建时验证 |

## Work-Unit Specs

### T1 · PeekyTheme 集中式主题源
```yaml
id: T1
title: PeekyTheme 集中式主题源
file_path: Sources/PeekyKit/PeekyTheme.swift   # 新文件
kind: 叶子纯函数模块(test-first)
functions:
  - name: PeekyTheme (enum 静态命名空间)
    描述: |
      语义化主题源。定义:
        enum Appearance { case light, dark }
        enum ThemeColor {  # 语义 token,与 JSONHighlighter.JSONTokenKind 对应 + 编辑器/gutter/坏行
          editorBackground, editorForeground,
          jsonKey, jsonString, jsonNumber, jsonBool, jsonNull, jsonPunctuation,
          gutterBackground, gutterText,
          invalidLineBackground, invalidLineForeground
        }
      两套 palette 各为一组 hex 常量(集中定义在本文件顶部,便于换色):
        dark(VSC Dark Modern 初始值):
          editorBackground #1F1F1F, editorForeground #CCCCCC,
          jsonKey #9CDCFE, jsonString #CE9178, jsonNumber #B5CEA8,
          jsonBool #569CD6, jsonNull #569CD6, jsonPunctuation #CCCCCC,
          gutterBackground #1F1F1F, gutterText #6E7681,
          invalidLineForeground #F85149, invalidLineBackground #F8514922(含 alpha)
        light(GitHub Light 初始值):
          editorBackground #FFFFFF, editorForeground #1F2328,
          jsonKey #0550AE, jsonString #0A3069, jsonNumber #098658,
          jsonBool #CF222E, jsonNull #CF222E, jsonPunctuation #6E7781,
          gutterBackground #FFFFFF, gutterText #8C959F,
          invalidLineForeground #CF222E, invalidLineBackground #CF222E1F(含 alpha)
    inputs: 静态命名空间,无实例
    outputs: NSColor / palette
    behavioral_contract: |
      - color(_ token: ThemeColor, appearance: Appearance) -> NSColor:
        对每个 (token, appearance) 组合返回对应 palette 的 hex 解析出的 NSColor。
        light 与 dark 都必须为**全部** ThemeColor 定义色值(palette 完整,无缺项)。
      - hexColor(_ hex: String) -> NSColor?:
        解析 "#RRGGBB"(6 位)与 "#RRGGBBAA"(8 位,末两位 alpha)。
        大小写不敏感;前导 "#" 必需。合法 → 对应 sRGB NSColor;
        非法(长度错/含非 hex 字符/缺 #/空)→ nil。
      - resolveAppearance(_ ns: NSAppearance?) -> Appearance:
        NSAppearance 最佳匹配 .darkAqua/.vibrantDark 系 → .dark;否则 .light;nil → .light。
      换色仅需改本文件顶部的 hex 常量,函数逻辑不变。
    error_cases:
      - { condition: "hexColor 收到非法字符串", behavior: "返回 nil" }
      - { condition: "hexColor 收到 8 位 hex", behavior: "解析含 alpha 的 NSColor" }
      - { condition: "resolveAppearance 收到 nil", behavior: "返回 .light" }
dependencies: []
reuse_candidates: |
  现有 DarkModernTheme(PreviewRenderer.swift:12-17)仅 background/foreground/gutter 三色,
  且散落非集中;shiki dark_modern 的 JSON token 色只在 JS bundle 内。本 unit 统一收拢为语义 palette。
acceptance: |
  visible+hidden 全绿。测试验证:palette 完整性(两 appearance × 全部 ThemeColor 均返回非 nil)、
  hexColor 正确性(6/8 位、大小写、非法→nil)、resolveAppearance 分支。
  **测试不硬编码断言具体 hex 色值**(色值是可调常量,锁死会让"换色=改常量"失效)。
```

### T2 · JSONHighlighter 原生 tokenizer
```yaml
id: T2
title: JSONHighlighter 原生 JSON tokenizer
file_path: Sources/PeekyKit/JSONHighlighter.swift   # 新文件
kind: 叶子纯函数模块(test-first)
functions:
  - name: JSONHighlighter.tokenize
    描述: |
      enum JSONHighlighter 静态命名空间。输出 token 类型 + range(不含颜色,颜色由 PeekyTheme 映射,解耦)。
        enum JSONTokenKind { key, string, number, boolLiteral, nullLiteral, punctuation }
        struct JSONToken { let kind: JSONTokenKind; let range: NSRange }
    signature: static func tokenize(_ text: String, in range: NSRange? = nil) -> [JSONToken]
    inputs: 一段(pretty-print 后的)JSON/JSONL 文本;可选子范围(nil = 全文)
    outputs: 按出现顺序排列的 JSONToken 数组,range 为 UTF-16 偏移
    behavioral_contract: |
      单遍扫描,区分:
      - 字符串:双引号包裹,支持 \" \\ \/ \n 等转义(反斜杠转义不结束字符串);
        紧随其后(跳过空白)为 ':' → kind=.key,否则 kind=.string。
      - 数字:可选负号、整数、小数、指数(如 -12.3e+4)→ .number。
      - true/false → .boolLiteral;null → .nullLiteral(作为完整字面量,非子串)。
      - 结构标点 { } [ ] , : → .punctuation(各一个 token)。
      - 空白(空格/tab/换行)跳过,不产 token。
      - range 参数非 nil 时,只返回**起点落在该范围内**的 token(controller 保证传入完整行边界)。
      - UTF-16 偏移与 NSAttributedString/NSTextView 一致。
    error_cases:
      - { condition: "空字符串或纯空白", behavior: "返回 []" }
      - { condition: "未闭合字符串(无收尾引号)", behavior: "返回一个延伸到文本末尾的 .string/.key token,不崩溃" }
      - { condition: "裸字面量在数组中 [\"a\"]", behavior: "\"a\" 为 .string(非 key,后随 ] 非 :)" }
      - { condition: "对象键 {\"a\":1}", behavior: "\"a\" 为 .key,1 为 .number" }
      - { condition: "含 \\uXXXX 转义的字符串", behavior: "整体为单个 string/key token" }
dependencies: []
reuse_candidates: |
  现有 SyntaxHighlighter.highlightJSON(正则,全量,1.5M 上限)不支持按范围惰性 tokenize、不区分 key/value。
  JSONScanner(JSONTreeIndex.swift)是为树索引设计(记 range 不上色、随 tree 删除)。本 unit 新写轻量 tokenizer。
acceptance: |
  visible+hidden 全绿:各类型 token、key vs value string 区分、转义字符串完整性、
  数字各形态、子范围过滤、空/空白/未闭合边界。
```

### T3 · PreviewRenderer 改造:JSON/JSONL 恒 formatted + 惰性高亮标记 + 跟随系统
```yaml
id: T3
title: PreviewRenderer JSON/JSONL 分支改造
file_path: Sources/PeekyKit/PreviewRenderer.swift
kind: 叶子纯函数模块(决策层,test-first)
functions:
  - name: render (JSON/JSONL 分支)
    描述: |
      JSON/JSONL 永远走 formatted(pretty-print),产出未逐 token 上色的 attributedText(仅等宽基础属性),
      逐 token 上色交由 controller 的 viewport 惰性路径。RenderedPreview 表达:
      - 新增语义标记 usesJSONHighlighting: Bool(true = 用 JSONHighlighter viewport 上色)
      - 新增 followsSystemAppearance: Bool(true = 用 PeekyTheme 跟随系统明暗)
      - JSON/JSONL 分支 highlightLanguage = nil(不走 shiki)
    behavioral_contract: |
      - JSON 可解析:JSONFormatter.prettyJSON 缩进文本;note="Formatted";
        display=.lineNumbers(showsIndentGuides:true);usesJSONHighlighting=true;followsSystemAppearance=true。
      - JSON 不可解析:原文文本;note="Invalid JSON";usesJSONHighlighting=true(尽力上色);followsSystemAppearance=true。
      - JSONL:JSONFormatter.prettyJSONLines(每行 pretty-print、记录间空行分隔、坏行保留原文并计数);
        display=.jsonLines(text:records:);note 含坏行计数(0 坏行时 "Formatted");usesJSONHighlighting=true;followsSystemAppearance=true。
        坏行红标信息随 records(isInvalid)传递,由 display metadata + controller 用 PeekyTheme.invalidLine* 上色。
      - 移除 collapseNestedJSON 折叠路径(全展开)。
      - 预算:JSON/JSONL 的 pretty-print 在 TextFileLoader 未截断(≤80MB 原始)前提下执行,不因 richFormatLimit(8MB)
        降级为无缩进 raw;richFormatLimit 对 JSON/JSONL 不再触发降级(其它类型行为不变)。
    error_cases:
      - { condition: "空 JSON 文件", behavior: "note 合理(如空/Invalid JSON),不崩溃" }
      - { condition: "全部坏行的 JSONL", behavior: "note 反映全坏行计数,文本为原文逐行" }
      - { condition: "有效但深层嵌套 JSON", behavior: "完整 pretty-print 全展开,无折叠占位" }
dependencies: [T1, T2]
reuse_candidates: |
  复用 JSONFormatter.prettyJSON / prettyJSONLines(现成 pretty-print);
  复用 applyInvalidLineHighlighting 思路但改用 PeekyTheme.invalidLine* 色。
acceptance: |
  visible+hidden 全绿:JSON 有效/无效、JSONL 正常/含坏行/全坏行、无折叠、标记字段正确、highlightLanguage=nil。
```

### T4 · PreviewWindowController + PreviewGutterView:删 tree + viewport 惰性上色 + 主题跟随系统
```yaml
id: T4
title: 控制器与 gutter 改造(删 tree + viewport 上色 + 跟随系统主题)
file_path: [Sources/PeekyKit/PreviewWindowController.swift, Sources/PeekyKit/PreviewGutterView.swift]
kind: AppKit 有状态层(构建 + 冒烟清单验收,不走双层单测)
work:
  - 删 tree 接线:移除 JSONOutlineView 实例与创建、jsonViewToggle 段控件、jsonViewModeChanged、
    presentJSONTree/showJSONTree、showPlainText 中的 tree 分支;PreviewTab 移除 jsonTreeVisible/collapseNestedJSON/jsonTreeIndex 字段。
    JSON/JSONL 恒走单一 textView 路径。
  - 移除 path bar、空格值预览 popover、记录尾摘要注解(drawRecordAnnotations)。保留坏行 gutter "!" 标 + 红底 + 行号。
  - viewport-only 惰性上色:新增逻辑——对 textView 可见 glyph 范围(glyphRange(forBoundingRectWithoutAdditionalLayout:visibleRect))
    对应字符范围按整行扩展,JSONHighlighter.tokenize(text, in: lineRange) → PeekyTheme.color(kind→ThemeColor, appearance)
    → layoutManager.setTemporaryAttributes([.foregroundColor:...], forCharacterRange:) 只给可见区上色;
    滚动(bounds/frame/didChange)与 layout pump 推进时增量补算可见区。挂 highlightGeneration + activeTabID 代际防护,
    renderActiveTab 开头 invalidate。temporary attributes 不改 textStorage。
  - 主题跟随系统:textView.backgroundColor = PeekyTheme.color(.editorBackground, appearance);
    基础前景 = .editorForeground;gutter 背景/行号 = .gutterBackground/.gutterText;坏行 = .invalidLine*。
    appearance 来自 effectiveAppearance;viewDidChangeEffectiveAppearance 时重设背景/基色并清除+重算可见区 temporary attributes。
    移除对 JSON/JSONL 施加固定 Dark Modern 的旧路径(usesDarkModernTheme 对 JSON/JSONL 不再生效;源码 shiki 路径不在本 scope,保持)。
  - PreviewGutterView:行号/背景色改从 PeekyTheme 按当前 appearance 取,替代 usesDarkModernTheme bool 分流。
  - 保留:isEditable=false/isSelectable=true + ⌘C 原生复制、maxSize=greatestFiniteMagnitude 两分支、
    clipsToBounds=true、layout pump、零布局副作用绘制。
dependencies: [T3, T1, T2]
acceptance: |
  swift build -c release 通过;冒烟清单:
  (1) 打开 .json → 单 textView、pretty-print、可见区分色、可选中 ⌘C;
  (2) 打开几万行 .jsonl → 冷启不卡、滚动时新可见区即时上色、坏行红标在;
  (3) 切换系统 Light/Dark → 背景/文字/token 色整体跟随,不残留另一套;
  (4) 无 tree 视图、无 tree/text 切换控件。
  用 background-gui-smoke 数值化手段(直跑二进制 + lldb 视图层级/layer contents + log stream)验证降级与主题。
```

### T5 · 删除孤立 tree 模块 + 集成验证 + 文档(架构师收尾)
```yaml
id: T5
title: 删除 tree 文件与测试 + 集成 + Living Documentation
file_path: [删除 JSONOutlineView.swift / JSONTreeIndex.swift / jsonTreeIndex{Visible,Hidden}.test.swift]
kind: 架构师亲自收尾
work:
  - 删除 Sources/PeekyKit/JSONOutlineView.swift、Sources/PeekyKit/JSONTreeIndex.swift。
  - 删除 Tests/visible/jsonTreeIndexVisible.test.swift、Tests/hidden/jsonTreeIndexHidden.test.swift。
  - 核 Package.swift(SPM glob,预期无需改)与全仓引用清零。
  - 全量 swift build -c release + 全量测试 + T4 冒烟复跑。
  - 更新 PROJECT.md(JSON/JSONL 功能行:formatted 文本 + 语义分色 + 跟随系统主题;移除树视图描述;新增 PeekyTheme/JSONHighlighter 模块地图与 data model)、
    PATTERNS.md(视图约定:JSON/JSONL 走单一 textView + viewport 惰性 JSON 高亮 + PeekyTheme;性能预算:JSON/JSONL formatted 不受 8MB 降级)、
    TECHSTACK.md(新增 PeekyTheme/JSONHighlighter)。
dependencies: [T4]
acceptance: |
  全量构建 + 测试全绿;冒烟通过;文档反映当前事实;git 无孤立引用。
```

## Dependency Graph
```
T1 (PeekyTheme) ────────┐
                        ├──→ T3 (PreviewRenderer) ──→ T4 (Controller+Gutter) ──→ T5 (删除+集成+文档)
T2 (JSONHighlighter) ───┘                              ↑
T1, T2 ───────────────────────────────────────────────┘ (T4 直接用 T1/T2 做 viewport 上色)
```
DAG 无环。

## Execution Waves
- **Wave 1**(并行,纯函数 test-first):T1 PeekyTheme、T2 JSONHighlighter
- **Wave 2**(deps T1,T2;纯函数 test-first):T3 PreviewRenderer
- **Wave 3**(deps T3,T1,T2;AppKit 冒烟):T4 Controller + Gutter
- **Wave 4**(deps T4;架构师收尾):T5 删除 + 集成 + 文档

## Status
Completed —— 全部 5 单元交付并验收。

- T1 PeekyTheme（hidden 10/10）、T2 JSONHighlighter（hidden 19/19，fresh 盲测重做）、T3 PreviewRenderer（hidden 16/16→删 collapse 测试后 15/15）、T4a 删 tree + 主题跟随系统、T4b 可视区惰性分色（均 release 编译 + 冒烟）、T5 删 JSONOutlineView/JSONTreeIndex/spike 脚本 + 文档。
- 终审（quality-security-reviewer）2 FAIL + 1 WARN 已修：viewport 上色改逐可见行 + 跳过 >64KB 超长行（修「超大单行值退化成全文级 tokenize」）、删 collapseNestedJSON 折叠死代码、删 recordAnnotations/summary 死代码、drawLabel 传 appearance。
- 最终：release 编译 0 error、全量 156 tests 全绿、5 万行 + 2MB 单行值冒烟不卡死。

## Follow-ups（本次未做，另行处理）
- **JSON/JSONL raw 模式主题统一**：Formatted/Raw 段控件（modeControl）对 JSON/JSONL 仍可切换，带行号打开（`peek foo.json:10`）会强制 mode=.raw；raw 走 `SyntaxHighlighter.highlightJSON`（硬编码色 + 钉死 dark modern，不跟随系统），与 formatted 的 PeekyTheme 不一致。统一需为 JSON formatted 建原文行→输出位置映射（JSONL 已有 targetLocationsByOriginalLine，JSON 缺）后移除 raw，或让 raw 也走 PeekyTheme。
- **全 app color theme 统一**：PeekyTheme 铺到侧栏 FileTreeView + 源码高亮 + Markdown 阅读列。
- **大文件明暗切换 benchmark**：`applyFollowSystemEditorColors` 在超大文件（100MB 级）明暗切换时全文 addAttribute 前景，未实测；单一 attribute run 应廉价，建议纳入冒烟。
- **JSONHighlighter.tokenize 的 `in:range` 参数**：生产改用子串直接 tokenize，range 参数仅测试用（YAGNI），可酌情精简。
