---
title: Peeky Showcase
tags: [markdown, preview]
authors:
  - HcaZreJ
---

# Peeky 的 Markdown 渲染

Peeky 用 `swift-markdown` 解析成 HTML，再用 `github-markdown.css` 呈现，样式与 GitHub 一致。

## 标题、列表、链接

- YAML frontmatter 被剥离后单独渲染
- h1 到 h4 会被抽出来作为文档大纲
- 链接、行内 `code`、**加粗** 和 *斜体* 都按 GitHub 规范渲染

访问 [Peeky 仓库](https://github.com/HcaZreJ/peeky)。

## 代码块

```swift
enum PreviewRenderer {
    static func render(_ text: String, kind: FileKind) -> RenderedPreview {
        switch kind {
        case .markdown: return MarkdownRenderer.render(text)
        case .json:     return JSONFormatter.format(text)
        default:        return .plain(text)
        }
    }
}
```

## 表格

| 格式 | 渲染方式 |
|---|---|
| Markdown | swift-markdown + github-markdown.css |
| JSON | `JSONSerialization` + 词法高亮 |
| Swift | shiki + VS Code Dark Modern |

> 富格式化的上限是 8 MB，超过会降级为等宽原文。
