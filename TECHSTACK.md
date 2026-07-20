# TECHSTACK

## 语言 / 运行时
- **Swift 6.0**（swift-tools-version 6.0），macOS 13+，AppKit（无 SwiftUI、无 WebView）
- 系统框架：`AppKit` / `Foundation` / `JavaScriptCore`（高亮引擎宿主）/ `os`（日志）
- 构建仅需 **Xcode CommandLineTools**（纯 SwiftPM，无 Xcode 工程）；重新生成 shiki bundle 需 Node ≥22（仅构建期）

## 依赖
- **SPM 第三方依赖：仅 1 个**——`swiftlang/swift-markdown` `exact: 0.8.0`（Markdown 解析，2026-07-15 用户批准；其 Package.resolved 内的 swift-cmark 为传递依赖）。
- 引入任何新第三方依赖需 plan 论证 + 用户批准（见 AGENTS.md 铁律）。
- npm 依赖仅存在于构建期工具 `scripts/shiki-bundle/`（esbuild/shiki/jsonc-parser，全部精确锁版本，node_modules 不入库）；运行期零 Node。

## 目录结构
```
peeky/
├── Package.swift                    # SPM：PeekyKit(库) + Peeky(executable) + PeekyTests(executable)
├── Package.resolved                 # 锁定 swift-markdown 0.8.0
├── Sources/Peeky/                   # 入口 main.swift
├── Sources/PeekyKit/                # 全部实现（见 PROJECT.md 模块地图）
│   └── Resources/shiki-bundle.js    # checked-in 高亮引擎产物（~755KB，SPM resource）
├── Tests/                           # PeekyTests：entry.swift + visible/ + hidden/
├── Resources/                       # Info.plist（peeky:// scheme + DocumentTypes）+ 图标
├── bin/peek                         # CLI（shell，零 Node）
├── scripts/build-app.sh             # release 构建 + .app 组装 + codesign；--install
├── scripts/build-shiki-bundle.mjs   # esbuild 重新生成 shiki-bundle.js（幂等）
├── scripts/shiki-bundle/            # bundle 的 npm 工程（src 模板/vendor 主题/smoke.mjs）
├── scripts/run-hidden-tests.sh      # hidden 测试运行器（仅输出 PASSED: X/Y）
├── .github/workflows/build-app.yml  # 手动触发的打包 workflow
└── .claude/plans/                   # 跨 session 设计文档
```

## 构建产物
- `swift build -c release` → `.build/release/Peeky` + `.build/release/Peeky_PeekyKit.bundle`（SPM 资源包，内含 shiki-bundle.js）
- `scripts/build-app.sh` → `.build/Peeky.app`（二进制 + Info.plist + icns + PeekyKit 资源包，ad-hoc codesign）
- `HighlightService` 运行时寻径资源包：`.app` 的 `Contents/Resources/` 与 `swift build` 输出目录两个候选，找不到走纯文本降级（不崩溃）

## shiki bundle（高亮引擎）
- 语言：python/typescript/javascript/json/yaml/toml/bash/swift/ini（9 门，扩展名别名 16 个）
- 主题：VSCode `dark_modern.json`（include 链 dark_plus→dark_vs 拍平后内嵌）
- JS API（globalThis）：`peekyInit()` / `peekyTokenize(text, lang)` / `peekyTokenizeChunk(text, lang, stateId)`（grammarState 续排，旧句柄即用即删）
- 引擎：shiki fine-grained core + `createJavaScriptRegexEngine({forgiving:true})`，无 WASM；`tokenizeMaxLineLength` 熔断超长行

## 分支现状
- `main`（基线）；`release-base`（本地，对应上游 `release`）：仅作参考，不合入。
