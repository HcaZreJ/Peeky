# Feature: Markdown 里的 Mermaid 图画成图（app 与终端版，issue #51）

**Status**：调研与设计完成（2026-10-22）；W1 进行中（2026-10-23）。分支 `worktree-mermaid-51`（worktree `.claude/worktrees/mermaid-51`）。下一步从 W1 开始。

## 已决定事项（用户原话，摘自 issue #51 正文）
> **决定（用户 2026-10-22）**：Mermaid 流程图要做，走方案 B——app 和终端版一起做。用户已同意为此引入第三方库 mermaid.js；按 AGENTS.md 铁律，动手前仍要在 `.claude/plans/` 里写一份 plan，把版本、体积、许可证、打包与更新方式写清楚。

> **为什么终端版要借 app 来画**：mermaid.js 要靠浏览器的 DOM 排版和量字宽，JavaScriptCore 单独跑不了。终端版（PeekTUI）约定不依赖 AppKit / WebKit，而 app 自带 WebKit。

用户本次指令：「处理 issue 51」。

## 要做什么
- app：Markdown 预览里 ` ```mermaid ` 代码块显示成图，跟随系统明暗切换重画。
- app 可执行文件加不开窗口的渲染模式，把 Mermaid 源码画成 PNG 后退出。
- 终端版：kitty / Ghostty 下 mermaid 代码块显示成图（复用 #60 的本地图片管线），复制得到 Mermaid 源码；图由同一 app 包里的 `Contents/MacOS/Peeky` 在后台画。

## 不做什么
- 跨次运行的 PNG 缓存（每次打开都重画；用户 2026-10-23 选定）。
- 网络加载 mermaid.js、运行期 Node。
- mermaid 的交互功能（点击回调、链接跳转、tooltip）。
- 终端版不支持图片的终端（显示成代码块，与现状相同）。

## 验收判据
1. app 打开含 mermaid 代码块的 md：代码块位置显示成图；浅色 / 深色各一套配色，切换系统明暗后图跟着换。
2. 语法错误的 mermaid 块：仍显示源码，下面一行说明画不出来的原因；页面其它部分不受影响。
3. 不含 mermaid 的 md：HTML 里没有 mermaid.js（打开速度不变）。
4. 含 mermaid 的 md：大纲点击跳转、外部改写后原地重读都停在正确位置（图画完之后再滚动）。
5. `Peeky --render-mermaid …` 在终端里运行：不出 Dock 图标、不开窗口，输出 PNG（透明底，2 倍像素），退出码 0；源码有错时不产出该 PNG、退出码非 0。
6. 终端版（kitty、Ghostty 各一遍，浅色深色各一遍）：mermaid 块先显示成代码，图画好后换成占位符行；占格规则同本地图片（不放大、不超正文宽与 30 行）；拖选复制得到 Mermaid 源码。
7. 终端版找不到同目录的 `Peeky` 时 mermaid 块照旧显示成代码，没有报错输出打到画面上。
8. 全量测试 `./.build/out/Products/Debug/PeekyTests --no-parallel` 零失败；`build-app.sh --install` 后用户安装版可见。

## 技术决定（架构师裁定，含否决方案）
- **版本：mermaid 11.17.2**（2026-08-25 发布，11 系最后一版）。
  - 体积：`dist/mermaid.min.js` 3,572,661 字节（gzip 979,561）。
  - 许可证：mermaid MIT；打进单文件的依赖为 MIT / ISC，DOMPurify 3.4.12 是 Apache-2.0 或 MPL-2.0 二选一（取 Apache-2.0）。文件内已带各自的 license 注释，原样保留。
  - 否决 12.1.0（最新为 12.2.0，才发布 9 天）：12.1.0 的 `mermaid.min.js` 5,493,176 字节（gzip 1,571,744），多出的 ~1.9 MB 主要是打进去的 elkjs（EPL-2.0，弱 copyleft，分发时要附源码获取方式）；12 新增的主题与外观选项对画流程图没有用处。
- **打包方式**：照 shiki-bundle 的做法，产物 checked-in 为 `Sources/PeekyCore/Resources/mermaid.min.js`，在 `Package.swift` 的 PeekyCore `resources` 里加 `.copy`，经 `CoreResources` 寻径。运行期离线、不联网。
- **更新方式**：`scripts/build-mermaid-bundle.sh` 里写死版本号与 npm 的 sha512 integrity（11.17.2：`sha512-V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg==`），脚本用 curl 下 `https://registry.npmjs.org/mermaid/-/mermaid-<版本>.tgz`、校验 integrity、只解出 `package/dist/mermaid.min.js` 覆盖资源文件。升级 = 改脚本里的版本与 integrity 再跑一次，体积与许可证变化写进 commit message 与 TECHSTACK。脚本不需要 Node。
- **app 只在需要时注入脚本**：`MarkdownHTMLRenderer` 的渲染结果带上是否含 mermaid 块；含时 `documentHTML` 才把 mermaid.js 内联进 `<script>`（WKWebView 用 `loadHTMLString(baseURL: nil)`，内联最稳）。
- **终端版的图按自然尺寸画**：渲染模式用 `useMaxWidth: false` 画出图的自然大小，按 2 倍像素输出透明底 PNG；终端版按占格规则缩到格子里。画图结果只和「源码 + 明暗」有关，终端宽度变化不用重画。
- **PNG 的交接走临时目录**：终端版每个进程一个 `$TMPDIR/peek-tui-mermaid-<pid>/`，文件名是「源码 + 明暗 + mermaid 版本」的散列；`q` 退出、SIGTERM / SIGHUP 时删掉这个目录。终端版里 `TerminalImage.Content` 用 `.file(path:)` 指向这个 PNG（路径里就是源码散列，编号随之稳定），光栅化沿用 `ImageRasterizer`。
- **一个文档一个渲染进程**：终端版把这份文档里还没画的 mermaid 块一次交给一个 `Peeky --render-mermaid` 进程，进程内依次画完再退出，省掉逐块起 WebKit 的开销。
- 否决：终端版自己用 JavaScriptCore 跑 mermaid（没有 DOM，不能排版量字）；拿到 SVG 后在终端版里光栅化（mermaid 的标签用 `foreignObject` 里的 HTML，CoreGraphics 画不出来）。

## 设计

### app（PeekyCore + PeekyKit）
- `MarkdownHTMLRenderer.visitCodeBlock`：语言（info string 第一个词，不分大小写）为 `mermaid` 时输出
  `<div class="peeky-mermaid"><pre><code class="language-mermaid">转义后的源码</code></pre></div>`。
- `renderWithOutline` 的结果加一项 `hasMermaid: Bool`（唯一调用方 `PreviewWindowController.renderMarkdownWeb`，测试里只按 `.html` / `.outline` 取值）。
- `documentHTML(bodyHTML:css:mermaidScript:)`：`mermaidScript` 非 nil 时内联脚本加一段启动代码：
  - `mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 深色 ? 'dark' : 'default' })`；
  - 逐个 `.peeky-mermaid` 取 `code.textContent`，`await mermaid.render(id, 源码)`，成功时在 `pre` 前插入 `<div class="peeky-mermaid-diagram">svg</div>` 并给容器加 `peeky-mermaid-rendered`（CSS 藏起 `pre`）；失败时保留 `pre`，追加一行 `<p class="peeky-mermaid-error">` 写错误首行，并删掉 mermaid 留在 body 里的临时节点；
  - `matchMedia('(prefers-color-scheme: dark)')` 变化时按新主题重画全部；
  - 暴露 `window.peekyDiagramsReady`（Promise，全部画完后 resolve；没有 mermaid 时是已 resolve 的 Promise），`scrollToHeading` 与原地重读的 `window.scrollTo` 都在它之后执行。
- `PreviewWindowController`：`githubMarkdownCSS` 旁边加懒加载的 mermaid 脚本（`CoreResources.url(forResource: "mermaid.min", withExtension: "js")`，找不到时为 nil，图降级为代码块）；`didFinish` 里的两处滚动改成等 `peekyDiagramsReady`。

### 渲染模式（PeekyKit，`Peeky --render-mermaid`）
- 命令行：`Peeky --render-mermaid --appearance dark|light <源码文件> <输出.png> [<源码文件> <输出.png> …]`。参数解析写成纯函数（`MermaidRenderJob.parse(arguments) -> Result<MermaidRenderJob, …>`），`PeekyMain.run()` 开头判断，命中就走渲染模式、不建 `AppDelegate`。
- 进程：`NSApplication.shared` + `setActivationPolicy(.prohibited)`（不出 Dock 图标）；一个不上屏的 `NSWindow` 承载 `WKWebView`（`drawsBackground = false`，透明底）；页面只含 mermaid.js 与渲染函数。逐个渲染：JS 返回 SVG 的包围盒 → 设 WebView 尺寸 → `takeSnapshot`（2 倍）→ PNG 写到输出路径。任一块失败不写它的 PNG、继续下一块，最后有失败则退出码 1。总超时 20 秒。
- W2 的第一步是 spike：确认离屏 `takeSnapshot` 在锁屏 / 无屏幕权限下能出像素、底色透明；不行就改用 `createPDF(configuration:)` 加 CoreGraphics 光栅化。
- 同时确认 LaunchServices 是否把这个进程当成正在运行的 Peeky（`lsappinfo list` 里查）。若是，渲染期间用户恰好 `peek --app` 时打开请求可能送到它这里；记录结论，必要时把渲染进程改成不登记为 app 的方式。

### 终端版（PeekTUI）
- `MarkdownImageContext` 加 `diagrams: [String: MermaidDiagram]`（键是源码散列，值是 PNG 路径与像素尺寸）。
- `MarkdownLayout.Builder.codeBlock`：有图片条件、语言是 mermaid 时记进 `MarkdownRendering.mermaidSources`（散列 → 源码，按出现顺序）；`diagrams` 里有它且尺寸非空时排成占位符行（同 `blockImage`：`imageCells` 定格数，第一行 `copyText` 是完整源码、其余行是装饰），否则按代码块排。
- `TUIEvent.mermaidRendered([String: MermaidDiagram], generation:)`、`TUIEffect.renderMermaid(sources:, appearance:, generation:)`；reducer 里 `renderMermaidIfNeeded` 与 `probeImagesIfNeeded` 并列（`OpenedDocument.requestedDiagrams` 防重复请求），结果合并后 `relayoutMarkdownIfNeeded`。明暗变化后散列不同，自然重新请求。
- `TUIRuntime`：找渲染程序 = `peek-tui` 真实路径同目录下的 `Peeky`（app 包里的 `Contents/MacOS/Peeky`；`swift build` 输出目录里两者也同级）；找不到就不发请求。子进程 stdin / stdout / stderr 一律接 `/dev/null`（不碰终端）。画完读 PNG 尺寸（`ImageRasterizer.pixelSize`），失败的记 `PixelSize.unreadable`（按代码显示）。

## 工作单元
| # | 内容 | 测试义务 |
|---|---|---|
| W1 | `scripts/build-mermaid-bundle.sh` + 资源文件 + Package.swift + `CoreResources` 能找到 | 跑脚本两次产物不变（幂等），`swift build --product Peeky` 后资源包里有文件 |
| W2 | spike：离屏渲染出 PNG（见上）；结论写回本节 Status | 跑起来验收，留 PNG 用 Read 看图 |
| W3 | `MarkdownHTMLRenderer` mermaid 块 + `hasMermaid` + `documentHTML` 注入 | test-first ≤ 8 例（`Visible_markdownHTMLRenderer` 扩充） |
| W4 | app 接线：`PreviewWindowController` 注入脚本、滚动等图画完 | 跑起来验收（浅色深色、语法错误、大纲跳转、原地重读） |
| W5 | 渲染模式：参数解析（纯函数）+ 渲染进程 | 参数解析 test-first ≤ 8 例；进程跑起来验收（验收判据 5） |
| W6 | 终端版：排版、reducer、运行时、退出清理 | 排版与 reducer test-first ≤ 8 例；找渲染程序 ≤ 4 例；tui-smoke + 录像解码验收（验收判据 6、7），无屏验证手法见 issue #51 正文 |
| W7 | 文档：TECHSTACK（依赖、资源、体积、许可证、更新命令）、PATTERNS（app 与终端版的 Mermaid 约定）、PROJECT（功能清单）、DEVFLOW（更新命令、验收清单）；完成后删除本 plan、关 #51 | — |

## 用户补充决定
> 就按A，你直接开始做（2026-10-23）

A = 终端版画好的图不跨次保存：每次打开都由渲染进程重画，PNG 只放在本次运行的临时目录里，退出时删掉。
