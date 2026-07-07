# Feature: peek-native —— fork peeky 为基底的全原生转型

## Overview
peek 因 web 栈冷启感知（内容可读 ~1.0s，WebKit 进程树 ~200ms 为架构固有）被用户裁定放弃 TypeScript 渲染栈；fork `zhangzhejian/Peeky`（口头授权）为基底做全原生 macOS app，目标"弹出即可读" ~0.4s，并保住 peek 的四项差异化底线。web 栈 peek 存档于 `~/Documents/peek` @ `64bb100`。

## Intent Brief
- **Goal**：`peek <path>` → 原生窗口 ~0.4s 内容可读；四项底线全保：① repo-aware 树 + 相对 repo root 路径复制 ② JSONL 记录流/表格 ③ VSCode Dark Modern 高亮保真 ④ CLI 唤起。
- **Motivation**：用户对启动速度零容忍（"慢不可接受，否则不如用 yazi"）。
- **Known context**（分析师报告 + 架构师审查 + spike，2026-07-03）：
  - peeky：Swift 6 SPM 零依赖纯 AppKit，functional-core（叶子纯函数模块 + 单一有状态 `PreviewWindowController` 1031 行）；tabs/多窗口/`peeky://open?path=&line=&cwd=`/`path:line` CLI/Markdown 大纲/JSONL 记录流(gutter+摘要+坏行红标)/三级性能预算/Ghostty OSC-8 集成已现成。
  - peeky 没有：目录浏览/文件树（`TextFileLoader` 拒绝目录）、repo-root 概念、真表格视图、TextMate 级高亮（main 分支仅 JSON/XML 正则高亮；release 分支为关键词级+系统色，不合入）、测试设施、codesign。
  - **JSC+Shiki spike 已验证**：esbuild 打包 shiki fine-grained core（dark-plus + JS 正则引擎 forgiving）= 588K bundle；Swift `JSContext` 中 eval 12ms + init 8ms + 首次 tokenize 349ms（冷 JIT，可后台预热）；token 颜色为 VSCode dark-plus 原色。
  - `swift build -c release` 全量 ~40s 本地验证通过。
- **Constraints**：peeky repo 铁律（functional-core、零 SPM 依赖默认、三级性能预算、主线程纪律，见 AGENTS.md）；shiki-bundle.js 为构建期生成物 checked-in（运行期零 Node、零 server、零 WebKit）。
- **Non-goals**：跟随上游 release 分支；编辑功能；跨平台。
- **Success criteria**：交替冷启实测 time-to-window ≤ 450ms 且弹出即可读；四底线逐项验收；叶子纯函数模块双层测试全绿。

## Alignment Gate
- **I will implement**：下方 W0–W5。
- **I will not implement**：上游 release 正则高亮合入；Tauri/Electron/WebView 任何回归。
- **Open assumptions**（用户确认前 W3+ 不派发）：
  - 高亮引擎 = JSC+Shiki（强推荐，spike 已焊死；备选 tree-sitter 全原生但保真近似）
  - repo 策略 = peeky repo 主战场、CLI 命名 `peek`、peek repo 归档
- **Acceptance criteria**：同 Success criteria。

## Assumption Ledger
| Assumption | Confidence | Impact if Wrong | Status |
|---|---:|---:|---|
| 高亮引擎 = JSC+Shiki | 决策 | — | closed（2026-07-03 用户授权架构师裁定，选 JSC+Shiki） |
| 首次 tokenize 349ms 可由启动后台预热消化 | high | low：首文件高亮迟 ~300ms | W3 验收关闭 |
| 主战场 = peeky repo | high | low：文件平移 | open — 已问 |
| JSONL 表格的列推导可复用 peek 的 collectColumns 语义（Swift 移植） | high | low | W4 spec 时定 |
| DirectoryLister 排序 tie-break（同 fold 不同字节）契约保留但 fixture 级未测——本机 APFS 大小写不敏感无法构造共存名；场景仅存在于大小写敏感卷 | high | low：极端场景排序次序不定 | 接受（架构师裁定 2026-07-04） |

## Work-Unit Specs

### Wave 0 — 地基（无依赖，可并行）
```yaml
- id: W0a
  title: 测试设施：testTarget + 双层 harness + hidden 运行器
  file_path: Package.swift + Tests/ + scripts/run-hidden-tests.sh
  behavioral_contract: |
    Package.swift 增 testTarget "PeekyTests"（Swift Testing）；目录 Tests/visible/、
    Tests/hidden/；scripts/run-hidden-tests.sh <unit> 用
    `swift test --filter <unit>` 跑 hidden 并只输出 "PASSED: X/Y"（解析
    swift test 输出，用例名/失败详情均訡吞掉）；一个 smoke 测试（对
    FileKind.detect 的 3 断言）验证管道通。executableTarget 拆出可测的
    库 target（executable 无法被 testTarget import 时的标准 SPM 处理）。
  acceptance: swift test 全绿；run-hidden-tests.sh 输出格式正确。
- id: W0b
  title: build-app.sh 补 codesign + 安装路径
  file_path: scripts/build-app.sh
  behavioral_contract: |
    组装后 `codesign --force --sign -`；新增 `--install` 选项拷贝到
    ~/Applications/Peeky.app（scheme/DocumentTypes 注册生效位置固定）。
  acceptance: codesign --verify 通过；--install 后 open peeky:// 可达。
```

### Wave 1 — CLI 与 repo-root（deps: W0a；两单元不同文件可并行）
```yaml
- id: W1a
  title: repo-root 发现（Swift 纯函数，双层 TDD）
  file_path: Sources/Peeky/RepoRoot.swift
  behavioral_contract: |
    discoverRepoRoot(from: URL) -> URL?：自起点向上找最近的含 VCS 标记
    （.git/.hg/.svn，文件或目录均可——git worktree 的 .git 是文件）的目录；
    到文件系统根/home 仍无标记 → nil。语义与 peek 的 discoverRepoRoot 一致
    （只认 VCS 标记，弱标记一律不钉根——历史教训：home 树根爆炸）。
  acceptance: visible + hidden 全绿（临时目录 fixture）。
- id: W1b
  title: peek CLI（shell，零 Node）
  file_path: bin/peek + scripts/build-app.sh（--install 联动装 CLI）
  behavioral_contract: |
    peek [<path>[:line[:col]]] （无参 = .）：绝对化路径（相对→$PWD）后
    open -a ~/Applications/Peeky.app "peeky://open?path=<enc>&cwd=<enc>[&line=&column=]"；
    app 不存在 → stderr 提示先跑 build-app.sh --install，exit 1。
    路径不存在 → stderr + exit 1。目录路径同样传递（W2 后 app 支持目录）。
  acceptance: 手动冒烟：peek <file>:12 打开并定位（app 侧 scheme 已现成）。
```

### Wave 2 — 文件树侧栏（deps: W1a；W2a→W2b 串行，W2b 碰热点文件）
```yaml
- id: W2a
  title: DirectoryLister 目录枚举（纯函数，双层 TDD）
  file_path: Sources/PeekyKit/DirectoryLister.swift（新）
  functions:
    - name: DirectoryLister.list
      signature: "static func list(dir: URL) throws -> [DirEntry]"
      behavioral_contract: |
        DirEntry { name: String, url: URL, isDirectory: Bool, size: Int64, mtime: Date }
        （public struct，Equatable）。列举 dir 直接子项：
        - 排序：目录在前、文件在后，各自按 name 不区分大小写升序
          （caseInsensitiveCompare；相等时按 name 字节序稳定次序）。
        - 过滤：名为 .git/.hg/.svn/.DS_Store 的条目一律不出现；其余条目
          （含其它 dotfile、node_modules）均出现。
        - size：文件为字节数；目录为 0。mtime 为条目修改时间。
        - symlink 条目按其自身呈现（isDirectory 以 symlink 解析目标判定，
          不递归展开）。
      error_cases:
        - { condition: "dir 不存在或不是目录或不可读", behavior: "throws（错误类型不限，语义可辨即可）" }
  acceptance: visible + hidden 全绿。
- id: W2b
  title: 目录打开 + repo-aware 文件树侧栏（UI + 接线）
  file_path: Sources/PeekyKit/FileTreeView.swift（新）
            + PreviewWindowController.swift / AppDelegate.swift（接线）
  behavioral_contract: |
    - sidebar 新增文件树区（NSOutlineView，惰性数据源：展开某目录时才调
      DirectoryLister.list，结果缓存至窗口刷新）。
    - 树根 = RepoRoot.discover(from: 目标) ?? （目标为目录 ? 目标 : 其父目录）；
      根节点标题显示根目录名。首次建树自动展开到当前打开文件并选中之。
    - 单击文件节点 → 复用既有 open(requests:) 在本窗口开/选 tab；单击目录
      节点仅展开/折叠。
    - 打开目录路径（CLI/scheme/拖放/Open 面板）→ 不再被过滤：路由到目标窗口
      并以该目录建树（不产生内容 tab；TextFileLoader 拒目录行为保留）。
    - 树区与既有 tab 列表、Markdown 大纲共存：三区纵向排布，树区可折叠。
    - DirectoryLister.list throws 时该节点显示单行"(无法读取)"占位，不崩溃。
  acceptance: |
    构建 + 冒烟（架构师执行）：peek <repo内文件> → 树根钉 repo root 且定位
    到该文件；peek <repo外目录> → 树根为该目录；点击树中文件开 tab；
    .git/.DS_Store 不出现在树中。
  测试边界（架构师裁定，沿用先例）: AppKit UI 走构建+冒烟；纯逻辑已在 W2a 覆盖。
```

### Wave 3 — Dark Modern 高亮（deps: W0a + 用户引擎确认；spec 在决策后细化）
```yaml
- id: W3（骨架，待引擎确认后拆 3 个 unit）
  组成: HighlightService（JSContext 封装+后台队列+启动预热+1.5M 预算沿用）
       / scripts/build-shiki-bundle.mjs（esbuild 生成，产物 checked-in Resources/）
       / PreviewRenderer+WindowController 接入（纯文本先行，token 到达原位上色）
       / Dark Modern 主题统一（编辑器底色/前景色替换系统语义色）
```

### Wave 4 — 复制四件套 + JSONL 表格（deps: W2/W3；spec 于 Wave 2 完成后细化）
```yaml
- id: W4a: 复制菜单（文件名/绝对路径/相对 repo root 路径/内容），挂 copyButton → NSMenu
- id: W4b: JSONL 表格视图（NSTableView 备选渲染 + 列推导纯函数 collectColumns 移植，双层 TDD）
```

### Wave 5 — 端到端验收 + 收尾（架构师亲自）
```yaml
- id: W5: 交替冷启计时（measure-ttw 工具复用）；四底线逐项验收；
        peeky 五文档就地更新；peek repo 归档（README 指针 + PROJECT 状态行）
```

## Dependency Graph
```
W0a ──┬── W1a ──── W2 ──┬── W4a/W4b ── W5
W0b ──┤                 │
      └── W3（引擎确认后）┘
W1b（依赖 W0b 的 --install）
```
无环。`PreviewWindowController.swift` 为单文件热点：W2 / W3 接入 / W4 严格串行经过它。

## Execution Waves
批次交付：先派 W0+W1（BACKLOG 第一批），W2 起逐波细化 spec 再派。

## Status
Awaiting user decision —— 引擎与 repo 策略两项确认后，第一批 BACKLOG 送批。
