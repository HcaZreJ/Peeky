import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// 读本地图片的像素尺寸、把要显示的图画成 PNG。只用 ImageIO / CoreGraphics / CoreText（不依赖 AppKit），在后台调用。
enum ImageRasterizer {
    /// 图片按 EXIF 方向转正后的像素尺寸；读不了或不是位图（如 SVG）时为 nil。
    static func pixelSize(ofImageAt path: String) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // 方向 5–8 是转了 90° 的
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    }

    /// 画成 PNG：图片文件缩到 `image.pixelSize` 以内（不放大，按 EXIF 方向转正）；标题文字画在透明底上。
    static func png(for image: TerminalImage) -> Data? {
        switch image.content {
        case let .file(path):
            return filePNG(path: path, fitting: image.pixelSize)
        case let .heading(text, red, green, blue, fontScale):
            return headingPNG(text: text, color: (red, green, blue), fontScale: fontScale, box: image.pixelSize)
        }
    }

    /// 标题字号是图高的这个比例（再乘 `fontScale`）：两行高里放一行 2 倍大的字。
    static let headingFontRatio = 0.75

    /// 标题文字：系统字体粗体（app 的 Markdown 标题用系统字体），靠左、竖直居中；放不下时缩小到正好放下。
    static func headingPNG(text: String, color: (UInt8, UInt8, UInt8), fontScale: Double, box: PixelSize) -> Data? {
        guard !box.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: box.width, height: box.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let cgColor = CGColor(srgbRed: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255, blue: CGFloat(color.2) / 255, alpha: 1)
        var fontSize = CGFloat(box.height) * headingFontRatio * fontScale
        var line = headingLine(text, size: fontSize, color: cgColor)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        if width > CGFloat(box.width) {
            fontSize *= CGFloat(box.width) / width
            line = headingLine(text, size: fontSize, color: cgColor)
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        }
        context.textPosition = CGPoint(x: 0, y: (CGFloat(box.height) - ascent - descent) / 2 + descent)
        CTLineDraw(line, context)
        return context.makeImage().flatMap(encodePNG)
    }

    private static func headingLine(_ text: String, size: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as [CFString: Any]
        let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        return CTLineCreateWithAttributedString(string ?? CFAttributedStringCreate(nil, "" as CFString, nil))
    }

    private static func filePNG(path: String, fitting box: PixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(box.width, box.height),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodePNG(thumbnail)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
