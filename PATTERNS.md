# PATTERNS

## Functional-core / 静态命名空间约定
- 格式化、解析、渲染决策一律做成**无状态 `enum` 命名空间 + 静态纯函数**（`JSONFormatter`、`MarkdownRenderer`、`XMLFormatter`、`SyntaxHighlighter`、`PreviewRenderer`），输入到输出确定，方便按 visible / hidden 双层测试。
- 有状态代码集中在两处：`AppDelegate`（窗口数组、生命周期）与 `PreviewWindowController`（tab 状态 + AppKit 接线）。新增交互 UI 挂在 `PreviewWindowController` 下；新增格式转换器写成叶子纯函数模块。
- `PreviewRenderer` 是"决策层"：选 Raw / Formatted 路径、执行性能预算降级、委派给叶子模块；不处理视图几何。

## 视图约定
- 文本类内容渲染进单一 `NSTextView`（`DropTextView`）的 `NSAttributedString`。JSON / JSONL 走同一 textView：`PreviewRenderer` 输出缩进格式化文本（`SyntaxHighlighter.monospace` 提供等宽基础），`PreviewWindowController.applyVisibleJSONHighlighting` 用 `JSONHighlighter` 对**可视区行对齐的子串**（`lineRange(for:)` 扩展）tokenize，通过 `layoutManager.setTemporaryAttributes` 只给屏幕可见行加语义色；滚动、布局泵、外观变化时重算，只处理可见区，从不 tokenize 全文，这样大文件 JSONL 也不阻塞。
- gutter 是 `PreviewGutterView`（`NSRulerView` 子类，scrollView 的 `verticalRulerView`）：`drawHashMarksAndLabels` 完全接管绘制，只枚举可见 glyph 范围，**每个逻辑行只在首个视觉行片段绘制行号**，软换行的续行不会重复编号（通过 line-start 偏移命中判断）。滚动同步用 `convert(NSZeroPoint, from: textView)` 做坐标平移，`bounds` / `frame` / `didChange` 三种通知触发重绘。overlay（记录分隔线 / 注解）同样按可见范围增量绘制，虚拟化由 `NSLayoutManager` 承担。
- 行号查找用预计算 line-start 偏移 + 二分。
- **异步分块高亮的代际防护**：流式高亮（`highlightStream`）的消费 Task 必须校验 `highlightGeneration` 与 `activeTabID` 两个条件，`renderActiveTab()` 开头统一调用 `invalidateHighlighting()`，取消在途 Task 并递增 generation，防止旧文档的迟到 chunk 覆盖新内容。高亮只调用 `addAttribute`，不重设整个 attributedString。
- **按钮外观统一走 `HoverButton`**：全 app 的按钮无壳、悬停出浅底（`labelColor` 0.14）、字形由 `secondaryLabelColor` 提到 `labelColor`、禁用落到 `tertiaryLabelColor`。三条约束不能省：① 悬停底的不透明度随控件面积取值——侧栏整行（240pt 宽）用 0.06 读得出来，20–30pt 见方的按钮要 0.14；② 语义色取 `.cgColor` 是按取值当时的绘制外观解析的一次性快照，一律包在 `effectiveAppearance.performAsCurrentDrawingAppearance { }` 里，并在 `viewDidChangeEffectiveAppearance()` 重跑；③ 悬停底画在 `bounds` 上，`alignmentRectInsets` 归零，否则一排等高按钮的 frame 互相错开两三个点、浅底参差。 ④ 重建悬停 tracking area 时只摘掉自己上一次装的那一块，走 `HoverTracking.reinstall(on:previous:)`——`NSView.toolTip` 的浮出由 `NSToolTipManager` 挂在同一个 `trackingAreas` 数组里的一块 area 承载，清空整个数组会把它一并删掉，而 `toolTip` 属性值仍在，只读代码看不出 tooltip 已经不浮出了。 顶栏动作按钮另外挂一行文字：`caption` 非空时按 `imageAbove` 排版，符号显式定到 13pt（不定的话默认尺寸会把文字挤出按钮框）、文字 9pt regular（比 metaLabel 的 11pt 低一档）、按钮高 36、宽取文字宽加左右各 6pt 内边距且下限 34；文字色与 `contentTintColor` 同一个值，图标与文字同进同退。 符号一律经 `ToolbarSymbol.uniform` 交给按钮，它做两件事：画进统一画布（24×16），解决 `.imageAbove` 按整块居中导致的文字基线参差；把符号的**墨迹**缩放到同一高度（14pt）再摆到画布正中，解决 SF Symbol 墨高天生不一（13pt 下 `doc.on.doc` 墨高 16、`folder` 12、`ellipsis` 只有 3）导致的图标一颗高一颗矮。选符号时宽高比控制在 1.6 以内：等高之后墨宽 = 14 × 宽高比，宽高比 2:1 的字母组与 4:1 的标点会横着撑出画布。
- **顶栏控件组不吸收富余宽度**：标题钉左、控件组钉右，中间一条 `>= 12` 的空隙吃掉全部富余宽度。控件组之间的间距编码分组关系（组内 8 / 两小组 12 / 两大组 20），把它们放进一个两端都钉死的 `NSStackView` 会让富余宽度按 hugging 优先级分摊到这些间距上，6 个按钮被拆成两摊。标题是唯一可压缩的一侧。
- **磁盘对账约定**：界面缓存与磁盘之间的一致性走三层——纯函数决定范围（`FileTreeRefresh.scope`：FSEvents 送来的变化路径 × 已展开目录 × 最前 tab 的文件）、纯函数决定合并（`FileTreeNode.reconcile`：按 URL 复用节点实例，保住 `NSOutlineView` 的展开态与选中行）、视图只负责执行与还原（`FileTreeView.refresh(directories:)` / `refreshAll()`）。刷新范围恒等于「此刻看得见的东西」：没展开过的目录与后台 tab 的文件不进范围，各自在展开时与切过去时才对账。重读整份文件之前先比 `FileStamp { size, mtime }`，指纹相同就不读。
- **FSEvents 服务约定**（`DirectoryWatcher`）：每窗口一个实例盯当前树根，`kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer` + 0.4s latency 让单次保存立刻送达、批量写入合并成个位数次回调；C 回调在私有后台队列上只做取路径与取 flag，回主线程再交给控制器；换树根时先停旧 stream，`windowWillClose` 撤监听。
- **JSC 服务约定**（以 `HighlightService` 为参照实现）：JSContext 单例 + 私有串行队列承载所有 JS 执行；预算与合法性检查在 Swift 侧前置，不进入 JS；任何 bundle 缺失或 JS 异常一律永久降级返回 nil，加一条一次性日志，运行不中断；资源寻径包含多个候选（`.app` 的 `Contents/Resources` 与 `swift build` 输出目录），寻径失败同样降级。
- **自绘视图必须设置 `clipsToBounds = true`**：macOS 14 起 NSView 默认不裁剪，`draw(_:)` 收到的 dirtyRect 可能远大于 bounds（窗口首帧为整窗），`fill(dirtyRect)` 会把背景涂到兄弟视图上（表现为兄弟视图"空白"，且 resize 之后也不恢复）。
- **textView 的换行和不换行两个分支都必须显式设置 `maxSize = greatestFiniteMagnitude`**：NSTextView 的 frame 增长通过 `setConstrainedFrameSize` 驱动，被钳制在 maxSize 内，而默认 maxSize 等于初始 frame（视口大小）；若未显式放开，长文档的 frame 无法超过视口高度，scrollView 就没有可滚动区域（`applyLineWrapping` 两个分支都已设置）。
- **文档布局由渲染管线主动驱动**：macOS 26 上 TextKit1 的惰性布局不会自行推进；`PreviewWindowController.startLayoutPump()` 在内容或换行模式变化后，在主线程分片调用 `ensureLayout`（每次处理 64k 字符，用 `main.async` 让出 runloop），frame 逐步增高，交互不阻塞。gutter 与 overlay 绘制不触发额外布局（使用 `withoutAdditionalLayout` 变体），只读已就绪数据；程序化跳转（`scrollToLine` 等）在 `scrollRangeToVisible` 之前先对目标 range 调用 `ensureLayout`。
- **配色集中在 `PeekyTheme`**：浅色与深色两套语义 palette 在文件顶部由两张 `[ThemeColor: hex]` 常量表定义，渲染代码按语义 token（`jsonString` / `jsonKey` / `editorBackground` 等）取色，不写死具体颜色；换配色时只改常量。编辑器主题分三条路径（`applyEditorTheme`）：`followsSystemAppearance`（JSON / JSONL）设 appearance 为 nil 跟随系统，背景 / 全文基础前景 / gutter / 坏行经 `resolveAppearance(effectiveAppearance)` 取色，系统明暗切换通过 `DropTextView.onEffectiveAppearanceChanged` 回调重刷可视区；`usesDarkModernTheme`（源码 shiki）锁定为 darkAqua；其它情况使用 `.textBackgroundColor`。

## 性能预算（既有常量，新代码不得绕过）
- `TextFileLoader.maxPreviewBytes = 80MB`（超出截断读取并标注）
- `PreviewRenderer.richFormatLimit = 8MB`（超出后自动降级为 raw；**JSON / JSONL 例外**：即使超 8MB 仍然缩进格式化，靠可视区惰性高亮 + 布局泵支持，只受 `TextFileLoader` 80MB 上限约束）
- `SyntaxHighlighter.highlightLimit = 1.5M UTF-16`（超出跳过高亮）
- 重计算放在后台线程，UI 回到主线程执行（上游存在同步渲染的技术债，新增代码不沿用这一做法）。

## 命名
- 类型用 PascalCase；函数以动词开头，camelCase；文件名等于主类型名。
- 打开请求统一经过 `OpenRequest` 归一化（CLI / Finder / scheme 三源），新入口不得绕过。

## 测试约定
- 叶子纯函数模块采用双层 test-first（visible / hidden，Swift Testing testTarget，运行器详见 DEVFLOW）。
- AppKit 视图 / 控制器层按架构师判断，通过构建 + 手动冒烟清单验收。
