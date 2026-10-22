import Foundation
import ImageIO
import Testing
@testable import PeekyCore
@testable import PeekTUI

// MARK: - 终端图片可见样例
//
// kitty 图片协议的 Unicode 占位符：每格是 U+10EEEE 加行号、列号附加符，前景色是图片编号；图以静默方式
// 分块传给终端。Markdown 里单独成段的本地图片在读到像素尺寸后排成占位符行（不放大，不超过正文宽与
// 30 行，保持长宽比），复制得到「[图片] 说明」；没读到尺寸、行内的图按文字显示。终端名是 kitty /
// Ghostty、报了格子像素尺寸、回答了图片协议探测，三样齐了才显示图片。终端不支持放大文字（Ghostty）时
// 顶层 H1 / H2 画成图：每个折行占两行，复制得到标题文字；支持放大文字（kitty）时仍用放大文字。

private let cell = PixelSize(width: 10, height: 20)
private let base = URL(fileURLWithPath: "/docs", isDirectory: true)

private func rendering(_ source: String, sizes: [String: PixelSize] = [:], width: Int = 44) -> MarkdownRendering {
    MarkdownLayout.render(source, width: width, theme: .dark, images: MarkdownImageContext(cell: cell, sizes: sizes, baseDirectory: base))
}

private func rowText(_ row: MarkdownRow) -> String {
    row.spans.map(\.text).joined()
}

@Suite("Visible_terminalImage")
struct Visible_terminalImage {
    @Test("占位文字：每格一个占位字符带行号、列号附加符，占 1 格；图片编号写成前景色")
    func placeholderText() {
        let text = ImagePlaceholder.rowText(row: 1, columns: 3)
        #expect(text.count == 3)
        #expect(TextWidth.width(of: text) == 3)
        #expect(text.unicodeScalars.map(\.value) == [0x10EEEE, 0x030D, 0x0305, 0x10EEEE, 0x030D, 0x030D, 0x10EEEE, 0x030D, 0x030E])
        #expect(ImagePlaceholder.color(for: 4242) == .rgb(0, 0x10, 0x92))
    }

    @Test("传输：静默、按 4096 字节分块，第一块带编号与格数并建虚拟放置；删除带编号")
    func transmissionChunks() {
        let escape = ImagePlaceholder.transmission(id: 7, png: Data(repeating: 0xAB, count: 5000), columns: 4, rows: 2)
        let chunks = escape.components(separatedBy: "\u{1B}\\").filter { !$0.isEmpty }
        #expect(chunks.count == 2)
        #expect(chunks[0].hasPrefix("\u{1B}_Ga=T,U=1,i=7,f=100,c=4,r=2,q=2,m=1;"))
        #expect(chunks[0].count == "\u{1B}_Ga=T,U=1,i=7,f=100,c=4,r=2,q=2,m=1;".count + 4096)
        #expect(chunks[1].hasPrefix("\u{1B}_Gm=0;"))
        #expect(ImagePlaceholder.deletion(id: 7) == "\u{1B}_Ga=d,d=I,i=7,q=2\u{1B}\\")
    }

    @Test("占几格：宽图被正文宽度限住；高图被 30 行限住、列数按比例缩；小图不放大")
    func imageCells() {
        let wide = MarkdownLayout.imageCells(PixelSize(width: 2160, height: 1464), cell: PixelSize(width: 14, height: 25), maxColumns: 60, maxRows: 30)
        #expect(wide.columns == 60 && wide.rows == 23)
        let tall = MarkdownLayout.imageCells(PixelSize(width: 100, height: 2000), cell: cell, maxColumns: 80, maxRows: 30)
        #expect(tall.columns == 3 && tall.rows == 30)
        let small = MarkdownLayout.imageCells(PixelSize(width: 40, height: 40), cell: cell, maxColumns: 80, maxRows: 30)
        #expect(small.columns == 4 && small.rows == 2)
    }

    @Test("本地路径：相对文档目录、解百分号、去掉 ?… #…；file: 取路径；网络地址不算")
    func localPaths() {
        #expect(MarkdownLayout.localImagePath("img/a%20b.png?raw=1#x", baseDirectory: base) == "/docs/img/a b.png")
        #expect(MarkdownLayout.localImagePath("../shots/c.png", baseDirectory: base) == "/shots/c.png")
        #expect(MarkdownLayout.localImagePath("/abs/d.png", baseDirectory: base) == "/abs/d.png")
        #expect(MarkdownLayout.localImagePath("file:///abs/e.png", baseDirectory: base) == "/abs/e.png")
        #expect(MarkdownLayout.localImagePath("https://example.com/f.png", baseDirectory: base) == nil)
    }

    @Test("Markdown：单独成段的本地图片有尺寸时排成占位符行，复制得到「[图片] 说明」；没有尺寸、行内的图按文字显示")
    func markdownBlockImage() {
        let source = "before\n\n![Diagram](img/a.png)\n\ninline ![x](img/b.png) text\n\nafter"
        let plain = rendering(source)
        #expect(plain.imageSources == ["/docs/img/a.png", "/docs/img/b.png"])
        #expect(plain.rows.contains { rowText($0).contains("[图片] Diagram") })

        let laidOut = rendering(source, sizes: ["/docs/img/a.png": PixelSize(width: 200, height: 100)])
        let imageRows = laidOut.rows.filter { $0.image != nil }
        let image = try! #require(imageRows.first?.image)
        #expect(image.columns == 20 && image.rows == 5)
        #expect(imageRows.count == 5)
        #expect(imageRows.enumerated().allSatisfy { index, row in rowText(row) == "  " + ImagePlaceholder.rowText(row: index, columns: 20) })
        #expect(imageRows[0].spans.contains { $0.style.foreground == ImagePlaceholder.color(for: image.id) })
        #expect(laidOut.rows.contains { rowText($0).contains("[图片] x") })

        let first = try! #require(laidOut.rows.firstIndex { $0.image != nil })
        let selection = TextSelection(anchor: TextPoint(line: first - 2, column: 0), head: TextPoint(line: first + 6, column: 0))
        #expect(SelectionText.markdownText(selection, rows: laidOut.rows) == "before\n\n[图片] Diagram\n")
    }

    @Test("终端能力齐了才排图片：先重排，排出的图去读尺寸，读到后带尺寸重排；同一张图不重复读")
    func capabilityProbeAndRelayout() {
        let text = "![Diagram](img/a.png)"
        var state = TUIState(size: TerminalSize(columns: 60, rows: 20), document: .loading(path: "a.md"))
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "a.md", details: ""),
            store: LineStore(text),
            presentation: .markdown,
            markdown: MarkdownLayout.render(text, width: 60, theme: .dark),
            baseDirectory: base
        ), generation: state.generation))
        #expect(TUIReducer.reduce(&state, .input(.terminalName("kitty(0.49.2)"))).isEmpty)
        #expect(TUIReducer.reduce(&state, .input(.cellPixelSize(width: 10, height: 20))).isEmpty)
        let relayout = TUIReducer.reduce(&state, .input(.graphicsReply(id: TUIReducer.graphicsProbeID, message: "OK")))
        #expect(state.supportsImages)
        guard case let .layoutMarkdown(_, _, _, _, _, _, images) = relayout.first else { Issue.record("没有重排"); return }
        // 这个终端没回答放大文字探测：标题也画成图
        #expect(images == MarkdownImageContext(cell: cell, baseDirectory: base, headingImages: true))

        let probe = TUIReducer.reduce(&state, .markdownLaidOut(MarkdownLayout.render(text, width: 60, theme: .dark, images: images), generation: state.generation))
        #expect(probe.contains(.probeImages(paths: ["/docs/img/a.png"], generation: state.generation)))
        let sizes = ["/docs/img/a.png": PixelSize(width: 200, height: 100)]
        let withSizes = TUIReducer.reduce(&state, .imagesProbed(sizes, generation: state.generation))
        guard case let .layoutMarkdown(_, _, _, _, _, _, sized) = withSizes.first else { Issue.record("没有带尺寸重排"); return }
        #expect(sized?.sizes == sizes)
        let again = TUIReducer.reduce(&state, .markdownLaidOut(MarkdownLayout.render(text, width: 60, theme: .dark, images: sized), generation: state.generation))
        #expect(!again.contains { if case .probeImages = $0 { return true } else { return false } })
    }

    @Test("帧里带上视口里出现的图，滚出视口后不再带")
    func frameListsVisibleImages() {
        let text = "![Diagram](img/a.png)\n\n" + Array(repeating: "para", count: 30).joined(separator: "\n\n")
        var state = TUIState(size: TerminalSize(columns: 60, rows: 10), document: .loading(path: "a.md"))
        _ = TUIReducer.reduce(&state, .loaded(OpenedDocument(
            header: DocumentHeader(displayPath: "a.md", details: ""),
            store: LineStore(text),
            presentation: .markdown,
            markdown: rendering(text, sizes: ["/docs/img/a.png": PixelSize(width: 200, height: 100)], width: 60)
        ), generation: state.generation))
        #expect(FrameRenderer.render(state).images.count == 1)
        state.viewport.top = ScrollPosition(line: 20, row: 0)
        #expect(FrameRenderer.render(state).images.isEmpty)
    }

    @Test("不支持放大文字时 H1 / H2 画成图：各占两行，复制得到标题文字，大纲与锚点照旧，H2 下有分隔线")
    func headingsAsImages() {
        let context = MarkdownImageContext(cell: cell, baseDirectory: base, headingImages: true)
        let laidOut = MarkdownLayout.render("# Title\n\n## Sub\n\ntext", width: 44, theme: .dark, images: context)
        let h1 = laidOut.rows.prefix(2).compactMap(\.image)
        #expect(h1.count == 2)
        #expect(h1.first?.content == .heading(text: "Title", red: 0xF0, green: 0xF6, blue: 0xFC, fontScale: 1))
        #expect(h1.first?.columns == 10 && h1.first?.rows == 2)
        #expect(laidOut.rows[0].fill?.style.background == MarkdownTheme.dark.headingBar)
        #expect(laidOut.rows[0].anchor == "title")
        let h2Row = try! #require(laidOut.rows.firstIndex { $0.image?.content == .heading(text: "Sub", red: 0x44, green: 0x93, blue: 0xF8, fontScale: 0.75) })
        #expect(rowText(laidOut.rows[h2Row + 2]).contains("───"))
        #expect(laidOut.outline.map(\.title) == ["Title", "Sub"])
        let selection = TextSelection(anchor: TextPoint(line: 0, column: 0), head: TextPoint(line: h2Row + 1, column: 40))
        #expect(SelectionText.markdownText(selection, rows: laidOut.rows) == "Title\n\nSub")
    }

    @Test("支持放大文字（kitty）时标题仍用放大文字，不画成图")
    func scaledHeadingsWin() {
        let context = MarkdownImageContext(cell: cell, baseDirectory: base, headingImages: true)
        let laidOut = MarkdownLayout.render("# Title", width: 44, theme: .dark, scaledHeadings: true, images: context)
        #expect(laidOut.rows.allSatisfy { $0.image == nil })
        #expect(laidOut.rows.first?.scaledHeading != nil)
    }

    @Test("标题图：PNG 尺寸是格数乘格子像素，字画上了")
    func headingPNGDrawsText() throws {
        let image = TerminalImage(content: .heading(text: "Title 标题", red: 0x1F, green: 0x23, blue: 0x28, fontScale: 1), columns: 20, rows: 2, cell: PixelSize(width: 14, height: 25))
        let png = try #require(ImageRasterizer.png(for: image))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 280 && decoded.height == 50)
        let pixels = try #require(decoded.dataProvider?.data as Data?)
        #expect(pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 })
    }

    @Test("能显示图片时：终端不支持放大文字就把标题画成图，支持放大文字就不画")
    func headingImagesFollowTextSizing() {
        var state = TUIState(size: TerminalSize(columns: 60, rows: 20), document: .loading(path: "a.md"))
        state.terminalName = "ghostty 1.3.1"
        state.cellPixelSize = cell
        state.graphicsReady = true
        let document = OpenedDocument(header: DocumentHeader(displayPath: "a.md", details: ""), store: LineStore("# T"), presentation: .markdown, baseDirectory: base)
        #expect(TUIReducer.imageContext(state, document: document)?.headingImages == true)
        state.supportsTextSizing = true
        #expect(TUIReducer.imageContext(state, document: document)?.headingImages == false)
    }
}
