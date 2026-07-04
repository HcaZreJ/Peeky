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
- **纯函数核心**：格式化/渲染/解析逻辑一律写成无状态 `enum` 命名空间的静态纯函数（现有 `PreviewRenderer`/`JSONFormatter`/`MarkdownRenderer` 风格），UI 状态只住在 `PreviewWindowController`。
- **零第三方 SPM 依赖**是默认；引入任何依赖需在 plan 中明确论证并经用户批准。
- **性能预算**：文件读取 80MB 上限、富格式化 8MB 上限、语法高亮 1.5M UTF-16 上限（`TextFileLoader`/`PreviewRenderer`/`SyntaxHighlighter` 中的既有常量），新功能不得绕过。
- **主线程纪律**：重计算（高亮、格式化大文件）放后台线程，UI 更新回主线程。
- 上游是 `zhangzhejian/Peeky`（口头授权 fork 改造）；本 fork 的开发不以跟随上游为目标，但保持可回贡的 commit 卫生。
