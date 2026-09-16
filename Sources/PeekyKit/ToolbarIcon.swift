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
///
/// 形状逐条照 Lucide 的原始 SVG path 转写（`align-left` / `tag` / `folder` / `list-tree`），
/// 笔间距则按 `lineWidth` 重排过：这个尺寸下决定清晰度的不是线粗，是两笔之间还剩多少缝。
/// 闸门是任意两块墨迹之间 ≥ 4.0 px@2x——低于这个数，Retina 上两笔会连成一块。
enum ToolbarIcon {
    /// 复制文件内容：一段正文，三行、行长递减。正文本身就是被复制的东西。
    case content
    /// 复制文件名：一枚行李牌，牌面上一个孔。
    case name
    /// 复制绝对路径：一条竖脊带一级缩进，顶行顶到最左——从根起算。
    case fullPath
    /// 复制相对路径：同一条脊，顶行换成省略号——前半截被截掉，从中途起算。
    case relPath
    /// 在访达里显示：文件夹。
    case revealInFinder
    /// 更多：三点。
    case more

    /// 几何写在这个方格里（左下为原点）。数值只需彼此协调，绝对尺寸由 `render` 统一给。
    static let grid: CGFloat = 24
    /// 六颗共用的墨迹外接框长边。
    static let inkSide: CGFloat = 15
    /// 最终 pt 上的描边粗细。`render` 会把它换算进被缩放过的坐标系。
    static let lineWidth: CGFloat = 2.35
    /// 画布。宽 24 与按钮 34pt 的宽度下限相容；高给墨迹上下各留 1pt。
    static let box = NSSize(width: 24, height: 17)

    /// 模板图，由按钮的 `contentTintColor` 上色，与同一颗按钮的文字同色。
    var image: NSImage {
        Self.render(strokes)
    }

    // MARK: - 六颗的几何

    private var strokes: [Stroke] {
        switch self {
        case .content:
            // 行距 7 格，是全套最宽裕的一处。
            return [
                .line(3, 19, 21, 19),
                .line(3, 12, 15, 12),
                .line(3, 5, 17, 5)
            ]

        case .name:
            // 孔往牌面内侧收，让它与斜边、圆角三面都留出缝——这一颗是全套唯一三面受夹的结构，
            // 也因此是线一粗最先糊掉的那颗。
            return [
                .polygon(Self.tagCorners, cornerRadius: 2),
                .dot(8.7, 15.3, 1.2)
            ]

        case .fullPath:
            return [
                .line(2.6, 19.9, 21.4, 19.9),
                .polyline([(5.4, 13.0), (5.4, 4.5), (21.4, 4.5)], cornerRadius: 2.6)
            ]

        case .relPath:
            // 与 fullPath 共用同一条脊，只有顶行不同：要读的正好是「从根起算 / 从中途起算」
            // 这一个 bit，就只给它一处可感差异。
            return [
                .dot(3.3, 19.9, 1.55), .dot(10.0, 19.9, 1.55), .dot(16.7, 19.9, 1.55),
                .polyline([(5.4, 13.0), (5.4, 4.5), (21.4, 4.5)], cornerRadius: 2.6)
            ]

        case .revealInFinder:
            return [.polygon(Self.folderCorners, cornerRadius: 2)]

        case .more:
            // 点径随线宽一起长，否则这一颗的墨水面积只有同行其余五颗的四分之一，排在一行里
            // 像没画完。2.91 是让「点径 ÷ 线宽」与其余五颗的观感基准持平的解。
            return [.dot(3, 12, 2.91), .dot(12, 12, 2.91), .dot(21, 12, 2.91)]
        }
    }

    private static let tagCorners: [(CGFloat, CGFloat)] = [(12, 22), (2, 22), (2, 12), (13, 1), (23, 11)]
    /// 缺口 4 格深：线一粗，3 格的落差在轮廓上就快看不出来了。
    private static let folderCorners: [(CGFloat, CGFloat)] = [
        (2, 21.5), (8, 21.5), (11, 17.5), (22, 17.5), (22, 4), (2, 4)
    ]

    // MARK: - 出图

    /// 按墨迹并集的长边缩到 `inkSide`，居中落在 `box` 上。
    private static func render(_ strokes: [Stroke]) -> NSImage {
        let (union, factor, strokeUnits) = fit(strokes)

        let canvas = NSImage(size: box, flipped: false) { _ in
            guard NSGraphicsContext.current != nil else { return true }
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
                stroke.path.lineWidth = strokeUnits
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

    /// 解出「墨迹长边正好 `inkSide`、描边正好 `lineWidth`」这一对互相依赖的量。
    ///
    /// 网格坐标会被缩放，描边宽度因此要先除以缩放系数才设进 `NSBezierPath.lineWidth`；而缩放
    /// 系数取决于墨迹范围、墨迹范围又含半个描边宽。四次迭代即收敛，六颗的描边于是一模一样粗，
    /// 与各自形状的宽高比无关。
    private static func fit(_ strokes: [Stroke]) -> (union: NSRect, factor: CGFloat, strokeUnits: CGFloat) {
        var strokeUnits = lineWidth * grid / inkSide
        var union = inkUnion(strokes, strokeUnits: strokeUnits)
        var factor = inkSide / max(union.width, union.height)
        for _ in 0..<4 {
            strokeUnits = lineWidth / factor
            union = inkUnion(strokes, strokeUnits: strokeUnits)
            factor = inkSide / max(union.width, union.height)
        }
        return (union, factor, strokeUnits)
    }

    private static func inkUnion(_ strokes: [Stroke], strokeUnits: CGFloat) -> NSRect {
        var union = NSRect.null
        for stroke in strokes {
            let box = stroke.inkBounds(strokeUnits: strokeUnits)
            union = union.isNull ? box : union.union(box)
        }
        return union.isNull ? NSRect(x: 0, y: 0, width: grid, height: grid) : union
    }
}

/// 图标里的一笔。
private struct Stroke {
    enum Style { case stroke, fill }

    let path: NSBezierPath
    let style: Style

    /// 这一笔占掉的墨迹范围——描边往外扩半个线宽，这样六颗按并集缩放时算的是同一件东西。
    func inkBounds(strokeUnits: CGFloat) -> NSRect {
        switch style {
        case .stroke: return path.bounds.insetBy(dx: -strokeUnits / 2, dy: -strokeUnits / 2)
        case .fill: return path.bounds
        }
    }

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Stroke {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x1, y: y1))
        path.line(to: NSPoint(x: x2, y: y2))
        path.lineCapStyle = .round
        return Stroke(path: path, style: .stroke)
    }

    /// 折线，每个拐点倒同一个圆角。
    static func polyline(_ points: [(CGFloat, CGFloat)], cornerRadius: CGFloat) -> Stroke {
        let pts = points.map { NSPoint(x: $0.0, y: $0.1) }
        let path = NSBezierPath()
        path.move(to: pts[0])
        for index in 1..<(pts.count - 1) {
            path.appendArc(from: pts[index], to: pts[index + 1], radius: cornerRadius)
        }
        path.line(to: pts[pts.count - 1])
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return Stroke(path: path, style: .stroke)
    }

    /// 闭合多边形，每个顶点倒同一个圆角。
    static func polygon(_ points: [(CGFloat, CGFloat)], cornerRadius: CGFloat) -> Stroke {
        let pts = points.map { NSPoint(x: $0.0, y: $0.1) }
        let path = NSBezierPath()
        let last = pts[pts.count - 1]
        path.move(to: NSPoint(x: (last.x + pts[0].x) / 2, y: (last.y + pts[0].y) / 2))
        for index in 0..<pts.count {
            path.appendArc(from: pts[index], to: pts[(index + 1) % pts.count], radius: cornerRadius)
        }
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
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
}
