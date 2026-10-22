import Foundation

/// 像素尺寸。
package struct PixelSize: Equatable, Hashable, Sendable {
    package var width: Int
    package var height: Int

    package init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// 读不出尺寸的图记成 0 × 0，排版时按文字显示。
    package static let unreadable = PixelSize(width: 0, height: 0)

    package var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// 终端里显示的一张图（kitty 图片协议的 Unicode 占位符方式）：占 `columns × rows` 格。内容是本地
/// 图片文件，或画成图的标题文字；编号由内容、格数与格子像素尺寸决定，同样的图总是同一个编号。
package struct TerminalImage: Equatable, Hashable, Sendable {
    package enum Content: Equatable, Hashable, Sendable {
        case file(path: String)
        /// 粗体标题文字；`fontScale` 是字号相对两行高的比例（H2 比 H1 小）
        case heading(text: String, red: UInt8, green: UInt8, blue: UInt8, fontScale: Double)
    }

    package let content: Content
    package let columns: Int
    package let rows: Int
    /// 一格的像素尺寸：按它把图画成 `columns × rows` 格大小
    package let cell: PixelSize
    package let id: UInt32

    package init(content: Content, columns: Int, rows: Int, cell: PixelSize) {
        self.content = content
        self.columns = min(max(columns, 1), ImagePlaceholder.maximumCells)
        self.rows = min(max(rows, 1), ImagePlaceholder.maximumCells)
        self.cell = cell
        self.id = Self.makeID(content: content, columns: self.columns, rows: self.rows, cell: cell)
    }

    /// 图片要画成的像素尺寸。
    package var pixelSize: PixelSize {
        PixelSize(width: columns * cell.width, height: rows * cell.height)
    }

    /// 内容、格数、格子尺寸的 FNV-1a 散列取低 24 位（编号写在前景色里，只有 24 位），不取 0。
    static func makeID(content: Content, columns: Int, rows: Int, cell: PixelSize) -> UInt32 {
        let key: String
        switch content {
        case let .file(path):
            key = "file:\(path)"
        case let .heading(text, red, green, blue, fontScale):
            key = "heading:\(text):\(red),\(green),\(blue):\(fontScale)"
        }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(key)|\(columns)x\(rows)|\(cell.width)x\(cell.height)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let id = UInt32(truncatingIfNeeded: hash ^ (hash >> 24) ^ (hash >> 48)) & 0x00FF_FFFF
        return id == 0 ? 1 : id
    }
}

/// kitty 图片协议的 Unicode 占位符：每格写 U+10EEEE 加行号、列号两个附加符，前景色是图片编号；
/// 终端在这些格子上画出编号对应的图。占位符就是普通文字，滚动、差异输出、清屏都照常。
package enum ImagePlaceholder {
    static let character: Unicode.Scalar = "\u{10EEEE}"
    /// 行数、列数的上限（附加符只有这么多个）。
    package static let maximumCells = ImagePlaceholderDiacritics.codePoints.count
    /// 每块 base64 的字节数（协议规定不超过 4096）。
    static let chunkSize = 4096

    /// 第 `row` 行的占位文字：`columns` 格，每格带齐行号与列号（横向截断时终端也认得出是哪一块）。
    package static func rowText(row: Int, columns: Int) -> String {
        let rowMark = diacritic(row)
        var scalars = String.UnicodeScalarView()
        for column in 0..<columns {
            scalars.append(character)
            scalars.append(rowMark)
            scalars.append(diacritic(column))
        }
        return String(scalars)
    }

    private static func diacritic(_ index: Int) -> Unicode.Scalar {
        let codePoints = ImagePlaceholderDiacritics.codePoints
        return Unicode.Scalar(codePoints[min(max(index, 0), codePoints.count - 1)]) ?? "\u{0305}"
    }

    /// 图片编号写成的前景色（24 位真彩）。
    package static func color(for id: UInt32) -> TerminalColor {
        .rgb(UInt8((id >> 16) & 0xFF), UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF))
    }

    /// 传一张 PNG 并为它建一个 `columns × rows` 格的虚拟放置；静默（`q=2`，终端不回复）。
    package static func transmission(id: UInt32, png: Data, columns: Int, rows: Int) -> String {
        let payload = png.base64EncodedString()
        var output = ""
        var start = payload.startIndex
        var isFirst = true
        repeat {
            let end = payload.index(start, offsetBy: chunkSize, limitedBy: payload.endIndex) ?? payload.endIndex
            let more = end < payload.endIndex ? 1 : 0
            let keys = isFirst ? "a=T,U=1,i=\(id),f=100,c=\(columns),r=\(rows),q=2,m=\(more)" : "m=\(more)"
            output += "\u{1B}_G\(keys);\(payload[start..<end])\u{1B}\\"
            start = end
            isFirst = false
        } while start < payload.endIndex
        return output
    }

    /// 删掉这张图（含虚拟放置）并释放数据。
    package static func deletion(id: UInt32) -> String {
        "\u{1B}_Ga=d,d=I,i=\(id),q=2\u{1B}\\"
    }
}
