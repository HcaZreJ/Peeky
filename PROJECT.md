# PROJECT

## 目的
Peeky 是 macOS 上的原生只读文件查看器，面向从终端触发的开发者工作流：`peek path[:line[:column]]` 打开文件并跳到指定行。支持 Markdown、JSON、JSONL、源码（9 种语言的 shiki 语法高亮）、XML、plist、YAML 等格式；侧栏能识别 `.git` / `.hg` / `.svn`，支持浏览当前代码仓库。在终端里运行 `peek` 时直接在当前终端分栏里打开终端版（`peek-tui`），不另开窗口、不和终端抢前台；`peek --app` 打开 app 窗口。本 repo 是 `zhangzhejian/Peeky` 的 fork。

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
| 顶栏 6 个动作按钮成组停在右端，每颗一个自绘图标（墨迹长边 15pt，逐颗相同）加一行 9pt 文字（复制组 4 个组内间距 8，定位组 2 个组内间距 8，两组之间 12；窗口变宽时富余宽度全部落进标题与按钮组之间的空隙，按钮组不被拉开）：Content 全文（⌥⌘C）、Name 文件名、Full path 绝对路径（⇧⌘C）、Rel path 相对仓库根路径（⌥⇧⌘C；无仓库时置灰）；Finder 即 Reveal in Finder；More 溢出菜单包含 Wrap Lines 开关（markdown 走 WebView，该项对它无作用因而置灰）。全部按钮无壳 + 悬停浅底（`HoverButton`）；选区触发浮动 chip（`NSTextView` 与 Markdown WebView 两条路径，Markdown 场景通过源行号启发式定位）——"path:line" 恒有，JSON / JSONL 且路径非根时左侧并排 "jq path"，两者成组右对齐选区尾端后整体做越界校正 | ✅ |
| 顶栏文件名下方的副标题以文件最后更改时间开头：`最后更改于：2026 年 10 月 20 日 14:32:05  \|  Markdown  \|  11 KB  \|  UTF-8`（本地时区、24 小时制、精确到秒，取自读文件时的磁盘修改时间；文件被外部改写、重读之后随之刷新），用来对上文件是哪次会话里生成或改写的。副标题放不下时从尾部省略，时间一段最后才被截，不撑宽窗口 | ✅ |
| XML / plist 缩进格式化 + 正则语法高亮 | ✅ |
| 拖放打开 / Finder 打开方式 / 三档大小上限（文件读取 80 MB、富格式化 8 MB、语法高亮 1.5M UTF-16 字符） | ✅ |
| 最近打开的文件：File ▸ Open Recent 子菜单 + 空白窗口（没打开文件时）里的 Recent Files 列表，最多 20 条、最新在前、跨重启保留（UserDefaults `PeekyRecentFiles`），Clear Menu / Clear 清空。每条写文件名 + 位置（仓库名、`仓库 › worktree 名`、或仓库外的 `~` 缩写父目录；同一仓库内同名才补目录）。打不开的条目保留、置灰、不可点，行尾写原因：所在 git worktree 整个不在了写 `Worktree deleted`，其余写 `File moved or deleted`；悬停提示给完整路径与一句说明 | ✅ |
| 终端版 `peek-tui`：在当前终端里全屏打开文件或目录，`q` 退出；`peek` 在终端里运行时 exec 它，`--app` 或标准输出不是终端时走 app；随 app 打包在 `Contents/MacOS/`；输出到管道时输出排好版的纯文字 | ✅（Ghostty 分栏实测待用户） |
| 终端版显示：纯文本、源码（shiki 高亮，固定 Dark Modern 底）、XML / plist、Markdown（按终端宽度排版：表格、列表、引用、代码块、链接 OSC 8；kitty 下 H1 / H2 用 OSC 66 真文字放大）、JSON / JSONL（折叠、jq 路径常驻状态栏、坏行标红）；超过 1 MB 需格式化的文件先显示原文再替换 | ✅ |
| 终端版侧栏：Files（版本库根的文件树，磁盘变化 1 秒内同步）与 Contents（Markdown 1–4 级标题大纲）；当前文件被改写后自动重读、视口按源行留在原处 | ✅ |
| 终端版交互：鼠标拖选 / 双击选词 / 三击选行，`y` / ⌘C 复制（装饰不复制，JSON 折叠态复制完整内容）；复制文件名 / 绝对路径 / 相对路径 / 全文 / 「路径:行号」（选中时状态栏显示）；`:行号` 跳行；`?` 帮助浮层；配色跟随终端明暗（以 OSC 11 背景色为准） | ✅ |
| 端到端冷启计时验收（plan W5） | ⏳ 后续 |
| 全局主题统一（`PeekyTheme` 覆盖侧栏 / 源码高亮 / Markdown） | ⏳ 后续 |

## 核心 Data Model（概览）
- `OpenRequest { url, line?, column? }`：CLI / Finder / scheme 三个来源统一后的打开请求
- `RecentFiles.Entry { path, openedAt, origin }`：一条最近文件，`origin` ∈ `.folder` / `.repository(name, rootPath)` / `.worktree(repositoryName, worktreeName, rootPath)`，在文件成功读进 tab 的那一刻由 `RepoRoot.discover` + 根下 `.git` 文件内容（`gitdir: …/worktrees/<名>`）判定并记下——worktree 删掉后 `.git` 跟着没了，显示时只能靠这份记录说明原因。可用性（`available` / `worktreeRemoved` / `missing`）每次显示时现查磁盘；`RecentFiles.Item` 是菜单条目与空白窗口行共用的显示文字
- `LoadedText { text, encoding, isTruncated, kind }`：`TextFileLoader` 的读取产物
- `FileKind`：markdown / json / jsonl / yaml / xml / plist / csv / log / text
- `TUIState`（PeekTUI）：终端版的全部界面状态——当前文档（`OpenedDocument`：按行存的文本、显示方式、高亮、Markdown 排版结果、JSON 折叠视图、文件戳）、视口、侧栏（`SidebarState` + 值类型文件树 `FileTree`）、焦点、选区（`TextSelection`，显示行 + 视觉列）、明暗与终端能力；只经 `TUIReducer.reduce` 修改
- `PreviewTab { url, document, mode, targetLine, targetColumn, stamp }`：窗口内 tab 状态。`stamp` 是读到 `document` 时磁盘上的 `FileStamp { size, mtime }`，磁盘事件到达时先比它，相等就不重读整个文件
- `FileTreeNode { url, name, isDirectory, isErrorPlaceholder, childrenLoaded, children }`：文件树节点。`reconcile(existing:entries:)` 把磁盘最新一级列表对账进已缓存的子项——次序跟随 `entries`，URL 未变的条目复用原节点实例（`NSOutlineView` 按实例记展开态，换实例会把展开的子树折回去），新 URL 建新节点，磁盘上消失的丢弃
- `FileTreeRefresh.Scope { directoriesToReload, touchesActiveFile }`：一次磁盘变化要触发的刷新范围。`scope(changedPaths:mustScanSubDirectories:loadedDirectories:activeFileURL:)` 是纯路径运算，路径比较前统一解析 symlink、剥前导 `/private`、去尾斜杠
- `RenderedPreview { attributedText, note, outline, display, highlightLanguage?, usesJSONHighlighting, followsSystemAppearance, jsonStructureIsValid }`：`PreviewRenderer` 的输出。`highlightLanguage` 非 nil 表示走 shiki 高亮（Dark Modern）；`usesJSONHighlighting` 为 true 表示 JSON / JSONL 走可视区惰性词法高亮；`followsSystemAppearance` 为 true 表示编辑器区通过 `PeekyTheme` 跟随系统明暗；`jsonStructureIsValid` 为 true 表示源文本是结构解析成功的 JSON，控制器据此决定是否建立 `JSONPathMap` 路径索引
- `PeekyPalette`（PeekyCore）：两套语义 palette（浅色 GitHub Light、深色 VS Code Dark Modern），`ThemeColor` 枚举 × hex 常量表，换色只改常量；`hex(_:appearance:)` 取 hex，`rgba(fromHex:)` 解析为 0–255 分量。`PeekyTheme`（PeekyKit）把它转成 NSColor，`resolveAppearance(NSAppearance?)` 将系统外观映射到对应 palette
- `JSONHighlighter.JSONToken { kind, range }`（kind ∈ key / string / number / boolLiteral / nullLiteral / punctuation）：JSON 词法分析器，单遍扫描按 UTF-16 子范围 tokenize，为可视区惰性高亮提供 token
- `HighlightedToken { text, colorHex }` / `HighlightedLine` / `HighlightChunk { firstLine, lines }`：`HighlightService` 的产物
- `JSONLineRecord { originalLine, range, isInvalid, summary }`：JSONL 原文模式下每条记录的元数据
- `JSONPathSegment`（key(String) / index(Int)）+ `JSONPathMap { nodes: [Node], lineNode: [Int32] }`：pretty JSON 文本的逐行节点路径索引。父指针树存储——`Node = { parent: Int32, segment }`，`lineNode` 每行一个节点下标（-1 为根），`path(line:)` 沿 parent 回溯物化。`build` 单遍 UTF-16 扫描；空行是 JSONL 记录边界（清栈隔离坏行），但空行紧跟 `{` / `[` 时属于空容器内部不清栈。`jqExpression` 产出可直接执行且可安全放进 shell 单引号的表达式（非标识符 key 走 `."..."`，单引号输出为 unicode 转义）；`dotPath` 产出 `users.0.user.phone`

## 模块地图（依赖自上而下）
三个库 target，各带一个入口：
- **PeekyCore**：不依赖 AppKit / WebKit 的公共核心，app 与终端版共用——TextFileLoader、FileKind、OpenRequest、JSON 四件套、XMLFormatter、MarkdownRenderer、MarkdownHTMLRenderer、MarkdownLinkPolicy、HighlightService、RepoRoot、DirectoryLister、DirectoryWatcher、FileTreeNode、FileTreeRefresh、FileTreeIndentGuide、RecentFiles、LastModifiedText、PreviewDisplayMetadata、PeekyPalette、PreviewBudget、CoreResources，以及 shiki-bundle.js / github-markdown.css 资源。类型以 `package` 访问级别对包内其它 target 可见。
- **PeekyKit**：app 的 AppKit / WebKit 界面代码，依赖 PeekyCore；入口 `Peeky`。
- **PeekTUI**：终端版，依赖 PeekyCore，零 AppKit；入口 `peek-tui`。目录分层：Screen（字宽、格子、差异编码）、Input（输入解析）、Terminal（终端会话进出）、Document（显示规则、按行存储、折行、Markdown 排版、着色、选区文字）、Sidebar（文件树、侧栏状态与渲染）、App（状态、reducer、唯一有状态的 `TUIRuntime`）、View（画面渲染、帮助浮层、界面色）。

### app（PeekyKit）
```
main → AppDelegate → OpenRequest / PreviewWindowController
                   → RecentFiles / RecentFilesMenu
PreviewWindowController
  → TextFileLoader / PreviewRenderer / MarkdownHTMLRenderer
  → MarkdownLinkPolicy / PreviewDisplayMetadata / HighlightService
  → WKWebView / PreviewGutterView / FileTreeView / DirectoryWatcher
  → Drop*View / FileKind / PeekyTheme / JSONHighlighter
FileTreeView → FileTreeNode / DirectoryLister
PreviewRenderer → JSONFormatter / XMLFormatter / SyntaxHighlighter
                → MarkdownRenderer / FileKind
```
- `PreviewWindowController`：约 1.8k 行，唯一持有状态的 UI 控制器。
- `RecentFiles`：最近文件列表的持有与持久化；`RecentFilesMenu`：Open Recent 子菜单条目；`RecentFilesSectionView`：空白窗口里的最近文件列表（`EmptyStateGroup` 装既有的 Peeky + Open File 与列表，宽 < 480 时每行改两行排）。
- `WKWebView`：Markdown 预览；`PreviewGutterView`：行号栏（`NSRulerView`）；`FileTreeView`：`NSOutlineView` 惰性树；`FileTreeNode`：节点 + reconcile。
- `MarkdownHTMLRenderer`：Markdown → HTML，交给 WebView；`PreviewRenderer`：非 Markdown 的路径选择与编排；`MarkdownRenderer`：大纲抽取 + 超 8 MB 时的兜底。
- 叶子纯函数模块：`RecentFiles`（记录去重截断 / 可用性三态 / 来源识别 / 显示文字）、`JSONFormatter`、`JSONHighlighter`、`JSONPathMap`（逐行节点路径索引 + jq / 点分序列化）、`PeekyPalette`（配色 hex 表）、`PeekyTheme`（PeekyPalette → NSColor）、`PreviewBudget`（三档性能预算常量）、`MarkdownHTMLRenderer`、`MarkdownLinkPolicy`（链接点击导航分流）、`XMLFormatter`、`MarkdownRenderer`、`SyntaxHighlighter`、`RepoRoot`、`DirectoryLister`、`FileTreeRefresh`（磁盘事件 → 刷新范围）、`HoverTracking`（悬停 tracking area 安装，保住系统的 tooltip 区）、`ToolbarIcon`（顶栏六颗图标同网格自绘，墨迹长边逐颗相同）、`LastModifiedText`（顶栏副标题里的「最后更改于」文案）。
- 服务单例：`HighlightService`（JSC + shiki-bundle，私有串行队列，资源缺失或 JS 异常时永久降级为纯文本）。
- 服务实例：`DirectoryWatcher`（FSEvents，每窗口一个，盯当前树根；后台队列收事件、回主线程交回调）。

### 终端版（PeekTUI）
```
peek-tui → PeekTUIMain → TerminalSession / TUIRuntime / PlainOutput
TUIRuntime → TUIReducer / FrameRenderer / ScreenEncoder / InputParser
           → TextFileLoader / DocumentPreparer / MarkdownLayout
           → HighlightService / DirectoryLister / DirectoryWatcher
TUIReducer → DocumentLayout / JSONView / FileTree / SelectionText
FrameRenderer → DocumentLayout / SidebarRenderer / HelpOverlay
```
- `TUIRuntime`：唯一有状态的对象，执行副作用（读文件、列目录、监听磁盘、写剪贴板），调度渲染。
- `TUIReducer`：纯函数，事件 → 新状态 + 副作用；侧栏与复制类动作的分支在 `SidebarReducer.swift` / `ActionReducer.swift` 两个扩展文件里。
- `FrameRenderer`：纯函数，状态 → 一帧 `CellBuffer`；`ScreenEncoder`：前后两帧的差异 → 转义序列。
- `PlainOutput`：标准输出不是终端时输出的纯文字。

## 关键约定
- Markdown 渲染走 `WKWebView` + github-markdown.css；其它文件走 `NSTextView` + `NSAttributedString`。
- JSON / JSONL 唯一渲染形态是缩进格式化文本 + `JSONHighlighter` 可视区惰性词法高亮 + 原生选中复制；交互模式对齐 codebeautify.org/jsonviewer 的 Ace code 视图，plan 见 `.claude/plans/json-viewer-parity.md`；工具栏按钮（compact / sort / transform / undo-redo）跟踪于 issues #21–#24。
- 配色集中在 `PeekyPalette`（hex 常量表，app 经 `PeekyTheme` 转 NSColor），两套语义 palette（浅色 GitHub Light、深色 VS Code Dark Modern），换色只改 hex 常量，跟随系统明暗；已覆盖 JSON / JSONL 渲染区和 gutter，侧栏 / 源码 / Markdown 的主题统一仍在后续。
- Markdown 解析层用 `swiftlang/swift-markdown` `exact 0.8.0`，是本 repo 唯一的第三方 SPM 依赖。
- 高亮引擎是 JavaScriptCore + shiki（`dark_modern` include 链在构建期扁平化）。产物 `Sources/PeekyCore/Resources/shiki-bundle.js` 由 esbuild 打包并 checked-in；运行期不需要 Node，高亮引擎本身不依赖 WebKit（Markdown 预览另外使用 WKWebView）。
- 文件树的任何一次「与磁盘对账」都走 `FileTreeNode.reconcile`，复用 URL 未变的节点实例，展开态与选中行因此天然保住；`FileTreeView.reload(root:)` 只用于换树根。
- 刷新范围由 `FileTreeRefresh.scope` 一处决定，`FileTreeView.loadedDirectoryURLs` 提供「哪些目录已经列过磁盘」这一事实。
- 编辑功能超出范围（见 `.out-of-scope/file-editing.md`）。
- CLI 命令名 `peek`，app 与 repo 名沿用 Peeky；基线是 `main` 分支。
- `peek` 的分派：标准输出是终端且找得到 `peek-tui`（脚本所在 app 包 → 选中的 app 包 → 仓库 `.build/release`）时 exec 终端版；带 `--app` 或标准输出不是终端时走 app（URL scheme）。
