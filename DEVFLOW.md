# DEVFLOW

## 常用命令
| 命令 | 作用 |
|---|---|
| `swift build` | 增量 debug 构建 |
| `swift build -c release` | release 构建（全量 ~40s） |
| `swift run Peeky <path>` | 从源码直接运行（无 Finder 集成） |
| `swift run Peeky <path>:<line>` | 打开并跳到指定行 |
| `bash scripts/build-app.sh` | 组装 `.build/Peeky.app` + ad-hoc codesign（正式身份，供 CI 打包）；`--install` 装到 `~/Applications/Peeky Dev.app`，转成 dev 身份（`local.peeky.dev` / `peeky-dev://` / 独立 Preferences），symlink `~/.local/bin/peek` |
| `swift build --product PeekyTests && ./.build/debug/PeekyTests` | 运行全部测试（可加 `--filter <suite>`） |
| `scripts/run-hidden-tests.sh <unit>` | 运行该单元的 hidden 测试，仅输出 `PASSED: X/Y` |
| `node scripts/build-shiki-bundle.mjs` | 重新生成 `Sources/PeekyKit/Resources/shiki-bundle.js`（幂等；改语言或主题后运行） |
| `node scripts/shiki-bundle/smoke.mjs` | bundle 冒烟测试：3 种语言 tokenize + dark_modern 配色 + 分块续接断言 |
| `bash scripts/record-demo.sh` | 生成 README 用的 hero 视频与三张截图；子命令 `--stills` `--video`，屏幕索引 `--screen N` |

> 本机仅 CommandLineTools：`swift test` 会构建但**不会执行**（CLT 缺 xctest 执行器）；请使用上表的 PeekyTests 可执行文件运行测试。

## 测试策略（Test-First，双层）
- 叶子纯函数模块：`Tests/visible/` + `Tests/hidden/`（Swift Testing；suite 命名 `Visible_<unit>` / `Hidden_<unit>` 供 `--filter` 精确匹配；同 target 内文件 basename 必须唯一，命名 `<unit>Visible.test.swift` / `<unit>Hidden.test.swift`）。
- 测试是独立 executable `PeekyTests`（`Tests/entry.swift` 经 `Testing.__swiftPMEntryPoint()` 进入），`@testable import PeekyKit` 走 debug 构建。
- hidden 运行器：`scripts/run-hidden-tests.sh <unit>`，仅输出 `PASSED: X/Y`。
- Stub 阶段用 **degenerate 返回值**（空集合 / nil / 空串），测试以断言失败呈现失败状态（"全部 FAIL 且非编译错误"的信号）。测试内对 stub 可能返回的集合做下标访问必须经过 `try #require` 或安全下标；直接使用 `[0]` 会 trap 中止整个共享 PeekyTests 进程，其余用例都无法运行。

## 分支 / 上游
- 开发在本 fork 的 `main`；上游 `zhangzhejian/Peeky` 不追随，保持 commit 可回贡到上游的干净状态（一个功能一个干净的 commit）。
- 提交粒度是 plan 级，用户批准后 commit；不主动 push。

## 手动验收清单
- **任何 UI 或渲染改动必须在浅色与深色两种外观下各测试一次**（通过系统外观切换或 `defaults write -g AppleInterfaceStyle`）；颜色相关改动还需在两种外观下验证 resolve 后的亮度断言（背景与前景对比方向正确）。
- `swift run Peeky <md>` 打开后能直接显示 Markdown，侧栏 Contents tab 里的大纲支持点击跳转；Open / Files / Contents 三个 tab 点击切换，并记住上次选择；非 Markdown 文件的 Contents 置灰，自动回退到 Files。
- 多标题的 Markdown（≥40 个标题）打开后窗口高度不超出屏幕，可以自由 resize；Contents tab 的大纲占满侧栏高度，超出时自行滚动。
- 一个窗口里打开多个文件后连按 ⌘W：每次关掉当前文件并切到相邻文件，文件全部关完后窗口停在空状态，再按一次才关窗；⇧⌘W 任何时候直接关窗。
- `<json>` / `<jsonl>` 打开后应显示缩进格式化 + 词法高亮（key / 字符串 / 数字 / bool / null / 标点；浅色 GitHub Light、深色 VS Code Dark Modern，跟随系统明暗）；鼠标选中 ⌘C 可复制；行号 gutter 显示；JSONL 解析失败的行以红底红字标出，gutter 显示 "!"；滚动时可视区即时高亮，大文件不阻塞。
- `<py / ts / yaml …>` 打开后应显示 Dark Modern 主题高亮，深色背景统一；选中 ⌘C 可复制；⌘E 打开系统默认编辑器并跳到当前行。
- `.app` bundle 打包后，执行 `open "peeky://open?path=...&line=N"` 应打开正式版 Peeky 并定位到指定行；`open "peeky-dev://open?path=...&line=N"` 应打开本地 dev 版。
- 大文件的行为：非 JSON / JSONL 且大于 8 MB 时降级为 raw，不阻塞界面；JSON / JSONL 仍然进行缩进格式化 + 可视区惰性高亮，即使大文件也不阻塞。
