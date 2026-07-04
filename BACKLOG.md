# BACKLOG

## 执行中 · Plan: peek-native（→ .claude/plans/2026-07-03-peek-native.md）第一批（已批准 2026-07-04）

### Wave 0 — 地基 · 可并行
- [x] W0a 测试设施（v2：PeekyKit/Peeky/PeekyTests 三 target 拆分 + executable 测试 runner，绕开 CLT 无 xctest 执行器的坑；visible 直跑 3 绿 + hidden 运行器 PASSED: 2/2 ✅）
- [x] W0b build-app.sh 补 codesign + --install（codesign ✅ scheme 冒烟 ✅）

### Wave 1 — deps: W0 · 可并行（不同文件）
- [x] W1a repo-root 发现（双层 TDD：测试审查通过零修改；visible 3/3 + hidden 13/13 ✅）
- [x] W1b peek CLI（shell，零 Node）（行定位/空格/Unicode/负例冒烟 ✅；命令切换留 W5）

## 待批准 · 第二批（Wave 2 — 文件树，spec 已细化进 plan）
- [ ] W2a DirectoryLister 目录枚举（纯函数，双层 TDD）
      file: Sources/PeekyKit/DirectoryLister.swift
      spec: plan W2a（DirEntry / 目录优先排序 / .git·.DS_Store 过滤 / throws 语义）
      验收: visible + hidden 全绿
- [ ] W2b 目录打开 + repo-aware 文件树侧栏（deps: W2a）
      file: Sources/PeekyKit/FileTreeView.swift（新）+ PreviewWindowController / AppDelegate（接线）
      spec: plan W2b（NSOutlineView 惰性树 / 根=repo root / 点击开 tab / 目录路由不再被过滤）
      验收: 构建 + 冒烟清单（架构师执行）

（W3 高亮引擎 / W4 复制+表格 / W5 验收——逐波细化后另批）
