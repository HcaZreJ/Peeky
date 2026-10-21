# DEVFLOW

## 常用命令
| 命令 | 作用 |
|---|---|
| `swift build --product Peeky` | 增量 debug 构建 |
| `swift build -c release` | release 构建（全量 ~40s） |
| `swift run Peeky <path>` | 从源码直接运行（无 Finder 集成） |
| `swift run Peeky <path>:<line>` | 打开并跳到指定行 |
| `swift build --product peek-tui` | 构建终端版 |
| `./.build/out/Products/Debug/peek-tui <path>[:<line>]` | 在当前终端里打开文件（q 退出）；标准输出不是终端时直接输出文本 |
| `PEEK_TUI_TRACE=1 ./.build/out/Products/Debug/peek-tui <path>` | 把读文件 / 格式化 / 切行 / JSON 索引各阶段耗时写进 `$TMPDIR/peek-tui.log`（测性能用 release 构建：`swift build -c release --product peek-tui`，二进制在 `.build/out/Products/Release/`） |
| `bash scripts/tui-smoke.sh <path> [按键 \| !命令 ...]` | 终端版冒烟：隐藏的 kitty 窗口里运行，逐个发送按键并读回屏幕文字；`!` 开头的参数改为执行 shell 命令（模拟外部新建 / 改写文件）并等 1 秒；鼠标用 SGR 序列模拟（如 `"\x1b[<0;31;2M\x1b[<32;42;2M\x1b[<0;42;2m"` 是在第 2 行从第 31 列拖到第 42 列，坐标 1 起算），⌘C 用 `"\x1b[99;9u"`；最后按 q 并检查终端设置已还原（需已安装 kitty；`COLS` / `ROWS` 设窗口格数；`KITTY_ARGS` 传额外 kitty 选项；`!` 命令里可用 `kitty @ --to "$KITTY_SOCKET" set-colors background=#101010` 改终端背景，模拟明暗切换） |
| `uv run --no-project python scripts/gen-width-table.py <EastAsianWidth.txt>` | 重新生成 `Sources/PeekTUI/Screen/EastAsianWidthTable.swift`（升级 Unicode 版本时运行） |
| `bash scripts/build-app.sh` | 构建 app 与终端版，组装 `.build/Peeky.app`（终端版在 `Contents/MacOS/peek-tui`）+ ad-hoc codesign（正式身份，供 CI 打包）；`--install` 装到 `~/Applications/Peeky Dev.app`，转成 dev 身份（`local.peeky.dev` / `peeky-dev://` / 独立 Preferences），symlink `~/.local/bin/peek` |
| `swift build --product PeekyTests && ./.build/out/Products/Debug/PeekyTests` | 运行全部测试（可加 `--filter <suite>`） |
| `scripts/run-hidden-tests.sh <unit>` | 运行该单元的 hidden 测试，仅输出 `PASSED: X/Y` |
| `node scripts/build-shiki-bundle.mjs` | 重新生成 `Sources/PeekyCore/Resources/shiki-bundle.js`（幂等；改语言或主题后运行） |
| `node scripts/shiki-bundle/smoke.mjs` | bundle 冒烟测试：3 种语言 tokenize + dark_modern 配色 + 分块续接断言 |
| `bash scripts/record-demo.sh` | 生成 README 用的 hero 视频与三张截图；子命令 `--stills` `--video`，屏幕索引 `--screen N` |
| `git tag vX.Y.Z && git push origin vX.Y.Z` | 发布：触发 CI 构建 + GitHub Release + 更新 Homebrew cask（见「发布」） |

> 本机仅 CommandLineTools：`swift test` 会构建但**不会执行**（CLT 缺 xctest 执行器）；请使用上表的 PeekyTests 可执行文件运行测试。
>
> **每条 swift build 都带 `--product`。** Swift 6.2 起 SwiftPM 默认走 swiftbuild 构建系统；一次同时构建
> `Peeky` 与 `PeekyTests` 两个 target 时，它会漏传 Testing 的宏插件，报
> `external macro implementation type 'TestingMacros.SuiteDeclarationMacro' could not be found`。
> 带 `--product` 逐个构建即正常。同一条命令偶发这个错时重跑一次即可通过。
>
> swiftbuild 把产物放在 `.build/out/Products/{Debug,Release}`，并保留 `.build/release/Peeky` 兼容路径供
> `scripts/build-app.sh` 使用。`scripts/run-hidden-tests.sh` 自行在两处候选里挑实际存在的那个二进制。
>
> **参数化测试的 `arguments:` 数组一律带显式类型标注**（`] as [(hex: String, red: Double, …)]`）。
> 缺标注时 Swift 6.4 推导 `@Test` 宏展开里的元组数组会超时，报
> `the compiler is unable to type-check this expression in reasonable time`，整个测试 target 编不过。

## 测试策略（Test-First，双层）
- 叶子纯函数模块：`Tests/visible/` + `Tests/hidden/`（Swift Testing；suite 命名 `Visible_<unit>` / `Hidden_<unit>` 供 `--filter` 精确匹配；同 target 内文件 basename 必须唯一，命名 `<unit>Visible.test.swift` / `<unit>Hidden.test.swift`）。`--filter` 匹配的是 Swift 里的类型名，测试结构体本身也要命名为 `Visible_<unit>`；`--filter` 不支持用 `|` 同时匹配多个套件，要逐个运行。
- 测试是独立 executable `PeekyTests`（`Tests/entry.swift` 经 `Testing.__swiftPMEntryPoint()` 进入），测试文件同时 `@testable import PeekyKit` 与 `@testable import PeekyCore`，走 debug 构建。
- 开真实窗口的界面测试（`Visible_headerMeta`、`Visible_headerLayout` 等）在默认的并行运行下偶发失败；全量验收用 `./.build/out/Products/Debug/PeekyTests --no-parallel`。
- hidden 运行器：`scripts/run-hidden-tests.sh <unit>`，仅输出 `PASSED: X/Y`。
- Stub 阶段用 **degenerate 返回值**（空集合 / nil / 空串），测试以断言失败呈现失败状态（"全部 FAIL 且非编译错误"的信号）。测试内对 stub 可能返回的集合做下标访问必须经过 `try #require` 或安全下标；直接使用 `[0]` 会 trap 中止整个共享 PeekyTests 进程，其余用例都无法运行。

## 分支 / 上游
- 开发在本 fork 的 `main`；上游 `zhangzhejian/Peeky` 不追随，保持 commit 可回贡到上游的干净状态（一个功能一个干净的 commit）。
- 提交粒度是 plan 级，用户批准后 commit；不主动 push。

## 发布

唯一的 workflow 是 `.github/workflows/build-app.yml`，触发条件只有两个：push 一个 `v*` tag，
或在 Actions 页手动 `workflow_dispatch`（可指定任意 branch / tag / SHA 构建）。
**合并到 `main` 不触发任何 CI，也不产出新版本**；仓库没有自动化测试闸门，测试闸门是本地的
`swift build --product PeekyTests && ./.build/out/Products/Debug/PeekyTests`。

发一个版本：

```sh
git checkout main && git pull
git tag v0.4.0        # 版本号去掉 v 前缀后成为 PEEKY_VERSION，写进 Info.plist
git push origin v0.4.0
```

tag 触发的 CI 依次做：`scripts/build-app.sh` 构建 → `ditto` 打包成
`Peeky-v0.4.0.zip` → 上传 artifact → 创建同名 GitHub Release 并附上 zip →
更新 Homebrew tap（clone `HcaZreJ/homebrew-peeky`，把 `Casks/peeky.rb` 的 `version` 与
`sha256` 改成本次产物的值并 push）。tap 更新依赖仓库 secret `TAP_PUSH_TOKEN`
（对 `HcaZreJ/homebrew-peeky` 有 contents:write 的 fine-grained PAT）；secret 缺失时
这一步跳过、release 仍然产出。

手动 `workflow_dispatch` 只构建并上传 artifact，不创建 Release、不更新 tap
（版本号非 `vX.Y.Z` 形态时 `is_release` 为 false）。

用户侧升级到新版本：

```sh
brew upgrade --cask peeky
```

升级后首次打开需要重新过一次 Gatekeeper 放行（ad-hoc 签名，非 Apple 公证），
步骤见 README 的安装章节。

## 手动验收清单
- **任何 UI 或渲染改动必须在浅色与深色两种外观下各测试一次**（通过系统外观切换或 `defaults write -g AppleInterfaceStyle`）；颜色相关改动还需在两种外观下验证 resolve 后的亮度断言（背景与前景对比方向正确）。
- `swift run Peeky <md>` 打开后能直接显示 Markdown，侧栏 Contents tab 里的大纲支持点击跳转；Open / Files / Contents 三个 tab 点击切换，并记住上次选择；非 Markdown 文件的 Contents 置灰，自动回退到 Files。
- 多标题的 Markdown（≥40 个标题）打开后窗口高度不超出屏幕，可以自由 resize；Contents tab 的大纲占满侧栏高度，超出时自行滚动。
- 一个窗口里打开多个文件后连按 ⌘W：每次关掉当前文件并切到相邻文件，文件全部关完后窗口停在空状态，再按一次才关窗；⇧⌘W 任何时候直接关窗。
- `<json>` / `<jsonl>` 打开后应显示缩进格式化 + 词法高亮（key / 字符串 / 数字 / bool / null / 标点；浅色 GitHub Light、深色 VS Code Dark Modern，跟随系统明暗）；鼠标选中 ⌘C 可复制；行号 gutter 显示；JSONL 解析失败的行以红底红字标出，gutter 显示 "!"；滚动时可视区即时高亮，大文件不阻塞。
- `<json>` / `<jsonl>` 的节点路径：光标落在任意行，底部状态栏在 Ln/Col 之后显示该行的 jq 路径；选中该行出现两个浮动 chip（"jq path" 在左、"path:line" 在右，窗口右缘也不重叠），点 "jq path" 复制的表达式能直接 `jq '<粘贴>' <file>` 跑出该行的值，⌥ 点击复制 `users.0.user.phone` 点分形态；折叠某容器后光标落在折叠行显示该容器自身的路径；切到非 JSON 文件后状态栏无路径段、jq chip 不出现；语法错误的 JSON 不显示任何路径。
- 文件树与磁盘同步：`peek <目录>` 打开后，在该目录里新建一个文件，**不做任何操作**，侧栏 Files 树在一秒内多出这一条；
  在没展开过的子目录里新建文件时树不动，展开该子目录时新文件在列；把某个已展开目录折叠再展开，等同一次刷新。
  展开五层目录后按 ⌘R，树保持原来的展开层级与选中行。
  当前正在预览的文件被外部改写时，正文就地更新且停在原来的滚动位置（markdown 与非 markdown 两条路径都要看）；
  切到另一个 tab 再切回来，期间被改写的内容在切回的那一刻落地。无树根（空窗口）时 View 菜单的 Refresh from Disk 置灰。
- 顶栏按钮逐个 hover：出浅底并浮出 tooltip，浅色深色下浅底都看得见；打开非 repo 内的文件时「复制相对路径」明显变暗。tab 卡片上的 × 与 Close All 同样有浅底。
- 顶栏 6 个按钮成组停在窗口右端，拖宽窗口时保持成组、不被拉开；标题过长时中段省略，按钮组位置不动。六颗的图标与 Content / Name / Full path / Rel path / Finder / More 六行文字在浅色深色下都读得清。
- 打开任意文件，顶栏文件名下面一行以「最后更改于：yyyy 年 MM 月 dd 日 HH:mm:ss」开头，与 Finder 的「修改日期」一致（精确到秒）；在外部改写这个文件，这一段随正文一起刷新；把窗口拖窄，这一行从尾部省略，时间一段最后才被截，按钮组不被挤出窗口。
- markdown 文件下打开 ⋯ 菜单，Wrap Lines 置灰；切到源码 / JSON 文件后它恢复可用且勾选态正确。
- `<py / ts / yaml …>` 打开后应显示 Dark Modern 主题高亮，深色背景统一；选中 ⌘C 可复制。
- `.app` bundle 打包后，执行 `open "peeky://open?path=...&line=N"` 应打开正式版 Peeky 并定位到指定行；`open "peeky-dev://open?path=...&line=N"` 应打开本地 dev 版。
- 大文件的行为：非 JSON / JSONL 且大于 8 MB 时降级为 raw，不阻塞界面；JSON / JSONL 仍然进行缩进格式化 + 可视区惰性高亮，即使大文件也不阻塞。
- 终端版（Ghostty 与 kitty 各走一遍，`bash scripts/build-app.sh --install` 之后用 `peek`，或直接跑 `.build/release/peek-tui`）：
  ⌘D 分栏里 `peek <md>` 在该栏全屏打开，`q` 退出后终端恢复原样（光标、回显、能正常输入命令）；`peek --app <md>` 打开 app 窗口。
  Markdown 的表格竖线逐行对齐、中英混排不错位；kitty 里 H1 / H2 是放大的文字，拖选能复制标题原文，Ghostty 里是粗体加颜色。
  JSON 回车折叠、`M` / `R` 全部折叠展开，状态栏 jq 路径随光标变；拖选后 `y`，`pbpaste` 内容与选中一致。
  侧栏在仓库里新建文件 1 秒内出现；外部改写当前文件后正文更新、停在原来的行。
  切换系统明暗（两个终端都配了深浅两套主题时），终端版配色随之变化；源码视图保持深色底。
