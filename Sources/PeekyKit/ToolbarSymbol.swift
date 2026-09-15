import AppKit

/// 顶栏动作按钮的符号图像：墨迹归一到同一高度，落在同一块画布的正中。
///
/// SF Symbol 是按「跟文字排在一起、坐在同一条文字基线上」设计的，不是按「填满一个图标框」
/// 设计的，所以同一点数下各符号的**墨迹**高度天生就不一样（13pt 下 `doc.on.doc` 墨高 16、
/// `folder` 12、`ellipsis` 只有 3）。把符号按原尺寸摆进统一画布，画布是齐的，图标看上去
/// 依然一颗高一颗矮、有的填满有的只占中间一条。
///
/// 这里量出每个符号的墨迹外接框，按墨高缩放到 `inkHeight`，再把墨迹摆到画布正中——六颗
/// 于是等高，且各自填满画布的竖直方向。宽度随符号自身的宽高比走：宽高比差得太远的字形
/// （`ellipsis` 4:1、`textformat.abc` 2:1）等高之后会横着撑出去，那类字形不进这排按钮。
enum ToolbarSymbol {
    /// 画布尺寸。宽度容得下宽高比 1.3 的符号等高之后的墨宽（14 × 1.3 ≈ 18.2）再加余量。
    static let box = NSSize(width: 24, height: 16)

    /// 六颗共用的墨迹高度。
    static let inkHeight: CGFloat = 14

    /// 符号名不存在时返回 nil——调用方据此发现名字写错了。
    static func uniform(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                ),
            let ink = inkBounds(of: symbol)
        else {
            return nil
        }

        // 等高优先；等高之后横向撑出画布的，退回按宽度收。
        let scale = min(inkHeight / ink.height, box.width / ink.width)
        let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        // 把墨迹（而不是含留白的整张图）摆到画布正中。
        let origin = NSPoint(
            x: (box.width - ink.width * scale) / 2 - ink.minX * scale,
            y: (box.height - ink.height * scale) / 2 - ink.minY * scale
        )

        let canvas = NSImage(size: box, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: origin, size: drawn))
            return true
        }
        // 模板图由 contentTintColor 上色，与同一颗按钮的文字同色。
        canvas.isTemplate = true
        return canvas
    }

    /// 符号墨迹的外接框，坐标与 `NSImage` 一致（左下为原点）。整张图透明时返回 nil。
    ///
    /// 超采样 4 倍再扫 alpha：SF Symbol 的描边末端是亚像素的，按 1 倍扫会把末端算丢，
    /// 六颗的缩放系数跟着差一点点，等高就等不准。
    private static func inkBounds(of symbol: NSImage) -> (minX: CGFloat, minY: CGFloat, width: CGFloat, height: CGFloat)? {
        let sample: CGFloat = 4
        let pixelsWide = Int((symbol.size.width * sample).rounded(.up))
        let pixelsHigh = Int((symbol.size.height * sample).rounded(.up))
        guard
            pixelsWide > 0, pixelsHigh > 0,
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        symbol.draw(in: NSRect(origin: .zero, size: NSSize(width: pixelsWide, height: pixelsHigh)))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixelsWide, maxX = -1, minRow = pixelsHigh, maxRow = -1
        for row in 0..<pixelsHigh {
            for column in 0..<pixelsWide where (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.08 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }

        // 位图行号自上而下，NSImage 的 y 自下而上。
        return (
            minX: CGFloat(minX) / sample,
            minY: CGFloat(pixelsHigh - 1 - maxRow) / sample,
            width: CGFloat(maxX - minX + 1) / sample,
            height: CGFloat(maxRow - minRow + 1) / sample
        )
    }
}
