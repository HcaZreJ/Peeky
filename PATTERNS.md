# PATTERNS

## Functional-core / 静态命名空间约定
- 格式化、解析、渲染决策一律为**无状态 `enum` 命名空间 + 静态纯函数**（`JSONFormatter`、`MarkdownRenderer`、`XMLFormatter`、`SyntaxHighlighter`、`PreviewRenderer`），输入→输出确定，便于双层测试。
- 有状态代码只住两处：`AppDelegate`（窗口数组、生命周期）与 `PreviewWindowController`（tab 状态 + AppKit 接线）。新交互 UI 挂 `PreviewWindowController`；新格式转换器做叶子纯函数模块。
- `PreviewRenderer` 是"决策层"：选 Raw/Formatted 路径、执行性能预算降级、委派叶子模块——不碰视图几何。

## 视图约定
- 一切内容渲染进单一 `NSTextView`（`DropTextView`）的 `NSAttributedString`；gutter（`PreviewGutterView`，与 scrollView 平级的独立 `NSView`，监听 clipView bounds / textView frame 变化重绘；macOS 26 起 `NSRulerView` 的 clipView.bounds 负偏移几何会让 `NSTextView` 正文不绘制，故 gutter 不走 ruler）与 overlay（记录分隔线/缩进参考线/注解）在 draw 时按**可见 glyph 范围**增量绘制，虚拟化交给 `NSLayoutManager`。
- 行号查找用预计算 line-start 偏移 + 二分。

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
