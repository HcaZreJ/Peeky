# PROJECT

## 目的
最快的 macOS 原生只读文件查看器，面向 AI 开发者的 CLI 工作流：`peek <path>` 弹出即可读（~0.4s），Markdown / JSON / JSONL / XML / 源码高亮渲染，repo 感知。本 repo 是 `zhangzhejian/Peeky` 的授权 fork，作为 peek 项目全原生形态的基底（前身 web 栈实现存档于 `~/Documents/peek` @ 64bb100）。

## 功能清单与状态
| 功能 | 状态 |
|---|---|
| 多窗口 + 窗口内多 tab（key window 复用路由） | ✅ 上游现成 |
| `peeky://open?path=&line=&cwd=` scheme（行列跳转） | ✅ 上游现成 |
| CLI 参数 `path:line[:column]` 直开 | ✅ 上游现成 |
| Markdown 渲染（标题/列表/引用/内联/NSTextTable 表格）+ 可点击大纲侧栏 | ✅ 上游现成 |
| JSON 格式化 + 正则高亮 + 嵌套折叠 toggle | ✅ 上游现成 |
| JSONL 逐行格式化 + 坏行红标 + gutter 记录标记 + 记录摘要注解 | ✅ 上游现成 |
| XML/plist 格式化 + 正则高亮 | ✅ 上游现成 |
| 拖放打开 / Finder Open With / 80MB·8MB·1.5M 三级性能预算 | ✅ 上游现成 |
| 转型（→ .claude/plans/2026-07-03-peek-native.md） | 🚧 见 plan |

## 核心 Data Model（概览）
- `OpenRequest { url, line?, column? }` —— CLI/Finder/scheme 三源统一的打开请求
- `LoadedText { text, encoding, isTruncated, kind }` —— `TextFileLoader` 产物
- `FileKind`：markdown/json/jsonl/yaml/xml/plist/csv/log/text
- `PreviewTab { url, document, mode, collapseNestedJSON, targetLine }` —— 窗口内 tab 状态
- `RenderedPreview { attributedText, note, outline, display }` —— `PreviewRenderer` 纯函数输出
- `JSONLineRecord { originalLine, range, isInvalid, summary }` —— JSONL 每记录元数据

## 模块地图（15 文件，~3.5k 行，依赖自上而下）
```
main → AppDelegate → { OpenRequest, PreviewWindowController }
PreviewWindowController(1031 行,唯一有状态 UI 控制器)
  → TextFileLoader / PreviewRenderer / PreviewDisplayMetadata
  → PreviewGutterView / Drop*View / FileKind
PreviewRenderer(纯编排) → MarkdownRenderer / JSONFormatter / XMLFormatter
                          / SyntaxHighlighter / FileKind
叶子纯函数模块：JSONFormatter · XMLFormatter · MarkdownRenderer · SyntaxHighlighter
```

## 关键决策记录
- 基线取 `main` 分支（含 JSONL gutter/overlay 富视图资产）；上游 `release` 的正则级源码高亮不合入——高亮引擎按 plan 决策实现（保真为硬指标）。
- 渲染全走 `NSTextView` + `NSAttributedString`，无 WebView。
- CLI 命令名 `peek`（用户肌肉记忆），app/repo 名沿用 Peeky。
