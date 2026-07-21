import Foundation

/// 折叠态合成结果：可见文本 + 可见↔源双向坐标映射。
struct FoldComposition: Equatable, Sendable {
    /// 可见/源坐标的单调映射段。恒等段 visibleRange.length == sourceRange.length；
    /// chip 段 visibleRange.length == 1（U+FFFC）对应 sourceRange = 被折叠区的
    /// innerCharRange。段按位置升序、互不重叠、联合覆盖全部可见文本。
    struct Segment: Equatable, Sendable {
        let visibleRange: NSRange
        let sourceRange: NSRange

        init(visibleRange: NSRange, sourceRange: NSRange) {
            self.visibleRange = visibleRange
            self.sourceRange = sourceRange
        }
    }

    /// 折叠区内容替换为单字符占位 U+FFFC（OBJECT REPLACEMENT CHARACTER）后的文本。
    /// 无折叠时与源文本逐字符相等。
    let visibleText: String
    /// 每个 U+FFFC 占位在 visibleText 中的 UTF-16 范围（长度恒为 1），升序。
    let chipRanges: [NSRange]
    /// 可见行号（0-based）→ 源行号（0-based）。折叠行映射到其 openLine；
    /// 折叠区之后的可见行跳号到 closeLine 之后（如 12 折叠后下一可见行是源 181 行）。
    let visibleLineToSourceLine: [Int]
    /// 每可见行的缩进深度（取该行对应源行的深度）。
    let visibleLineDepths: [Int]
    let segments: [Segment]

    init(
        visibleText: String,
        chipRanges: [NSRange],
        visibleLineToSourceLine: [Int],
        visibleLineDepths: [Int],
        segments: [Segment]
    ) {
        self.visibleText = visibleText
        self.chipRanges = chipRanges
        self.visibleLineToSourceLine = visibleLineToSourceLine
        self.visibleLineDepths = visibleLineDepths
        self.segments = segments
    }
}

/// 折叠态文本合成（纯函数）：源 pretty 文本 + 折叠索引 + 已折叠区集合 → 可见文本
/// 与双向坐标映射。
///
/// 折叠一个区域 = 把它的 innerCharRange（含换行缩进）整体替换为一个 U+FFFC，
/// 因此折叠区在可见文本中呈现为单行：openLine 前缀 + 开括号 + U+FFFC + 闭括号
/// + closeLine 括号后的剩余内容（如逗号）。嵌套折叠时外层吞并内层（内层 id 是否
/// 在 collapsed 中都一样）；collapsed 中不存在于 foldMap 的 id 忽略。collapsed
/// 为空时输出与源文本恒等（映射为单一恒等段）。
enum JSONFoldComposer {
    static func compose(
        sourceText: String,
        foldMap: JSONFoldMap,
        collapsed: Set<Int>
    ) -> FoldComposition {
        _ = foldMap
        _ = collapsed
        return FoldComposition(
            visibleText: sourceText,
            chipRanges: [],
            visibleLineToSourceLine: [],
            visibleLineDepths: [],
            segments: []
        )
    }

    /// 可见坐标范围 → 源坐标范围。与 chip 段有交集时，交集部分展开为该 chip 的
    /// 完整源范围（复制含折叠 chip 的选区得到完整底层 JSON 的依据）。
    static func sourceRange(forVisible range: NSRange, in composition: FoldComposition) -> NSRange {
        _ = composition
        return range
    }

    /// 源坐标范围 → 可见坐标范围。完全落在某个被折叠区内容中时返回该 chip 的
    /// 可见范围（长度 1）；部分重叠时返回覆盖全部重叠内容的最小可见范围；
    /// 源范围越界（超出全部段覆盖）时返回 nil。
    static func visibleRange(forSource range: NSRange, in composition: FoldComposition) -> NSRange? {
        _ = composition
        return range
    }
}
