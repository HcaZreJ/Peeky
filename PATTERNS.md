# PATTERNS

## Functional-core / 静态命名空间约定
- 格式化、解析、渲染决策一律做成**无状态 `enum` 命名空间 + 静态纯函数**（`JSONFormatter`、`MarkdownRenderer`、`XMLFormatter`、`SyntaxHighlighter`、`PreviewRenderer`），输入到输出确定，方便按 visible / hidden 双层测试。
- 有状态代码集中在两处：`AppDelegate`（窗口数组、生命周期、最近文件列表）与 `PreviewWindowController`（tab 状态 + AppKit 接线）。新增交互 UI 挂在 `PreviewWindowController` 下；新增格式转换器写成叶子纯函数模块。
- `PreviewRenderer` 是"决策层"：选 Raw / Formatted 路径、执行性能预算降级、委派给叶子模块；不处理视图几何。

## 视图约定
- 文本类内容渲染进单一 `NSTextView`（`DropTextView`）的 `NSAttributedString`。JSON / JSONL 走同一 textView：`PreviewRenderer` 输出缩进格式化文本（`SyntaxHighlighter.monospace` 提供等宽基础），`PreviewWindowController.applyVisibleJSONHighlighting` 用 `JSONHighlighter` 对**可视区行对齐的子串**（`lineRange(for:)` 扩展）tokenize，通过 `layoutManager.setTemporaryAttributes` 只给屏幕可见行加语义色；滚动、布局泵、外观变化时重算，只处理可见区，从不 tokenize 全文，这样大文件 JSONL 也不阻塞。
- gutter 是 `PreviewGutterView`（`NSRulerView` 子类，scrollView 的 `verticalRulerView`）：`drawHashMarksAndLabels` 完全接管绘制，只枚举可见 glyph 范围，**每个逻辑行只在首个视觉行片段绘制行号**，软换行的续行不会重复编号（通过 line-start 偏移命中判断）。滚动同步用 `convert(NSZeroPoint, from: textView)` 做坐标平移，`bounds` / `frame` / `didChange` 三种通知触发重绘。overlay（记录分隔线 / 注解）同样按可见范围增量绘制，虚拟化由 `NSLayoutManager` 承担。
- 行号查找用预计算 line-start 偏移 + 二分。
- **异步分块高亮的代际防护**：流式高亮（`highlightStream`）的消费 Task 必须校验 `highlightGeneration` 与 `activeTabID` 两个条件，`renderActiveTab()` 开头统一调用 `invalidateHighlighting()`，取消在途 Task 并递增 generation，防止旧文档的迟到 chunk 覆盖新内容。高亮只调用 `addAttribute`，不重设整个 attributedString。
- **按钮外观统一走 `HoverButton`**：全 app 的按钮无壳、悬停出浅底（`labelColor` 0.14）、字形由 `secondaryLabelColor` 提到 `labelColor`、禁用落到 `tertiaryLabelColor`。三条约束不能省：① 悬停底的不透明度随控件面积取值——侧栏整行（240pt 宽）用 0.06 读得出来，20–30pt 见方的按钮要 0.14；② 语义色取 `.cgColor` 是按取值当时的绘制外观解析的一次性快照，一律包在 `effectiveAppearance.performAsCurrentDrawingAppearance { }` 里，并在 `viewDidChangeEffectiveAppearance()` 重跑；③ 悬停底画在 `bounds` 上，`alignmentRectInsets` 归零，否则一排等高按钮的 frame 互相错开两三个点、浅底参差。 ④ 重建悬停 tracking area 时只摘掉自己上一次装的那一块，走 `HoverTracking.reinstall(on:previous:)`——`NSView.toolTip` 的浮出由 `NSToolTipManager` 挂在同一个 `trackingAreas` 数组里的一块 area 承载，清空整个数组会把它一并删掉，而 `toolTip` 属性值仍在，只读代码看不出 tooltip 已经不浮出了。 顶栏动作按钮另外挂一行文字：`caption` 非空时按 `imageAbove` 排版，文字 9pt regular（比 metaLabel 的 11pt 低一档）、按钮高 36、宽取文字宽加左右各 6pt 内边距且下限 34；文字色与 `contentTintColor` 同一个值，图标与文字同进同退。 图标一律取自 `ToolbarIcon`（六颗同网格自绘，见下条），交给按钮时画布统一为 24×17——`.imageAbove` 是把「图标 + 文字」整块垂直居中的，画布不统一时文字基线会跟着图标高度参差。
- **顶栏图标自绘、六颗同尺寸**（`ToolbarIcon`）：每颗写成一组笔画（`Stroke`：描边 / 填充 / 折线 / 圆角多边形），几何画在 24 见方的网格里，渲染时按墨迹并集的长边缩到 `inkSide` 15pt 再摆进画布正中——**长边一致就是尺寸契约**，六颗因此占同一个槽位。宽高比不入契约：六颗照各自的现成约定画（形状逐条照 Lucide 的 `align-left` / `tag` / `folder` / `list-tree` 转写），硬把它们撑成同一个宽高比，只能靠在小尺寸里堆笔画换。现成符号库做不到这件事：SF Symbol 是按「坐在文字基线上」设计的，墨高与宽高比各不相同，归一到等高之后墨宽从 11.5 摊到 23.0。
- **小尺寸图标的清晰度由笔间距决定，不由线粗决定**：墨迹 15pt 在 Retina 上只有 30px，这个尺寸下两笔之间还剩多少缝才是能否读出形状的判据。闸门是**任意两块墨迹之间 ≥ 4.0 px@2x**——低于这个数两笔会真的连成一块（曾经的三级链式 Rel path 实测缝为 0，省略号与折线连成一体）。`lineWidth` 2.35pt 是在这个闸门下能取到的粗档：纯加粗到 2.25pt 时行李牌的孔先破（它是全套唯一三面受夹的结构），所以 2.35pt 这一档同时重排了笔间距（孔内移收小、勾的落差加大、文件夹缺口加深）。`lineWidth` 是**最终 pt 值**，网格坐标被缩放过，描边要先除以缩放系数才设进 `NSBezierPath.lineWidth`，而缩放系数又依赖含半个描边的墨迹范围——`fit` 迭代四次收敛。新增或替换顶栏图标时跑 `Visible_headerLayout` 的长边断言，并在 @2x 真实像素上量一次连通块数与最近两块距离（当前六颗 5.0–6.0px，墨水面积最重/最轻 3.33×）。
- **顶栏控件组不吸收富余宽度**：标题钉左、控件组钉右，中间一条 `>= 12` 的空隙吃掉全部富余宽度。控件组之间的间距编码分组关系（组内 8 / 两小组 12 / 两大组 20），把它们放进一个两端都钉死的 `NSStackView` 会让富余宽度按 hugging 优先级分摊到这些间距上，6 个按钮被拆成两摊。标题是唯一可压缩的一侧。 标题区里的文字抗压缩一旦高于窗口「保持当前尺寸」的 500，就宁可把窗口撑宽也不省略自己：文件名（`titleLabel`）与副标题（`metaLabel`）因此都设为 `defaultLow`，并且设在 label 本身（设在外层 `NSStackView` 上管不到它里面的 label）。文件名超长时中段省略；副标题以最后更改时间开头、尾部省略，挤的时候先吃掉后面的类型 / 大小 / 编码。
- **磁盘对账约定**：界面缓存与磁盘之间的一致性走三层——纯函数决定范围（`FileTreeRefresh.scope`：FSEvents 送来的变化路径 × 已展开目录 × 最前 tab 的文件）、纯函数决定合并（`FileTreeNode.reconcile`：按 URL 复用节点实例，保住 `NSOutlineView` 的展开态与选中行）、视图只负责执行与还原（`FileTreeView.refresh(directories:)` / `refreshAll()`）。刷新范围恒等于「此刻看得见的东西」：没展开过的目录与后台 tab 的文件不进范围，各自在展开时与切过去时才对账。重读整份文件之前先比 `FileStamp { size, mtime }`，指纹相同就不读。指纹与 `TextFileLoader` 取的文件大小都用 `FileManager.attributesOfItem` 直接读：`URL.resourceValues` 把值缓存在 URL 实例上，runloop 转过一轮才清，紧跟在改写之后的对账会读到旧值。
- **FSEvents 服务约定**（`DirectoryWatcher`）：每窗口一个实例盯当前树根，`kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer` + 0.4s latency 让单次保存立刻送达、批量写入合并成个位数次回调；C 回调在私有后台队列上只做取路径与取 flag，回主线程再交给控制器；换树根时先停旧 stream，`windowWillClose` 撤监听。
- **JSC 服务约定**（以 `HighlightService` 为参照实现）：JSContext 单例 + 私有串行队列承载所有 JS 执行；预算与合法性检查在 Swift 侧前置，不进入 JS；任何 bundle 缺失或 JS 异常一律永久降级返回 nil，加一条一次性日志，运行不中断；资源寻径统一走 PeekyCore 的 `CoreResources`（多个候选：`.app` 的 `Contents/Resources`、`swift build` 输出目录、可执行文件真实路径所在目录及其 `../Resources`），寻径失败同样降级。
- **自绘视图必须设置 `clipsToBounds = true`**：macOS 14 起 NSView 默认不裁剪，`draw(_:)` 收到的 dirtyRect 可能远大于 bounds（窗口首帧为整窗），`fill(dirtyRect)` 会把背景涂到兄弟视图上（表现为兄弟视图"空白"，且 resize 之后也不恢复）。
- **随内容伸缩的视图，凡经约束链连到窗口尺寸的优先级一律低于 500**：NSWindow 有一条「保持当前尺寸」的隐式约束，优先级 500，任何高于它的约束（理想宽 / 理想高的等式、标签的抗压缩）都会把窗口撑大，而不是让内容收窄、截断或滚动。链条常常隐蔽：滚动区里行内标签的抗压缩 → 行宽 → documentView 宽 = clipView 宽 → scrollView → 外层容器 → 窗口。空白窗口的最近文件列表（`RecentFilesSectionView`）因此把理想宽、理想高与行内抗压缩全部定在 480–499；验收时让 app 自己跑完一轮布局再读 `window.frame`，调试器 `setContentSize` 之后立刻读到的是被强行压窄的假状态。
- **textView 的换行和不换行两个分支都必须显式设置 `maxSize = greatestFiniteMagnitude`**：NSTextView 的 frame 增长通过 `setConstrainedFrameSize` 驱动，被钳制在 maxSize 内，而默认 maxSize 等于初始 frame（视口大小）；若未显式放开，长文档的 frame 无法超过视口高度，scrollView 就没有可滚动区域（`applyLineWrapping` 两个分支都已设置）。
- **文档布局由渲染管线主动驱动**：macOS 26 上 TextKit1 的惰性布局不会自行推进；`PreviewWindowController.startLayoutPump()` 在内容或换行模式变化后，在主线程分片调用 `ensureLayout`（每次处理 64k 字符，用 `main.async` 让出 runloop），frame 逐步增高，交互不阻塞。gutter 与 overlay 绘制不触发额外布局（使用 `withoutAdditionalLayout` 变体），只读已就绪数据；程序化跳转（`scrollToLine` 等）在 `scrollRangeToVisible` 之前先对目标 range 调用 `ensureLayout`。
- **配色集中在 `PeekyPalette`**（PeekyCore，app 经 PeekyKit 的 `PeekyTheme` 转成 NSColor）：浅色与深色两套语义 palette 由两张 `[ThemeColor: hex]` 常量表定义，渲染代码按语义 token（`jsonString` / `jsonKey` / `editorBackground` 等）取色，不写死具体颜色；换配色时只改常量。编辑器主题分三条路径（`applyEditorTheme`）：`followsSystemAppearance`（JSON / JSONL）设 appearance 为 nil 跟随系统，背景 / 全文基础前景 / gutter / 坏行经 `resolveAppearance(effectiveAppearance)` 取色，系统明暗切换通过 `DropTextView.onEffectiveAppearanceChanged` 回调重刷可视区；`usesDarkModernTheme`（源码 shiki）锁定为 darkAqua；其它情况使用 `.textBackgroundColor`。

## 终端版（PeekTUI）约定
- **functional core**：状态只在 `TUIRuntime`（对应 app 的 `PreviewWindowController`）。`TUIReducer.reduce(&state, event) -> [TUIEffect]` 是纯函数，`FrameRenderer.render(state) -> CellBuffer` 是纯函数，`ScreenEncoder.encode(previous:next:)` 把前后两帧的差异编成转义序列；副作用（退出、挂起、读文件）由运行时执行。
- **终端进出顺序固定**：进入 = raw 模式 → alternate screen → 隐藏光标 → 鼠标（1000/1002/1006）→ 括号粘贴 2004 → 焦点 1004 → 明暗通知 2031 → kitty 键盘协议 `CSI > 1 u`；退出是逆序（`TerminalSession.exitSequence`），正常退出、SIGTERM / SIGHUP、`atexit` 都走同一个 `TerminalRestore.restoreIfNeeded()`。Ctrl-Z 先还原再 `raise(SIGTSTP)`，回来后重新进入并整屏重画。
- **主循环用 RunLoop，不用 `dispatchMain()`**：`dispatchMain()` 会让主线程退出，主队列改由其他线程执行，Swift 6 的 MainActor 隔离检查随即中止进程（"Incorrect actor executor assumption"）。`PeekTUIMain.runMainLoop()` 在主 RunLoop 上挂一个不触发的定时器再 `RunLoop.main.run()`。
- **后台工作放 `Task.detached` + `nonisolated static` 函数**：在 `@MainActor` 类型里写给 `DispatchQueue.global().async` 的闭包会被推断成 MainActor 隔离，放到后台线程执行就中止进程。
- **字宽**：`TextWidth` 以字形簇为单位：含 U+FE0F 或首码位默认 emoji 呈现 → 2；东亚宽度 W/F（`EastAsianWidthTable`，由脚本从 Unicode 数据生成）→ 2；控制、格式、组合附加符 → 0；其余（含 Ambiguous）→ 1。`CellBuffer` 里宽字符占两格，第二格为续格；覆盖半个宽字符时另一半改空格。
- **每帧输出**包在同步输出 `CSI ? 2026 h … l` 里；颜色一律 24 位真彩，正文用终端默认前景 / 背景，保留用户的半透明背景。
- **界面运行期间 stderr 重定向到 `$TMPDIR/peek-tui.log`**（`TerminalRestore.redirectStandardError`，退出时还原）：库函数往 stderr 写的任何一行（例如 JavaScriptCore 的 inspection 提示）都会打在画面上、把整屏顶上去一行，之后的差异帧全部错位。
- **显示规则与 app 一致**：`DocumentPreparer.prepare(LoadedText)` 复刻 `PreviewRenderer.render` 的分支与 note 文案（Formatted / Invalid JSON / Invalid XML / Invalid plist / Raw / Raw preview for large file）。
- **大文本按行存但不按行建字符串**：`LineStore` 只存全文与每行起点的 UTF-8 偏移，取行时切片；结尾换行不多出空行，`\r\n` 去 `\r`。
- **视口按「逻辑行 + 折行序号」定位**（`ScrollPosition`），每行占几个可视行由 `DocumentLayout.rows` 在视口附近按需计算，不预先算全文可视行总数；大文件（超富格式化上限）默认不换行。
- **高亮异步**：reducer 读入源码文档时发出 `.startHighlight` 副作用，运行时用 `HighlightService.highlightStream` 流式取块，`.highlighted(chunk, generation:)` 回到 reducer；代际不符的块丢弃。
- **Markdown 先排成屏幕行**：`MarkdownLayout.render(source, width:theme:codeTokens:)` 按终端宽度把文档排成 `MarkdownRow`（含左右 2 列边距、底色铺法、来源行号、标题锚点、行内链接地址），视口里每个排版行占 1 个可视行。读入时在后台按当前宽度排好；宽度变化时 reducer 发 `.layoutMarkdown`，结果 `.markdownLaidOut` 回来后光标按来源行号对回原处。代码块高亮走 `.highlightMarkdownCode` → `.markdownCodeHighlighted` → 再排一次。容器块（列表项、引用）先在更窄的宽度下排子块再加前缀；列表项内部子块之间不空行。
- **折行规则（`WrapEngine`）**：西文按词（西文标点属于所在的词），宽字符（CJK、全角标点）各自是可断单位，收尾标点不落行首（放不下时连同行尾连着的收尾标点和它们前面的一个字或词一起换行，「）。」不会拆开），超长词硬断。Markdown 代码块的长行另用 `LineLayout.wrapCode`：断在空格、`/`、`,`、`;` 或宽字符之后（下一个字符是收尾标点时不断），找不到断点才硬断；断处的空格留在上一行，续行补上原行缩进再画暗色 `↪`（装饰，不复制），复制仍是原文。表格列宽 `TableLayout.columnWidths`：放不下时每次把最宽的列减 1，每列不低于 `min(6, 自然宽度)`。
- **JSON / JSONL 视图**：`JSONView` 持有 app 的 `JSONFoldMap` / `JSONPathMap` 与折叠状态，折叠后的显示文本由 `JSONFoldComposer` 合成（折起来的内容显示为 `⟷`），行号栏显示源行号（格式化后文本的行号）并在右侧 2 列画 `▾` / `▸`；`JSONLineColoring` 只给视口内的行着色并在缩进处画导轨 `│`。折叠 / 展开时光标与视口顶端按源行号对回原处。
- **大文件分阶段送达**：需要格式化的类型超过 `TUIRuntime.progressiveThreshold`（1 MB）时，先送原文（`OpenedDocument.formattingPending`），再送格式化后的文档，JSON 最后送 `.jsonIndexed`；小文件一次送达，免得状态栏提示闪一下。后台进度由 `OpenedDocument.progressNote` 派生、显示在状态栏左侧；`文件:行号` 的跳转等格式化后的文档到达才执行。各阶段耗时用 `PhaseTrace` 记录（`PEEK_TUI_TRACE=1`）。
- **侧栏文件树是值类型**：`FileTree` 按路径记每个列过的目录与展开集合，可见行由 `rows()` 推出；目录重新列举后展开状态按路径保留，消失的子目录连同其下状态一起丢掉。app 的 `FileTreeNode` 是引用类型、靠实例身份记展开态，终端版的状态要能比较、能放进 reducer，所以不复用它；刷新范围复用 `FileTreeRefresh.scope`，导轨点亮规则同 app（选中目录点亮自己，选中文件点亮父目录）。
- **正文区随侧栏右移变窄**：正文从 `TUIState.contentOrigin` 列起、宽 `contentColumns`；`DocumentLayout` 与 Markdown 排版一律用正文宽度。`FrameRenderer` 先把正文画进一块正文宽的缓冲区再 `paste` 到侧栏右侧。终端尺寸变化与侧栏显隐都走 `TUIReducer.contentWidthChanged`（光标留在视口里，Markdown 按新宽度重排）。
- **按键先过全局键再按焦点分发**：q / Ctrl-C / Ctrl-Z / Tab / s / 1 / 2 / 3 / [ / ] / x / r 不论焦点都生效，其余键交给 `focus` 所在的正文或侧栏；鼠标按落点分区，按下时焦点跟到那一块，滚轮不改焦点。
- **重读按源行锚定**：目录监听报告当前文件所在目录变了 → 运行时读文件戳 → reducer 与读入时的比较，不同才重读；重读前记 `ReloadAnchor`（视口顶端与光标的源行），新内容到达后对回，文件变短钳到末行；重读跳过「先显示原文」阶段。文件戳用 `FileManager.attributesOfItem` 读：`URL.resourceValues` 会把值缓存在 URL 实例上，后台任务里没有 RunLoop 轮转清缓存，同一个 URL 反复取一直是旧值。
- **多个打开的文件（`TabsReducer`）**：`TUIState.tabs` 是打开的文件（`OpenTab`：文档、视口、换行开关、读入代际、重读锚点），`activeTabIndex` 指当前文件；`document` / `viewport` / `wrapsLines` / `generation` 等是读写当前文件的计算属性。代际全局递增（`lastGeneration`），各文件互不相同；只有当前文件接收后台结果，切走的文件迟到的结果因代际不符被丢掉，切回来时 `refreshActiveTab` 补做（没读完的重读，源码高亮、Markdown 代码块高亮与重排重新发起）并查一次文件戳。打开已开着的文件只切换；关掉当前文件切到右边的（没有就左边的），全关掉后正文显示 `emptyDocument`。文件树跟随当前文件：在树根下时展开定位，不在时发 `.discoverTreeRoot` 换树根（与 app 的 `establishTreeRoot` 一致）。
- **最近打开与 app 共用**：记录在 UserDefaults 的 `PeekyRecentFiles`，读写走 PeekyCore 的 `RecentFiles.load / save / record`；终端版打包在 app 里时 `UserDefaults.standard` 就是 app 的偏好域。两边都不在内存里常驻列表，记一笔前先读存着的最新值，互不覆盖。文件第一次读进来（不是重读）时记。侧栏 Open 页在打开的文件之后列出此刻没打开的最近文件。
- **大纲从排版结果派生**：`MarkdownLayout` 排版时给 1–4 级标题的第一行记级别与纯文本标题（`MarkdownRenderer.plainDisplayText`，空标题显示 "Untitled heading"），`MarkdownRendering.outline` 的行号就是排版行号，跳转与画面严格对应。
- **选区按视觉列记录**：`TextSelection` 的点是「显示行 + 视觉列」（展开制表符、不折行时的列，Markdown 为排版行里含装饰的列），滚动、换行开关都不影响它；换文档、折叠变化、Markdown 重排时清掉。复制由 `SelectionText.text` 换回原文：不同行之间换行，软换行直接拼接，制表符原样；JSON 折叠态换成源区间（`JSONView.expandedText`）。
- **装饰用 `StyledSpan.copyText` 标出**：nil 复制原文，空串（`StyledSpan.decoration`）不复制，其它值替换（表格单元格之间的竖线复制成制表符）；只有装饰的行（分隔线、表格边框行）整行不复制。Markdown 软换行续行记 `MarkdownRow.joinsPrevious`（折行处去掉了空格时是 " "），复制时接回上一行。
- **按键处理顺序**：帮助浮层（任意键关闭）→ `:行号` 输入 → `/` 搜索输入 → 全局键 → 复制与文件动作键（y / ⌘C / Y / F / p / P / L / o / e）→ 搜索跳转 n / N → 按焦点分给正文或侧栏。字符键先去掉 shift（终端对大写字母与符号的上报有的带 shift）。
- **搜索（`SearchEngine` / `SearchReducer`）**：按 UTF-8 字节比较，只折叠英文字母大小写（不建小写副本，偏移不变）。匹配记成「行 + 视觉列区间」（`SearchMatch`）：文本、源码、XML、JSON 的行是源行（格式化后文本的行），Markdown 是排版行——搜的是排好版的文字，装饰不算，一段和它的软换行续行接成一串再搜，跨行的匹配拆成每行一段（第二段起 `isContinuation`，n / N 跳过）。运行时按 `SearchEngine.chunks`（5 万行一批，Markdown 批尾延到段尾）在后台搜，每批结果以 `.searchResults` 送回，发起新搜索时取消旧任务；最多记 `SearchEngine.maximumMatches`（10 万）段。回车后结果到达时跳到第一个不早于光标行的匹配；JSON 的匹配在折叠里时先 `JSONView.reveal` 展开。换文档、重读、Markdown 重排后用同一个词重搜（`rerunSearch`）。
- **连击与提示计时在运行时**：终端不报告双击，`TUIRuntime` 按两次左键按下的间隔（400 ms）与位置算出 `MouseEvent.clickCount`；提示由 `TUIReducer.showToast` 设置并返回 `.expireToast(token)`，2 秒后令牌仍是最新的才清掉。
- **明暗以终端实际背景为准**：启动时发 DSR 996 与 OSC 11，OSC 11 回了背景色就按亮度判断（`TUIReducer.appearance(ofBackground:)`），只有 996 时按 996；之后的 996 / 2031 只触发再问一次背景色（`.queryBackground`）。终端的 996 可能跟着系统明暗而不是它自己的配色。明暗存在 `TUIState.appearance`，所有取色都带它；调色板之外的界面色在 `ChromeColors`。源码视图固定 Dark Modern；Markdown 排版结果记着排版时的明暗，与当前不同就重排（`relayoutMarkdownIfNeeded`），浅色下代码块不上 shiki 色。读文件与重排 Markdown 的副作用都带明暗参数。
- **放大标题（kitty OSC 66）**：启动时在左上角打一个 2 倍空格再问光标位置（`TUIRuntime.textSizingProbe`），光标到第 3 列即 `supportsTextSizing`。放大排版时顶层 H1 / H2 每个折行占上下两个排版行（`MarkdownRow.scaledHeading` 的 part 0 / 1），上半行的片段是不放大时的样子；渲染时两半都在视口里才写放大块（`CellBuffer.writeScaled`：左上格带整段文字，其余是 `isCovered` 格子），否则退回普通样式。`ScreenEncoder` 把前后帧里含放大块的行作为一组：组内有变化就先全部 `ESC[2K` 再整行重画——在放大格上写普通字会让 kitty 擦掉整个大字。排版结果记着是否放大，与终端能力不同就重排。
- **图片（kitty 图片协议的 Unicode 占位符）**：启动时问格子像素尺寸（`CSI 16 t`）、终端名（XTVERSION）与图片协议（`a=q`），三样都有回复且终端是 kitty / Ghostty 才显示图片（`TUIState.supportsImages`）。图以占位符画进格子：每格是 U+10EEEE 加行号、列号附加符，前景色是图片编号（`ImagePlaceholder`），所以滚动、差异输出、选区都当普通文字处理；图片编号由内容、格数、格子尺寸散列而来（`TerminalImage.id`），排版保持纯函数。Markdown 排版带 `MarkdownImageContext`：单独成段的本地图片在读到像素尺寸后排成占位符行（不放大，不超过正文宽与 30 行，按格子像素比例保持长宽比），复制得到「[图片] 说明」；尺寸由运行时在后台读（`.probeImages` → `.imagesProbed` → 重排），还没读到或读不了（SVG、网络地址）的按文字显示。终端能显示图片、但不支持放大文字（Ghostty）时，顶层 H1 / H2 画成图（`MarkdownImageContext.headingImages`）：与放大标题一样按一半宽度折行，每个折行是一张宽为文字两倍、高两行的图，用 CoreText 以系统字体粗体画在透明底上（H1 用 `MarkdownTheme.headingText`，H2 用强调色）；复制时上一行给出标题文字，下一行是装饰。支持放大文字（kitty）时仍用 OSC 66。渲染时 `CellBuffer.images` 列出视口里的图，运行时把没传过的在后台缩到格子大小、编成 PNG，静默分块传给终端（`a=T,U=1,q=2`）；退出与挂起时删掉。只用 ImageIO / CoreGraphics / CoreText。
- **半透明配色**：PeekyPalette 里带透明度的颜色（如 JSONL 坏行底色）由 `TerminalPalette` 叠在编辑器底色上算成不透明色再输出，终端没有透明度。
- **链接**：`StyledSpan.target` 记原始地址（含 `#锚点` 与相对路径），带 scheme 的地址同时写进 `CellStyle.link` 输出 OSC 8；回车打开光标行第一个链接，锚点按 GitHub slug 规则跳转（先解百分号编码），其余交 `/usr/bin/open`，相对路径相对文档目录。

## 性能预算（既有常量，新代码不得绕过）
三档常量集中在 PeekyCore 的 `PreviewBudget`，`TextFileLoader` / `PreviewRenderer` / `SyntaxHighlighter` / `HighlightService` 都读这里。
- `PreviewBudget.maxPreviewBytes = 80MB`（超出截断读取并标注）
- `PreviewBudget.richFormatLimit = 8MB`（超出后自动降级为 raw；**JSON / JSONL 例外**：即使超 8MB 仍然缩进格式化，靠可视区惰性高亮 + 布局泵支持，只受 `TextFileLoader` 80MB 上限约束）
- `PreviewBudget.highlightLimit = 1.5M UTF-16`（超出跳过高亮）
- 重计算放在后台线程，UI 回到主线程执行（上游存在同步渲染的技术债，新增代码不沿用这一做法）。

## 命名
- 类型用 PascalCase；函数以动词开头，camelCase；文件名等于主类型名。
- 打开请求统一经过 `OpenRequest` 归一化（CLI / Finder / scheme 三源），新入口不得绕过。

## 测试约定
- 叶子纯函数模块采用双层 test-first（visible / hidden，Swift Testing testTarget，运行器详见 DEVFLOW）。
- AppKit 视图 / 控制器层按架构师判断，通过构建 + 手动冒烟清单验收。
- 开真实窗口的界面测试全程同步：测试体里不转 RunLoop、不按时长等待，断言的状态由被测代码同步给出。PeekyTests 默认并行运行，转主线程 runloop 会把别的测试插进来执行，等多久、等到什么都不可控。
