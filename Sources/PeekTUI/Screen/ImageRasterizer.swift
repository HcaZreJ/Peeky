import CoreGraphics
import Foundation
import ImageIO

/// 读本地图片的像素尺寸、把要显示的图画成 PNG。只用 ImageIO / CoreGraphics（不依赖 AppKit），在后台调用。
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

    /// 画成 PNG：图片文件缩到 `image.pixelSize` 以内（不放大，按 EXIF 方向转正）。
    static func png(for image: TerminalImage) -> Data? {
        switch image.content {
        case let .file(path):
            return filePNG(path: path, fitting: image.pixelSize)
        case .heading:
            return nil
        }
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
