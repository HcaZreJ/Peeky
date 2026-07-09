# PATTERNS

## Functional-core / 静态命名空间约定
- 格式化、解析、渲染决策一律为**无状态 `enum` 命名空间 + 静态纯函数**（`JSONFormatter`、`MarkdownRenderer`、`XMLFormatter`、`SyntaxHighlighter`、`PreviewRenderer`），输入→输出确定，便于双层测试。
- 有状态代码只住两处：`AppDelegate`（窗口数组、生命周期）与 `PreviewWindowController`（tab 状态 + AppKit 接线）。新交互 UI 挂 `PreviewWindowController`；新格式转换器做叶子纯函数模块。
- `PreviewRenderer` 是"决策层"：选 Raw/Formatted 路径、执行性能预算降级、委派叶子模块——不碰视图几何。

## 视图约定
- 一切内容渲染进单一 `NSTextView`（`DropTextView`）的 `NSAttributedString`；gutter（`PreviewGutterView`，与 scrollView 平级的独立 `NSView`，由 `DropTextView.onDidDraw` 回调驱动跟随重绘；macOS 26 起 `NSRulerView` 的 clipView.bounds 负偏移几何会让 `NSTextView` 正文不绘制，故 gutter 不走 ruler）与 overlay（记录分隔线/缩进参考线/注解）在 draw 时按**可见 glyph 范围**增量绘制，虚拟化交给 `NSLayoutManager`。
- 行号查找用预计算 line-start 偏移 + 二分。
- **自绘视图必须 `clipsToBounds = true`**：macOS 14 起 NSView 默认不裁剪，`draw(_:)` 收到的 dirtyRect 可远大于 bounds（窗口首帧为整窗），`fill(dirtyRect)` 会把背景涂到兄弟视图上（表现为兄弟"空白"，且 resize 救不回）。
- **textView 换行/不换行两分支都必须显式 `maxSize = greatestFiniteMagnitude`**：NSTextView 布局驱动的 frame 增长走 `setConstrainedFrameSize`，被钳在 maxSize 内，而默认 maxSize 是初始 frame（视口大小）——漏设时长文档 frame 长不过视口高度，scrollView 没有可滚动区域（`applyLineWrapping` 两分支均已设置）。
- **文档布局由渲染管线主动推进**：macOS 26 上 TextKit1 惰性布局不自行推进；`PreviewWindowController.startLayoutPump()` 在每次内容/换行模式变化后主线程分片 `ensureLayout`（每拍 64k 字符、`main.async` 让出 runloop），frame 渐进长高、交互不阻塞。gutter/overlay 绘制保持零布局副作用（`withoutAdditionalLayout` 变体）只读已就绪数据；程序化跳转（`scrollToLine` 等）在 `scrollRangeToVisible` 前对目标 range 先 `ensureLayout`。

## 性能预算（既有常量，新代码不得绕过）
- `TextFileLoader.maxPreviewBytes = 80MB`（超出截断读取并标注）
- `PreviewRenderer.richFormatLimit = 8MB`（超出静默降级 raw）
- `SyntaxHighlighter.highlightLimit = 1.5M UTF-16`（超出跳过高亮）
- 重计算放后台线程，UI 回主线程（上游同步渲染是已知债，新增代码不复制该模式）。

## 命名
- 类型 PascalCase；函数动词开头 camelCase；文件名 = 主类型名。
- 打开请求统一经 `OpenRequest` 归一化（CLI/Finder/scheme 三源），新入口不得绕过。

## 测试约定
- 叶子纯函数模块走双层 test-first（visible/hidden，Swift Testing testTarget，运行器见 DEVFLOW）。
- AppKit 视图/控制器层按架构师裁定走构建 + 冒烟清单验收。
