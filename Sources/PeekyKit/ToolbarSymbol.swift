import AppKit

/// 顶栏动作按钮的符号图像。
///
/// SF Symbol 各自的自然高度差得很远：13pt 下 `doc.on.doc` 高 18、`ellipsis` 只有 5。
/// `NSButton` 的 `.imageAbove` 把「图标 + 文字」整块垂直居中，图标一矮整块跟着变矮、
/// 文字就往上跑，一排按钮的文字因此参差不齐。把每个符号画进同一尺寸的画布，每颗按钮的
/// 堆叠高度完全一致，图标落在同一条水平带上、文字落在同一条基线上。
enum ToolbarSymbol {
    /// 容得下顶栏这组符号在 13pt 下的最大尺寸（`textformat.abc` 宽 25、`doc.on.doc` 高 18）。
    static let box = NSSize(width: 26, height: 18)

    /// 画布用 `NSImage(size:flipped:drawingHandler:)` 生成，每个缩放倍率各自重画一遍，
    /// Retina 下不糊。符号名不存在时返回 nil——调用方据此发现名字写错了。
    static func uniform(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                )
        else {
            return nil
        }

        let size = symbol.size
        let canvas = NSImage(size: box, flipped: false) { _ in
            symbol.draw(in: NSRect(
                x: ((Self.box.width - size.width) / 2).rounded(),
                y: ((Self.box.height - size.height) / 2).rounded(),
                width: size.width,
                height: size.height
            ))
            return true
        }
        // 模板图由 contentTintColor 上色，与同一颗按钮的文字同色。
        canvas.isTemplate = true
        return canvas
    }
}
