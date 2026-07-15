# PROJECT

## 目的
最快的 macOS 原生只读文件查看器，面向 AI 开发者的 CLI 工作流：`peek <path>` 弹出即可读（~0.4s），Markdown / JSON / JSONL / 源码 / XML 高保真渲染，repo 感知。本 repo 是 `zhangzhejian/Peeky` 的授权 fork，作为 peek 项目全原生形态的基底（前身 web 栈实现存档于 `~/Documents/peek` @ 64bb100）。

## 功能清单与状态
| 功能 | 状态 |
|---|---|
| 多窗口 + 窗口内多 tab（key window 复用路由） | ✅ |
| `peeky://open?path=&line=&cwd=` scheme（行列跳转）/ CLI `path:line[:column]` 直开 | ✅ |
| repo-aware 文件树侧栏（RepoRoot 发现 + DirectoryLister 惰性枚举） | ✅ |
| `peek` CLI（bin/peek，build-app.sh --install 联动安装） | ✅ |
| Markdown：swift-markdown 解析（GFM 全特性：表格/任务列表/删除线/自动链接/围栏代码块带高亮）+ Primer 排版数值 + 限宽阅读列（672pt 居中）+ 可点击大纲侧栏 | ✅ |
| JSON/JSONL 树视图：NSOutlineView + 惰性索引 + >100 分桶 + 折叠摘要 + Option 递归展开/折叠到第 N 层 + 空格值预览 + path bar（点语法/jq 复制）+ 树⇄原文切换 + 坏行红标 | ✅ |
| 源码语法高亮：JSC+Shiki，VSCode Dark Modern 原色，16 扩展名（py/ts/js/mjs/cjs/json/yaml/yml/toml/sh/bash/zsh/swift/ini/conf/config），流式分块上色 + 启动预热 + 超预算纯文本回退 | ✅ |
| 行号 gutter（NSRulerView，viewport-only，折行仅首视觉行编号）+ 全文可选中 ⌘C | ✅ |
| 复制五件套（全文 ⌥⌘C / 绝对路径 ⇧⌘C / 相对 repo root 路径 ⌥⇧⌘C / 文件本体 / path:line）+ ⌘E 用编辑器打开（VS Code/Cursor 带行定位） | ✅ |
| XML/plist 格式化 + 正则高亮 | ✅ |
| 拖放打开 / Finder Open With / 80MB·8MB·1.5M 三级性能预算 | ✅ |
| JSONL 表格视图（plan W4b）/ 端到端冷启计时验收（plan W5） | ⏳ 后续批次 |

## 核心 Data Model（概览）
- `OpenRequest { url, line?, column? }` —— CLI/Finder/scheme 三源统一的打开请求
- `LoadedText { text, encoding, isTruncated, kind }` —— `TextFileLoader` 产物
- `FileKind`：markdown/json/jsonl/yaml/xml/plist/csv/log/text
- `PreviewTab { url, document, mode, collapseNestedJSON, jsonTreeVisible, targetLine }` —— 窗口内 tab 状态
- `RenderedPreview { attributedText, note, outline, display, highlightLanguage? }` —— `PreviewRenderer` 纯函数输出；highlightLanguage 非 nil = 命中高亮接入范围（并触发 Dark Modern 编辑器主题）
- `JSONTreeIndex { nodes(前序节点表), rootIndices, errorIndex? }`，`Node { type, keyRange?, valueRange, childCount, firstChild?, nextSibling?, isInvalid, isTruncated }` —— 单遍扫描惰性索引，值按需从原文物化（80MB/430 万节点实测 0.35s）
- `HighlightedToken { text, colorHex }` / `HighlightedLine` / `HighlightChunk { firstLine, lines }` —— HighlightService 产物
- `JSONLineRecord { originalLine, range, isInvalid, summary }` —— JSONL 原文模式每记录元数据

## 模块地图（依赖自上而下）
```
main → AppDelegate → { OpenRequest, PreviewWindowController }
PreviewWindowController(~1.8k 行，唯一有状态 UI 控制器)
  → TextFileLoader / PreviewRenderer / PreviewDisplayMetadata / HighlightService
  → PreviewGutterView(NSRulerView) / JSONOutlineView / FileTreeView / Drop*View / FileKind
PreviewRenderer(纯编排) → MarkdownRenderer(swift-markdown visitor) / JSONFormatter
                          / XMLFormatter / SyntaxHighlighter / FileKind
叶子纯函数模块：JSONFormatter · JSONTreeIndex · XMLFormatter · MarkdownRenderer
               · SyntaxHighlighter · RepoRoot · DirectoryLister
服务单例：HighlightService（JSC + shiki-bundle，私有串行队列，故障永久降级不崩溃）
```

## 关键决策记录
- 渲染主体走 `NSTextView` + `NSAttributedString`，无 WebView；JSON/JSONL 默认视图为 NSOutlineView 树（2026-07-15 用户裁定），原文文本模式可切换。
- Markdown 解析层 = swiftlang/swift-markdown `exact 0.8.0`——本 repo 唯一获批第三方 SPM 依赖（2026-07-15 用户批准）。
- 高亮引擎 = JSC+Shiki（dark_modern 主题 include 链拍平）：构建期 esbuild 产 `Sources/PeekyKit/Resources/shiki-bundle.js` checked-in，运行期零 Node、零 WebKit。
- 编辑功能 wontfix（`.out-of-scope/file-editing.md`）；"看完顺手改"由 ⌘E 交系统默认编辑器承接。
- CLI 命令名 `peek`（用户肌肉记忆），app/repo 名沿用 Peeky；基线取 `main` 分支。
