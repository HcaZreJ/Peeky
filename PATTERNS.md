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
