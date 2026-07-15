# BACKLOG

## 执行中 · Plan: peek-native 批次 1「渲染重做 + 复制可用性」 (→ .claude/plans/2026-07-03-peek-native.md)

（测试设施/RepoRoot/DirectoryLister/FileTreeView/codesign/peek CLI 已具备，44 测试全绿。）

### Wave 1 — 无依赖 · 可并行
- [x] R0  shiki bundle 构建脚本 ✅（bundle 755KB；smoke 3 语言 dark_modern 原色通过；产物资源化至 Sources/PeekyKit/Resources/）

### Wave 2 — 纯函数层 · 不同文件可并行（各单元先 test-author 后 implementer）
- [x] R1  JSON/JSONL 惰性索引 ✅（visible 3/3 + hidden 24/24；spike：80MB/430 万节点 0.35s，RSS 955MB 架构师裁定接受）
- [x] R2  Markdown 渲染器重写 ✅（visible 3/3 + hidden 19/19；swift-markdown exact 0.8.0；autolink 走 NSDataDetector）
- [x] R3  HighlightService ✅（visible 3/3 + hidden 17/17；冷路径预热实测 ~109ms；坏 bundle 永久降级）

### Wave 3 — UI 接线 · PreviewWindowController 热点严格串行（顺序 = 痛点优先级）
- [x] R4a gutter 重修 + 可选中复制 ✅（NSRulerView + TK1 enumerateLineFragments + lineStarts 命中法；lldb 证实 macOS 26 下正文/行号 layer 均提交像素；isSelectable=true）
- [x] R4b 复制五件套 + ⌘E ✅（六项入口双挂工具栏菜单+Edit 菜单；无 repo 动态隐藏；⌘E 走 vscode://cursor:// 行定位）
- [ ] R4c JSON 树视图核心           file: JSONOutlineView(新) + PreviewWindowController  deps: R1, R4b
        验收: issue #6 核心判据（80MB 可浏览/分桶/零竖线/坏行红标）——树已上屏/文本隐藏已证，行内容冒烟中
- [ ] R4d JSON 树交互层             file: JSONOutlineView + PreviewWindowController      deps: R4c
        验收: issue #6 交互判据（折叠命令族/path bar/空格预览/原文切换）
- [ ] R4e 高亮接入 + 主题统一        file: PreviewRenderer + PreviewWindowController      deps: R3, R4d
        验收: issue #9 判据（9 类型原色/首屏无感知延迟/超预算回退）
- [ ] R4f Markdown 接线 + 限宽阅读列 file: PreviewWindowController + PreviewRenderer      deps: R2, R4e
        验收: issue #8 判据（5 条排版规范勾验/8MB 流畅/大纲兼容）

### Wave 4 — 收尾 · 架构师亲自
- [ ] R5  集成验证 + 双审计 + 文档更新 + 关闭 issues #5-#9 + plan 级 commit
