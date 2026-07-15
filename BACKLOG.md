# BACKLOG

## 执行中 · Plan: peek-native 批次 1「渲染重做 + 复制可用性」 (→ .claude/plans/2026-07-03-peek-native.md)

（测试设施/RepoRoot/DirectoryLister/FileTreeView/codesign/peek CLI 已具备，44 测试全绿。）

### Wave 1 — 无依赖 · 可并行
- [ ] R0  shiki bundle 构建脚本   file: scripts/build-shiki-bundle.mjs + Resources/shiki-bundle.js
        spec: R0（9 语言 + dark_modern 主题 + 分块续排入口，产物 checked-in）
        验收: bundle ≤1MB；3 语言 tokenize smoke 通过

### Wave 2 — 纯函数层 · 不同文件可并行（各单元先 test-author 后 implementer）
- [ ] R1  JSON/JSONL 惰性索引  file: Sources/PeekyKit/JSONTreeIndex.swift   deps: —
        spec: R1（单遍扫描节点表 + 值按需物化 + JSONL 逐记录 + 容错）
        验收: visible + hidden 全绿 + 80MB spike（≤5s / 内存 ≤2×）
- [ ] R2  Markdown 渲染器重写  file: Sources/PeekyKit/MarkdownRenderer.swift  deps: —
        spec: R2（swift-markdown visitor + GFM 全特性 + Primer 排版数值）
        验收: visible + hidden 全绿；8MB 预算沿用
- [ ] R3  HighlightService    file: Sources/PeekyKit/HighlightService.swift  deps: R0
        spec: R3（JSContext 单例 + 后台队列 + 预热 + 分块 + 降级）
        验收: visible + hidden 全绿（dark_modern 原色断言/预算回退/坏 bundle 降级）

### Wave 3 — UI 接线 · PreviewWindowController 热点严格串行（顺序 = 痛点优先级）
- [ ] R4a gutter 重修 + 可选中复制   file: PreviewGutterView + PreviewWindowController   deps: —
        验收: issue #5 判据（滚动行号一致/折行首行编号/可选中 ⌘C/不可编辑）
- [ ] R4b 复制五件套 + ⌘E          file: PreviewWindowController + AppDelegate         deps: R4a
        验收: issue #7 判据（六项入口 + 粘贴/打开逐项正确）
- [ ] R4c JSON 树视图核心           file: JSONOutlineView(新) + PreviewWindowController  deps: R1, R4b
        验收: issue #6 核心判据（80MB 可浏览/分桶/零竖线/坏行红标）
- [ ] R4d JSON 树交互层             file: JSONOutlineView + PreviewWindowController      deps: R4c
        验收: issue #6 交互判据（折叠命令族/path bar/空格预览/原文切换）
- [ ] R4e 高亮接入 + 主题统一        file: PreviewRenderer + PreviewWindowController      deps: R3, R4d
        验收: issue #9 判据（9 类型原色/首屏无感知延迟/超预算回退）
- [ ] R4f Markdown 接线 + 限宽阅读列 file: PreviewWindowController + PreviewRenderer      deps: R2, R4e
        验收: issue #8 判据（5 条排版规范勾验/8MB 流畅/大纲兼容）

### Wave 4 — 收尾 · 架构师亲自
- [ ] R5  集成验证 + 双审计 + 文档更新 + 关闭 issues #5-#9 + plan 级 commit
