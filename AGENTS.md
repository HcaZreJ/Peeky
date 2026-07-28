# AGENTS

进 repo 先读本文件与 PROJECT.md，动手前按需深入其余文档；开始新工作前查看 `.claude/plans/` 中 Status 非 Completed 的 plan，有则先了解上下文。

## 文档地图
| 文档 | 内容契约 |
|---|---|
| [PROJECT.md](PROJECT.md) | 项目目的、功能清单与当前状态、核心 data model、模块地图 |
| [PATTERNS.md](PATTERNS.md) | 设计范式：functional-core 约定、模块边界、命名、性能预算、测试约定 |
| [TECHSTACK.md](TECHSTACK.md) | 语言/运行时、零依赖原则、目录结构、构建产物 |
| [DEVFLOW.md](DEVFLOW.md) | 构建/运行/打包命令、分支策略、验收清单 |

## 本 repo 铁律
- **只读查看器**：不做编辑功能。
- **纯函数核心**：格式化 / 渲染 / 解析逻辑一律写成无状态 `enum` 命名空间的静态纯函数（沿用 `PreviewRenderer` / `JSONFormatter` / `MarkdownRenderer` 的风格），UI 状态只放在 `PreviewWindowController`。
- **默认零第三方 SPM 依赖**（当前仅有 `swift-markdown` 一个例外）；引入任何新依赖需要在 plan 中明确论证并经用户批准。
- **性能预算**：文件读取 80 MB 上限、富格式化 8 MB 上限、语法高亮 1.5M UTF-16 上限（分别定义在 `TextFileLoader` / `PreviewRenderer` / `SyntaxHighlighter`），新功能不得绕过。
- **主线程纪律**：重计算（高亮、大文件格式化）放在后台线程，UI 更新回主线程。
- 上游是 `zhangzhejian/Peeky`（口头授权 fork 改造）；本 fork 开发不追随上游，但保持 commit 状态干净可回贡。
