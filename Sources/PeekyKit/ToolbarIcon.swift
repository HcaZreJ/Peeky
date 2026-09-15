import AppKit

/// 顶栏六颗动作按钮的图标，画在同一个网格上。
///
/// 现成符号库里凑不出六个尺寸一致、含义又都对的符号：SF Symbol 是按「跟文字排在一起、
/// 坐在同一条文字基线上」设计的，墨迹高度与宽高比各不相同。把它们归一到等高之后，墨宽从
/// 11.5 摊到 23.0（极差 11.5pt）；外接框相等也不等于看着一样大，墨水面积最重的一颗是最轻的
/// 2.44 倍，排成一行时重的那颗先被看见、尺寸差异于是编码了一条不存在的信息。
///
/// 所以六颗改成自绘：各写成一组笔画，渲染时按这组笔画墨迹并集的长边缩到 `inkSide`，再摆进
/// 画布正中——六颗拿到同一个外接框，尺寸一致由几何保证，不靠肉眼判断。
enum ToolbarIcon {
    /// 复制文件内容：一段正文，四行、末行收短。正文本身就是被复制的东西。
    case content
    /// 复制文件名：一枚行李牌。斜 45° 摆，外接框天然是正方形。
    case name
    /// 复制绝对路径：三级一条链，每级挂在上一级下面，最上一级顶到最左——从根起算。
    case fullPath
    /// 复制相对路径：同一条链，最上一级换成省略号——前半截被截掉，从中途起算。
    case relPath
    /// 在访达里显示：文件夹。
    case revealInFinder
    /// 更多：圆里三点。圆的外接框天然是正方形。
    case more

    /// 画布尺寸，与按钮的 13pt 符号槽位一致。
    static let box = NSSize(width: 24, height: 16)
    /// 六颗共用的墨迹外接框长边。
    static let inkSide: CGFloat = 14
    /// 与 13pt regular 的 SF Symbol 描边粗细对齐——顶栏里还有系统控件，两者要同一手感。
    static let lineWidth: CGFloat = 1.3

    /// 模板图，由按钮的 `contentTintColor` 上色，与同一颗按钮的文字同色。
    var image: NSImage {
        Self.render(strokes)
    }

    // MARK: - 六颗的几何
    //
    // 坐标画在一个 14 见方的网格里（左下为原点），最终尺寸由 render 统一缩放，
    // 所以这里的数值只需要彼此协调，不必凑成某个绝对值。

    private var strokes: [Stroke] {
        switch self {
        case .content:
            return [
                .line(0.65, 13.35, 13.35, 13.35),
                .line(0.65, 9.1, 13.35, 9.1),
                .line(0.65, 4.85, 13.35, 4.85),
                .line(0.65, 0.65, 8.4, 0.65)
            ]

        case .name:
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 0, y: 0))
            outline.line(to: NSPoint(x: 3.5, y: 3.4))
            outline.appendArc(from: NSPoint(x: 11.4, y: 3.4), to: NSPoint(x: 11.4, y: -3.4), radius: 2.0)
            outline.appendArc(from: NSPoint(x: 11.4, y: -3.4), to: NSPoint(x: 3.5, y: -3.4), radius: 2.0)
            outline.line(to: NSPoint(x: 3.5, y: -3.4))
            outline.close()
            outline.lineJoinStyle = .round
            let hole = NSBezierPath(ovalIn: NSRect(x: 3.0, y: -1.05, width: 2.1, height: 2.1))
            return Stroke.rotated(
                [Stroke(path: outline, style: .stroke), Stroke(path: hole, style: .stroke)],
                degrees: 45
            )

        case .fullPath:
            return [
                .dot(1.2, 13.0, 1.0), .line(3.1, 13.0, 13.35, 13.0),
                .elbow([(1.2, 11.6), (1.2, 7.0), (3.0, 7.0)]),
                .dot(4.4, 7.0, 1.0), .line(6.3, 7.0, 13.35, 7.0),
                .elbow([(4.4, 5.6), (4.4, 1.0), (6.2, 1.0)]),
                .dot(7.6, 1.0, 1.0), .line(9.5, 1.0, 13.35, 1.0)
            ]

        case .relPath:
            return [
                .dot(1.2, 13.0, 0.75), .dot(3.9, 13.0, 0.75), .dot(6.6, 13.0, 0.75),
                .elbow([(1.2, 11.6), (1.2, 7.0), (3.0, 7.0)]),
                .dot(4.4, 7.0, 1.0), .line(6.3, 7.0, 13.35, 7.0),
                .elbow([(4.4, 5.6), (4.4, 1.0), (6.2, 1.0)]),
                .dot(7.6, 1.0, 1.0), .line(9.5, 1.0, 13.35, 1.0)
            ]

        case .revealInFinder:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0.65, y: 3.0))
            path.appendArc(from: NSPoint(x: 0.65, y: 13.35), to: NSPoint(x: 4.6, y: 13.35), radius: 1.9)
            path.appendArc(from: NSPoint(x: 4.6, y: 13.35), to: NSPoint(x: 6.6, y: 10.7), radius: 1.5)
            path.line(to: NSPoint(x: 6.6, y: 10.7))
            path.appendArc(from: NSPoint(x: 13.35, y: 10.7), to: NSPoint(x: 13.35, y: 3.0), radius: 1.9)
            path.appendArc(from: NSPoint(x: 13.35, y: 0.65), to: NSPoint(x: 0.65, y: 0.65), radius: 1.9)
            path.appendArc(from: NSPoint(x: 0.65, y: 0.65), to: NSPoint(x: 0.65, y: 13.35), radius: 1.9)
            path.close()
            path.lineJoinStyle = .round
            return [Stroke(path: path, style: .stroke)]

        case .more:
            return [
                .circle(7.0, 7.0, 6.35),
                .dot(3.5, 7.0, 0.85),
                .dot(7.0, 7.0, 0.85),
                .dot(10.5, 7.0, 0.85)
            ]
        }
    }

    // MARK: - 出图

    /// 按墨迹并集的长边缩到 `inkSide`，居中落在 `box` 上。
    private static func render(_ strokes: [Stroke]) -> NSImage {
        let union = inkUnion(strokes) ?? NSRect(x: 0, y: 0, width: inkSide, height: inkSide)
        let factor = inkSide / max(union.width, union.height)

        let canvas = NSImage(size: box, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return true }
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(
                by: box.width / 2 - union.midX * factor,
                yBy: box.height / 2 - union.midY * factor
            )
            transform.scale(by: factor)
            transform.concat()

            NSColor.black.setStroke()
            NSColor.black.setFill()
            for stroke in strokes {
                stroke.path.lineWidth = lineWidth
                switch stroke.style {
                case .stroke: stroke.path.stroke()
                case .fill: stroke.path.fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        canvas.isTemplate = true
        return canvas
    }

    private static func inkUnion(_ strokes: [Stroke]) -> NSRect? {
        var union = NSRect.null
        for stroke in strokes {
            union = union.isNull ? stroke.inkBounds : union.union(stroke.inkBounds)
        }
        return union.isNull ? nil : union
    }
}

/// 图标里的一笔。
private struct Stroke {
    enum Style { case stroke, fill }

    let path: NSBezierPath
    let style: Style

    /// 这一笔占掉的墨迹范围——描边往外扩半个线宽，这样六颗按并集缩放时算的是同一件东西。
    var inkBounds: NSRect {
        switch style {
        case .stroke:
            return path.bounds.insetBy(dx: -ToolbarIcon.lineWidth / 2, dy: -ToolbarIcon.lineWidth / 2)
        case .fill:
            return path.bounds
        }
    }

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Stroke {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x1, y: y1))
        path.line(to: NSPoint(x: x2, y: y2))
        path.lineCapStyle = .round
        return Stroke(path: path, style: .stroke)
    }

    static func elbow(_ points: [(CGFloat, CGFloat)]) -> Stroke {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].0, y: points[0].1))
        for point in points.dropFirst() {
            path.line(to: NSPoint(x: point.0, y: point.1))
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return Stroke(path: path, style: .stroke)
    }

    static func dot(_ centerX: CGFloat, _ centerY: CGFloat, _ radius: CGFloat) -> Stroke {
        Stroke(
            path: NSBezierPath(ovalIn: NSRect(
                x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2
            )),
            style: .fill
        )
    }

    static func circle(_ centerX: CGFloat, _ centerY: CGFloat, _ radius: CGFloat) -> Stroke {
        Stroke(
            path: NSBezierPath(ovalIn: NSRect(
                x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2
            )),
            style: .stroke
        )
    }

    static func rotated(_ strokes: [Stroke], degrees: CGFloat) -> [Stroke] {
        let transform = NSAffineTransform()
        transform.rotate(byDegrees: degrees)
        return strokes.map { stroke in
            let turned = transform.transform(stroke.path)
            turned.lineCapStyle = stroke.path.lineCapStyle
            turned.lineJoinStyle = stroke.path.lineJoinStyle
            return Stroke(path: turned, style: stroke.style)
        }
    }
}
