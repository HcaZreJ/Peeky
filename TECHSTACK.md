# TECHSTACK

## 语言 / 运行时
- **Swift 6.0**（swift-tools-version 6.0），macOS 13+，AppKit（无 SwiftUI、无 WebView）
- 构建仅需 **Xcode CommandLineTools**（纯 SwiftPM，无 Xcode 工程）

## 依赖
- **SPM 外部依赖：零**。只 import 系统框架 `AppKit` / `Foundation`。
- 引入任何第三方依赖需 plan 论证 + 用户批准（见 AGENTS.md 铁律）。

## 目录结构
```
peeky/
├── Package.swift              # SPM：单 executableTarget "Peeky"
├── Sources/Peeky/             # 全部源码（15 文件，见 PROJECT.md 模块地图）
├── Resources/                 # Info.plist（peeky:// scheme + DocumentTypes）+ 图标
├── scripts/build-app.sh       # swift build -c release + 组装 .build/Peeky.app
├── .github/workflows/build-app.yml  # 手动触发的打包 workflow（无测试/签名步骤）
└── .claude/plans/             # 跨 session 设计文档
```

## 构建产物
- `swift build -c release` → `.build/release/Peeky`（单二进制，~40s 全量编译）
- `scripts/build-app.sh` → `.build/Peeky.app`（bundle 组装：二进制 + Info.plist + icns；上游无 codesign 步骤）

## 分支现状
- `main`（基线）：JSONL gutter/overlay 富视图。
- `release-base`（本地，对应上游 `release`）：正则级源码高亮 + 精简 formatter，与 main 分叉；仅作参考（`SourceLanguage.swift` 的语言检测表可借鉴），不合入。
