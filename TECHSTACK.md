# TECHSTACK

## 语言 / 运行时
- **Swift 6.0**（swift-tools-version 6.0），macOS 13+，AppKit + WebKit（markdown 预览用 WKWebView；无 SwiftUI）
- 系统框架：`AppKit` / `WebKit`（markdown WebView 渲染）/ `Foundation`（含 FSEvents，用于文件树的磁盘监听）/ `JavaScriptCore`（高亮引擎宿主）/ `os`（日志）；终端版另用 `ImageIO` / `CoreGraphics` / `CoreText`（读图片尺寸、缩放并编成 PNG，把标题文字画成图）
- 构建仅需 **Xcode CommandLineTools**（纯 SwiftPM，无 Xcode 工程）；重新生成 shiki bundle 需 Node ≥22（仅构建期）

## 依赖
- **SPM 第三方依赖仅 1 个**：`swiftlang/swift-markdown` `exact: 0.8.0`，用于 Markdown 解析（PeekyCore 与 PeekTUI 都依赖它的 `Markdown` product）；其 `Package.resolved` 内的 swift-cmark 为传递依赖。
- **mermaid.js 11.17.2**（JS 资源，不是 SPM 依赖；用户 2026-10-22 批准）：npm 发布包里的单文件构建 `dist/mermaid.min.js`，3,572,661 字节（gzip 约 0.98 MB）。mermaid 是 MIT 许可，打进去的依赖为 MIT / ISC，DOMPurify 取其 Apache-2.0 / MPL-2.0 双许可中的 Apache-2.0，各自的 license 注释原样留在文件里。checked-in 为 `Sources/PeekyCore/Resources/mermaid.min.js`，运行期离线。升级：改 `scripts/build-mermaid-bundle.sh` 里的版本号与 integrity（`npm view mermaid@<版本> dist.integrity`）再运行。12.x 的单文件构建打进了 EPL-2.0 许可的 elkjs、大 1.9 MB，所以停在 11.x。
- 引入任何新的第三方依赖需要 plan 论证 + 用户批准（见 AGENTS.md 铁律）。
- npm 依赖仅存在于构建期工具 `scripts/shiki-bundle/`（esbuild/shiki/jsonc-parser，全部精确锁版本，node_modules 不入库）；运行期零 Node。

## 目录结构
```
peeky/
├── Package.swift                    # SPM：PeekyCore(库) + PeekyKit(库) + Peeky(executable) + PeekTUI(库) + peek-tui(executable) + PeekyMermaid(库) + peeky-mermaid(executable) + PeekyTests(executable)
├── Package.resolved                 # 锁定 swift-markdown 0.8.0
├── Sources/Peeky/                   # 入口 main.swift
├── Sources/PeekyCore/               # 不依赖 AppKit/WebKit 的格式化、解析、高亮、文件树逻辑（见 PROJECT.md 模块地图）
│   ├── Resources/shiki-bundle.js    # checked-in 高亮引擎产物（~755KB，SPM resource）
│   ├── Resources/github-markdown.css # 内嵌 sindresorhus/github-markdown-css（markdown WebView 样式，SPM resource）
│   └── Resources/mermaid.min.js     # checked-in mermaid 11.17.2 单文件构建（~3.6MB，SPM resource）
├── Sources/PeekyKit/                # AppKit / WebKit 界面（窗口、视图、控制器），依赖 PeekyCore
├── Sources/PeekTUI/                 # 终端版：Screen/（宽度、格子、差异编码）· Input/（输入解析）· Terminal/（终端会话）· Document/（显示规则、按行存储、折行、着色、标题行）· Sidebar/（文件树、侧栏状态与渲染）· App/（状态、reducer、运行时）· View/（画面渲染），依赖 PeekyCore
├── Sources/peek-tui/                # 终端版入口 main.swift
├── Sources/PeekyMermaid/            # 离屏 WKWebView 把 Mermaid 源码画成 PNG（命令行解析 + 渲染进程），依赖 PeekyCore
├── Sources/peeky-mermaid/           # 渲染辅助程序入口 main.swift（终端版在后台调用）
├── Tests/                           # PeekyTests：entry.swift + visible/ + hidden/
├── Resources/                       # Info.plist（peeky:// scheme + DocumentTypes）+ 图标
├── bin/peek                         # CLI（shell，零 Node）
├── scripts/build-app.sh             # release 构建 + .app 组装 + codesign；--install
├── scripts/build-shiki-bundle.mjs   # esbuild 重新生成 shiki-bundle.js（幂等）
├── scripts/build-mermaid-bundle.sh  # 下载固定版本的 mermaid、按 sha512 校验、取出 mermaid.min.js（幂等，不需要 Node）
├── scripts/shiki-bundle/            # bundle 的 npm 工程（src 模板/vendor 主题/smoke.mjs）
├── scripts/run-hidden-tests.sh      # hidden 测试运行器（仅输出 PASSED: X/Y）
├── scripts/tui-smoke.sh             # 终端版真终端冒烟（隐藏的 kitty 窗口 + 远程控制读屏）
├── scripts/gen-width-table.py       # 由 Unicode EastAsianWidth.txt 生成 PeekTUI 的宽字符区间表
├── .github/workflows/build-app.yml  # 手动触发的打包 workflow
└── .claude/plans/                   # 跨 session 设计文档
```

## 构建产物
- `swift build -c release` → `.build/release/Peeky` + `.build/release/Peeky_PeekyCore.bundle`（SPM 资源包，内含 shiki-bundle.js + github-markdown.css）
- `swift build --product peek-tui` → `.build/out/Products/Debug/peek-tui`（终端版，零 AppKit）；release 构建在 `.build/release/peek-tui`（`.build/release` 指向 `out/Products/Release`）
- `swift build --product peeky-mermaid` → `.build/out/Products/Debug/peeky-mermaid`（与 peek-tui 同目录，开发构建的终端版据此画 Mermaid 图）
- `scripts/build-app.sh` → `.build/Peeky.app`（`Contents/MacOS/` 里是 `Peeky` 与 `peek-tui`，`Contents/Helpers/` 里是 `peeky-mermaid`，`Contents/Resources/` 里是 `peek` 脚本、icns、PeekyCore 资源包；先签 `peeky-mermaid` 再 ad-hoc codesign 整个 app）。包里的 `peek-tui` 以所在 app 为主 bundle，资源同样从 `Contents/Resources/` 找到；`peeky-mermaid` 经可执行文件所在目录的 `../Resources` 找到资源
- `CoreResources` 运行时寻找资源包：`Bundle.main.resourceURL`（`.app` 的 `Contents/Resources/`）、`Bundle.main.bundleURL`（`swift build` 输出目录）、可执行文件真实路径所在目录及其 `../Resources`，依次尝试；找不到时高亮降级为纯文本、Markdown 样式为空

## shiki bundle（高亮引擎）
- 语言：python/typescript/javascript/json/yaml/toml/bash/swift/ini（9 门，扩展名别名 16 个）
- 主题：VSCode `dark_modern.json`（include 链 dark_plus→dark_vs 拍平后内嵌）
- JS API（globalThis）：`peekyInit()` / `peekyTokenize(text, lang)` / `peekyTokenizeChunk(text, lang, stateId)`（`grammarState` 支持续接，旧句柄使用后立即释放）
- 引擎：shiki fine-grained core + `createJavaScriptRegexEngine({forgiving:true})`，无 WASM；`tokenizeMaxLineLength` 熔断超长行

## 分支现状
- `main`（基线）；`release-base`（本地，对应上游 `release`）：仅作参考，不合并进 main。
