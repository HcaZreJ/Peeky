# DEVFLOW

## 常用命令
| 命令 | 作用 |
|---|---|
| `swift build` | 增量 debug 构建 |
| `swift build -c release` | release 构建（全量 ~40s） |
| `swift run Peeky <path>` | 源码直接运行（无 Finder 集成） |
| `swift run Peeky <path>:<line>` | 打开并跳到行 |
| `bash scripts/build-app.sh` | 组装 `.build/Peeky.app` + ad-hoc codesign；`--install` 装 `~/Applications` + 链 `~/.local/bin/peek` |
| `swift build --product PeekyTests && ./.build/debug/PeekyTests` | 跑全部测试（可加 `--filter <suite>`） |
| `scripts/run-hidden-tests.sh <unit>` | 跑该单元 hidden 测试，仅输出 `PASSED: X/Y` |

> 本机仅 CommandLineTools：`swift test` 会构建但**静默不执行**（CLT 缺 xctest 执行器）——一律用上表的 PeekyTests 可执行文件跑测试。

## 测试策略（Test-First，双层）
- 叶子纯函数模块：`Tests/visible/` + `Tests/hidden/`（Swift Testing；suite 命名 `Visible_<unit>` / `Hidden_<unit>` 供 `--filter` 精确匹配；同 target 内文件 basename 必须唯一，命名 `<unit>Visible.test.swift` / `<unit>Hidden.test.swift`）。
- 测试是独立 executable `PeekyTests`（`Tests/entry.swift` 经 `Testing.__swiftPMEntryPoint()` 进入），`@testable import PeekyKit` 走 debug 构建。
- hidden 运行器：`scripts/run-hidden-tests.sh <unit>`（仅输出 `PASSED: X/Y`）。
- Stub 阶段以 `fatalError("NotImplemented")`：stub 未实现时测试进程崩溃且崩溃信息含 `NotImplemented`，以此作为"全 FAIL 且非编译错误"的红信号。

## 分支 / 上游
- 开发在本 fork 的 `main`；上游 `zhangzhejian/Peeky` 不追随，保持可回贡的 commit 卫生（一个功能一个干净 commit）。
- 提交粒度 plan 级，用户批准后 commit；不主动 push。

## 手动验收清单（转型期）
- **任何 UI/渲染改动须在浅色与深色两种外观下各过一遍**（系统外观切换或 `defaults write -g AppleInterfaceStyle`）；颜色类改动另需两外观 resolve 亮度断言（背景/前景对比方向正确）
- `swift run Peeky <md>` → 弹出即读，Markdown 大纲侧栏可点
- `<json>` / `<jsonl>` → 格式化 + 折叠 toggle + 坏行红标
- `.app` bundle 后 `open "peeky://open?path=...&line=N"` → 打开并定位到行
- 大文件（>8MB）→ 降级 raw 不卡死
