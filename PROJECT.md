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
| JSON/JSONL：pretty-print 缩进 + 语义分色（key/字符串/数字/bool/null/标点）+ 原生选中复制 ⌘C，可视区惰性上色（NSLayoutManager temporary attributes，只算屏幕可见行）扛几万行大文件，跟随系统 light/dark，坏行红标 | ✅ |
| 源码语法高亮：JSC+Shiki，VSCode Dark Modern 原色，16 扩展名（py/ts/js/mjs/cjs/json/yaml/yml/toml/sh/bash/zsh/swift/ini/conf/config），流式分块上色 + 启动预热 + 超预算纯文本回退 | ✅ |
| 行号 gutter（NSRulerView，viewport-only，折行仅首视觉行编号）+ 全文可选中 ⌘C | ✅ |
| 复制五件套（全文 ⌥⌘C / 绝对路径 ⇧⌘C / 相对 repo root 路径 ⌥⇧⌘C / 文件本体 / path:line）+ ⌘E 用编辑器打开（VS Code/Cursor 带行定位） | ✅ |
| XML/plist 格式化 + 正则高亮 | ✅ |
| 拖放打开 / Finder Open With / 80MB·8MB·1.5M 三级性能预算 | ✅ |
| 端到端冷启计时验收（plan W5） | ⏳ 后续批次 |
| 全 app color theme 统一（PeekyTheme 铺到侧栏/源码高亮/Markdown） | ⏳ 后续工程 |

## 核心 Data Model（概览）
- `OpenRequest { url, line?, column? }` —— CLI/Finder/scheme 三源统一的打开请求
- `LoadedText { text, encoding, isTruncated, kind }` —— `TextFileLoader` 产物
- `FileKind`：markdown/json/jsonl/yaml/xml/plist/csv/log/text
- `PreviewTab { url, document, mode, targetLine, targetColumn }` —— 窗口内 tab 状态
- `RenderedPreview { attributedText, note, outline, display, highlightLanguage?, usesJSONHighlighting, followsSystemAppearance }` —— `PreviewRenderer` 纯函数输出；highlightLanguage 非 nil = 源码命中 shiki（Dark Modern 主题）；usesJSONHighlighting = JSON/JSONL 走可视区惰性语义分色；followsSystemAppearance = 编辑器区走 PeekyTheme 跟随系统明暗
- `PeekyTheme`：集中式主题源，light(GitHub Light)/dark(VSC Dark Modern) 两套语义 palette（`ThemeColor` × hex 常量表，换色只改常量）；`resolveAppearance(NSAppearance?)` 映射系统明暗
- `JSONHighlighter.JSONToken { kind, range }`（kind ∈ key/string/number/boolLiteral/nullLiteral/punctuation）—— 原生单遍 JSON 词法分色器，按 UTF-16 子范围 tokenize，供可视区惰性上色
- `HighlightedToken { text, colorHex }` / `HighlightedLine` / `HighlightChunk { firstLine, lines }` —— HighlightService 产物
- `JSONLineRecord { originalLine, range, isInvalid, summary }` —— JSONL 原文模式每记录元数据

## 模块地图（依赖自上而下）
```
main → AppDelegate → { OpenRequest, PreviewWindowController }
PreviewWindowController(~1.8k 行，唯一有状态 UI 控制器)
  → TextFileLoader / PreviewRenderer / PreviewDisplayMetadata / HighlightService
  → PreviewGutterView(NSRulerView) / FileTreeView / Drop*View / FileKind / PeekyTheme / JSONHighlighter
PreviewRenderer(纯编排) → MarkdownRenderer(swift-markdown visitor) / JSONFormatter
                          / XMLFormatter / SyntaxHighlighter / FileKind
叶子纯函数模块：JSONFormatter · JSONHighlighter · PeekyTheme · XMLFormatter · MarkdownRenderer
               · SyntaxHighlighter · RepoRoot · DirectoryLister
服务单例：HighlightService（JSC + shiki-bundle，私有串行队列，故障永久降级不崩溃）
```

## 关键决策记录
- 渲染主体走 `NSTextView` + `NSAttributedString`，无 WebView；JSON/JSONL = pretty-print 文本 + `JSONHighlighter` 可视区惰性语义分色 + 原生选中复制，唯一渲染形态（2026-07-20 用户裁定）。
- 配色集中于 `PeekyTheme`（light=GitHub Light / dark=VSC Dark Modern 两套语义 palette，换色只改 hex 常量），跟随系统 light/dark；当前接入 JSON/JSONL 渲染区 + gutter，全 app 主题统一（侧栏/源码/Markdown）为后续工程。
- Markdown 解析层 = swiftlang/swift-markdown `exact 0.8.0`——本 repo 唯一获批第三方 SPM 依赖（2026-07-15 用户批准）。
- 高亮引擎 = JSC+Shiki（dark_modern 主题 include 链拍平）：构建期 esbuild 产 `Sources/PeekyKit/Resources/shiki-bundle.js` checked-in，运行期零 Node、零 WebKit。
- 编辑功能 wontfix（`.out-of-scope/file-editing.md`）；"看完顺手改"由 ⌘E 交系统默认编辑器承接。
- CLI 命令名 `peek`（用户肌肉记忆），app/repo 名沿用 Peeky；基线取 `main` 分支。
