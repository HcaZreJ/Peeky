# PROJECT

## 目的
Peeky 是 macOS 上的原生只读文件查看器，面向从终端触发的开发者工作流：`peek path[:line[:column]]` 打开文件并跳到指定行。支持 Markdown、JSON、JSONL、源码（9 种语言的 shiki 语法高亮）、XML、plist、YAML 等格式；侧栏能识别 `.git` / `.hg` / `.svn`，支持浏览当前代码仓库。本 repo 是 `zhangzhejian/Peeky` 的 fork。

## 功能清单与状态
| 功能 | 状态 |
|---|---|
| 多窗口 + 每窗口多 tab；打开新文件时复用当前 key window；⌘W 关闭当前文件（窗口已无文件时关闭窗口），⇧⌘W 关闭窗口 | ✅ |
| `peeky://open` URL scheme + CLI `path:line[:column]` 支持行列跳转 | ✅ |
| 侧栏文件树：`RepoRoot` 识别代码仓库根，`DirectoryLister` 按需枚举一级子项 | ✅ |
| 文件树与磁盘保持同步：FSEvents 监听树根，已展开目录的内容一变就地重列、最前 tab 的文件内容一变就地重读（留在原阅读位置）；展开某目录、⌘R（View 菜单 Refresh from Disk）同样触发对账。刷新范围收窄到「此刻看得见的东西」——没展开的目录与后台 tab 的文件走惰性，各自在展开时 / 切过去时才对账 | ✅ |
| 侧栏三个 tab（Open / Files / Contents）单选切换；Markdown 无大纲时 Contents 置灰回退 Files；选择通过 UserDefaults 持久化 | ✅ |
| `peek` shell 包装（`bin/peek`），`build-app.sh --install` 一并部署到 `~/Applications` 与 `~/.local/bin` | ✅ |
| Markdown：swift-markdown 解析为 HTML（`MarkdownHTMLRenderer`），WKWebView 用 github-markdown.css 渲染；支持表格、任务列表、嵌套引用、围栏代码块、标题分隔线等 GFM 特性；侧栏大纲支持点击跳转；正文链接点击交系统默认浏览器/程序打开（文档内锚点留在页内），预览停留在当前文档；代码块内语法高亮跟踪于 issue #16 | ✅ |
| JSON / JSONL：缩进格式化 + 词法高亮（键 / 字符串 / 数字 / bool / null / 标点）+ ⌘C 选中复制；可视区惰性上色（`NSLayoutManager` 临时属性，只处理屏幕可见行），大文件不阻塞；跟随系统明暗；JSONL 解析失败的行以红色标注 | ✅ |
| JSON / JSONL 交互：gutter 折叠三角（对象和数组点击折叠/展开，行号连续）、折叠占位符 `⟷`、缩进虚线导轨、底部状态栏（行、列、选中字符数、文件大小，坐标以源文件为准）、双击选中整个 element、折叠状态下复制展开为完整 JSON；折叠映射与坐标计算是纯函数模块（`JSONFoldMap` / `JSONFoldComposer`），配色新增 7 个语义 token 到 `PeekyTheme` | ✅ |
| JSON / JSONL 节点路径：光标所在行的 jq 路径常驻显示在底部状态栏（超 60 字符中段省略），选区浮动 "jq path" chip 一键复制——点击复制 jq 表达式（`.users[0].user.phone`，可直接 `jq '<粘贴>' file.json`），⌥ 点击复制点分形态（`users.0.user.phone`）；逐行路径索引是纯函数模块 `JSONPathMap`（父指针树，避免逐行物化路径数组），仅在 JSON 结构解析成功时建立，语法错误的文件不显示推测路径 | ✅ |
| 源码语法高亮：JavaScriptCore + shiki，VS Code Dark Modern 主题，覆盖 16 个扩展名（py / ts / js / mjs / cjs / json / yaml / yml / toml / sh / bash / zsh / swift / ini / conf / config）；流式分块高亮 + 启动预热；超过 1.5M UTF-16 字符时回退为等宽原文 | ✅ |
| 行号 gutter（`NSRulerView`，只渲染可视区；软换行的续行不编号）；全文可选中 ⌘C | ✅ |
| 顶栏 6 个图标按钮成组停在右端（复制组 4 个组内间距 8，定位组 2 个组内间距 8，两组之间 12；窗口变宽时富余宽度全部落进标题与按钮组之间的空隙，按钮组不被拉开）：全文（⌥⌘C）、文件名、绝对路径（⇧⌘C）、相对仓库根路径（⌥⇧⌘C；无仓库时置灰）；Reveal in Finder；⋯ 溢出菜单包含 Wrap Lines 开关（markdown 走 WebView，该项对它无作用因而置灰）。全部按钮无壳 + 悬停浅底（`HoverButton`）；选区触发浮动 chip（`NSTextView` 与 Markdown WebView 两条路径，Markdown 场景通过源行号启发式定位）——"path:line" 恒有，JSON / JSONL 且路径非根时左侧并排 "jq path"，两者成组右对齐选区尾端后整体做越界校正 | ✅ |
| XML / plist 缩进格式化 + 正则语法高亮 | ✅ |
| 拖放打开 / Finder 打开方式 / 三档大小上限（文件读取 80 MB、富格式化 8 MB、语法高亮 1.5M UTF-16 字符） | ✅ |
| 端到端冷启计时验收（plan W5） | ⏳ 后续 |
| 全局主题统一（`PeekyTheme` 覆盖侧栏 / 源码高亮 / Markdown） | ⏳ 后续 |

## 核心 Data Model（概览）
- `OpenRequest { url, line?, column? }`：CLI / Finder / scheme 三个来源统一后的打开请求
- `LoadedText { text, encoding, isTruncated, kind }`：`TextFileLoader` 的读取产物
- `FileKind`：markdown / json / jsonl / yaml / xml / plist / csv / log / text
- `PreviewTab { url, document, mode, targetLine, targetColumn, stamp }`：窗口内 tab 状态。`stamp` 是读到 `document` 时磁盘上的 `FileStamp { size, mtime }`，磁盘事件到达时先比它，相等就不重读整个文件
- `FileTreeNode { url, name, isDirectory, isErrorPlaceholder, childrenLoaded, children }`：文件树节点。`reconcile(existing:entries:)` 把磁盘最新一级列表对账进已缓存的子项——次序跟随 `entries`，URL 未变的条目复用原节点实例（`NSOutlineView` 按实例记展开态，换实例会把展开的子树折回去），新 URL 建新节点，磁盘上消失的丢弃
- `FileTreeRefresh.Scope { directoriesToReload, touchesActiveFile }`：一次磁盘变化要触发的刷新范围。`scope(changedPaths:mustScanSubDirectories:loadedDirectories:activeFileURL:)` 是纯路径运算，路径比较前统一解析 symlink、剥前导 `/private`、去尾斜杠
- `RenderedPreview { attributedText, note, outline, display, highlightLanguage?, usesJSONHighlighting, followsSystemAppearance, jsonStructureIsValid }`：`PreviewRenderer` 的输出。`highlightLanguage` 非 nil 表示走 shiki 高亮（Dark Modern）；`usesJSONHighlighting` 为 true 表示 JSON / JSONL 走可视区惰性词法高亮；`followsSystemAppearance` 为 true 表示编辑器区通过 `PeekyTheme` 跟随系统明暗；`jsonStructureIsValid` 为 true 表示源文本是结构解析成功的 JSON，控制器据此决定是否建立 `JSONPathMap` 路径索引
- `PeekyTheme`：两套语义 palette（浅色 GitHub Light、深色 VS Code Dark Modern），`ThemeColor` 枚举 × hex 常量表，换色只改常量；`resolveAppearance(NSAppearance?)` 将系统外观映射到对应 palette
- `JSONHighlighter.JSONToken { kind, range }`（kind ∈ key / string / number / boolLiteral / nullLiteral / punctuation）：JSON 词法分析器，单遍扫描按 UTF-16 子范围 tokenize，为可视区惰性高亮提供 token
- `HighlightedToken { text, colorHex }` / `HighlightedLine` / `HighlightChunk { firstLine, lines }`：`HighlightService` 的产物
- `JSONLineRecord { originalLine, range, isInvalid, summary }`：JSONL 原文模式下每条记录的元数据
- `JSONPathSegment`（key(String) / index(Int)）+ `JSONPathMap { nodes: [Node], lineNode: [Int32] }`：pretty JSON 文本的逐行节点路径索引。父指针树存储——`Node = { parent: Int32, segment }`，`lineNode` 每行一个节点下标（-1 为根），`path(line:)` 沿 parent 回溯物化。`build` 单遍 UTF-16 扫描；空行是 JSONL 记录边界（清栈隔离坏行），但空行紧跟 `{` / `[` 时属于空容器内部不清栈。`jqExpression` 产出可直接执行且可安全放进 shell 单引号的表达式（非标识符 key 走 `."..."`，单引号输出为 unicode 转义）；`dotPath` 产出 `users.0.user.phone`

## 模块地图（依赖自上而下）
```
main → AppDelegate → { OpenRequest, PreviewWindowController }
PreviewWindowController(约 1.8k 行,唯一持有状态的 UI 控制器)
  → TextFileLoader / PreviewRenderer / MarkdownHTMLRenderer / MarkdownLinkPolicy / PreviewDisplayMetadata / HighlightService
  → WKWebView(Markdown 预览) / PreviewGutterView(NSRulerView) / FileTreeView / DirectoryWatcher / Drop*View / FileKind / PeekyTheme / JSONHighlighter
FileTreeView(NSOutlineView 惰性树) → FileTreeNode(节点 + reconcile) / DirectoryLister
MarkdownHTMLRenderer(Markdown → HTML,交给 WebView);PreviewRenderer(非 Markdown 的路径选择与编排)
  → JSONFormatter / XMLFormatter / SyntaxHighlighter / MarkdownRenderer(大纲抽取 + 超 8 MB 时的兜底) / FileKind
叶子纯函数模块:JSONFormatter · JSONHighlighter · JSONPathMap(逐行节点路径索引 + jq/点分序列化) · PeekyTheme · MarkdownHTMLRenderer · MarkdownLinkPolicy(链接点击导航分流) · XMLFormatter · MarkdownRenderer · SyntaxHighlighter · RepoRoot · DirectoryLister · FileTreeRefresh(磁盘事件 → 刷新范围)
服务单例:HighlightService(JSC + shiki-bundle,私有串行队列,资源缺失或 JS 异常时永久降级为纯文本)
服务实例:DirectoryWatcher(FSEvents,每窗口一个,盯当前树根;后台队列收事件、回主线程交回调)
```

## 关键约定
- Markdown 渲染走 `WKWebView` + github-markdown.css；其它文件走 `NSTextView` + `NSAttributedString`。
- JSON / JSONL 唯一渲染形态是缩进格式化文本 + `JSONHighlighter` 可视区惰性词法高亮 + 原生选中复制；交互模式对齐 codebeautify.org/jsonviewer 的 Ace code 视图，plan 见 `.claude/plans/json-viewer-parity.md`；工具栏按钮（compact / sort / transform / undo-redo）跟踪于 issues #21–#24。
- 配色集中在 `PeekyTheme`，两套语义 palette（浅色 GitHub Light、深色 VS Code Dark Modern），换色只改 hex 常量，跟随系统明暗；已覆盖 JSON / JSONL 渲染区和 gutter，侧栏 / 源码 / Markdown 的主题统一仍在后续。
- Markdown 解析层用 `swiftlang/swift-markdown` `exact 0.8.0`，是本 repo 唯一的第三方 SPM 依赖。
- 高亮引擎是 JavaScriptCore + shiki（`dark_modern` include 链在构建期扁平化）。产物 `Sources/PeekyKit/Resources/shiki-bundle.js` 由 esbuild 打包并 checked-in；运行期不需要 Node，高亮引擎本身不依赖 WebKit（Markdown 预览另外使用 WKWebView）。
- 文件树的任何一次「与磁盘对账」都走 `FileTreeNode.reconcile`，复用 URL 未变的节点实例，展开态与选中行因此天然保住；`FileTreeView.reload(root:)` 只用于换树根。
- 刷新范围由 `FileTreeRefresh.scope` 一处决定，`FileTreeView.loadedDirectoryURLs` 提供「哪些目录已经列过磁盘」这一事实。
- 编辑功能超出范围（见 `.out-of-scope/file-editing.md`）；⌘E 用系统默认编辑器打开当前文件。
- CLI 命令名 `peek`，app 与 repo 名沿用 Peeky；基线是 `main` 分支。
