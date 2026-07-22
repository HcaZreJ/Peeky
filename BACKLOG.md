# BACKLOG

## 执行中 · Plan: json-viewer-parity   (→ .claude/plans/json-viewer-parity.md)

- [x] F1  折叠结构索引（纯函数）JSONFoldMap.swift  hidden 14/14
- [x] F3  PeekyTheme 新语义色（折叠/导轨/状态栏 7 token）  hidden 15/15
- [x] F2  折叠合成 + 双向坐标映射（纯函数）JSONFoldComposer.swift  hidden 22/22
- [x] F4  gutter 折叠三角/点击/跳号  PreviewGutterView.swift
- [x] F5  正文导轨虚线/折叠 chip/双击选区/复制  DropContainerView.swift
- [x] F6  控制器接线（fold 状态机/状态栏/显示管线）PreviewWindowController.swift
- [ ] F7  用户目检验收：`swift run Peeky` 演示窗口已开，等用户反馈 bug/优化清单
        （架构师侧已过：浅色静态像素 + 30k 行 JSONL 冒烟（412k 行/6 坏行/CPU 安定）+ 全量 280 例测试绿）

---
（既有后续跟踪：代码高亮 issue #16、原生死路径清理 issue #17、GLFM issue #14、JSON 工具栏 issues #21–#24；
已知独立事项：Hidden_markdownRenderer 偶发 flaky 先于本 plan 存在，基线 34d47d1 上 3/40 复现，待单独排查。）
