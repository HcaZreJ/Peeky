# BACKLOG

## 执行中 · Plan: json-viewer-parity   (→ .claude/plans/json-viewer-parity.md)

### Wave 1 — 无依赖 · 可并行
- [x] F1  折叠结构索引（纯函数）        file: Sources/PeekyKit/JSONFoldMap.swift（新）  hidden 14/14
- [x] F3  PeekyTheme 新语义色           file: Sources/PeekyKit/PeekyTheme.swift  hidden 15/15

### Wave 2 — deps: F1
- [x] F2  折叠态文本合成 + 双向坐标映射（纯函数）   file: Sources/PeekyKit/JSONFoldComposer.swift（新）  hidden 22/22

### Wave 3 — deps: F2, F3 · 不同文件可并行 · 执行中
- [ ] F4  gutter 折叠三角 + 点击 + 跳号   file: Sources/PeekyKit/PreviewGutterView.swift
        验收: 构建干净 + 全量测试绿；三角/跳号像素验收并入 F7
- [ ] F5  正文导轨虚线 + 折叠 chip + 双击选区/复制   file: Sources/PeekyKit/DropContainerView.swift
        验收: 构建干净 + 全量测试绿；导轨/chip/copy 验收并入 F7

### Wave 4 — deps: F1–F5
- [ ] F6  控制器接线：fold 状态/状态栏/高亮坐标适配   file: Sources/PeekyKit/PreviewWindowController.swift
        验收: 全量测试绿 + 折叠/滚动/选中链路 lldb 冒烟

### Wave 5 — deps: F6
- [ ] F7  集成像素验收（架构师亲自）：明暗两态 × 样板六图特征逐项对照 + 几万行 JSONL 冒烟

---
（既有后续跟踪：代码高亮 issue #16、原生死路径清理 issue #17、GLFM issue #14；JSON/JSONL follow-up 记于 `.claude/plans/2026-07-20-json-jsonl-render-simplify.md` 的 Follow-ups 节。）
