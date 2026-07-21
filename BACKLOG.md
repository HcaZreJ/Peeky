# BACKLOG

## 待批准 · Plan: json-viewer-parity   (→ .claude/plans/json-viewer-parity.md)

### Wave 1 — 无依赖 · 可并行
- [ ] F1  折叠结构索引（纯函数）        file: Sources/PeekyKit/JSONFoldMap.swift（新）
        spec: JSONFoldMap.build（FoldRegion 表 + 每行缩进深度，单遍扫描，坏行跳过）
        验收: F1 visible+hidden 全绿（深嵌套/JSONL 多记录/坏行/大文本）
- [ ] F3  PeekyTheme 新语义色           file: Sources/PeekyKit/PeekyTheme.swift
        spec: indentGuide / foldChip* / statusBar* / gutterDisclosure，light+dark 双套
        验收: peekyTheme 单元全绿（两外观解析 + 亮度方向断言）

### Wave 2 — deps: F1
- [ ] F2  折叠态文本合成 + 双向坐标映射（纯函数）   file: Sources/PeekyKit/JSONFoldComposer.swift（新）
        spec: compose(source, foldMap, collapsed) → 可见文本/chip 位置/跳号行表/深度表/单调段表
        验收: F2 visible+hidden 全绿（恒等/单折/嵌套折/跨 chip 映射）

### Wave 3 — deps: F2, F3 · 不同文件可并行
- [ ] F4  gutter 折叠三角 + 点击 + 跳号   file: Sources/PeekyKit/PreviewGutterView.swift
        验收: 截图见三角两态；lldb 触发 toggle 后行号跳号正确
- [ ] F5  正文导轨虚线 + 折叠 chip + 双击选区/复制   file: Sources/PeekyKit/DropContainerView.swift
        验收: 截图见导轨/chip；copy 断言=完整底层源文本

### Wave 4 — deps: F1–F5
- [ ] F6  控制器接线：fold 状态/状态栏/高亮坐标适配   file: Sources/PeekyKit/PreviewWindowController.swift
        验收: 全量测试绿 + 折叠/滚动/选中链路 lldb 冒烟

### Wave 5 — deps: F6
- [ ] F7  集成像素验收（架构师亲自）：明暗两态 × 样板六图特征逐项对照 + 几万行 JSONL 冒烟

---
（既有后续跟踪：代码高亮 issue #16、原生死路径清理 issue #17、GLFM issue #14；JSON/JSONL follow-up 记于 `.claude/plans/2026-07-20-json-jsonl-render-simplify.md` 的 Follow-ups 节。）
