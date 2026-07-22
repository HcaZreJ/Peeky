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
        let effective = effectiveRegions(foldMap: foldMap, collapsed: collapsed)
        let ns = sourceText as NSString
        let totalLength = ns.length

        guard !effective.isEmpty else {
            let lineCount = foldMap.lineDepths.count
            return FoldComposition(
                visibleText: sourceText,
                chipRanges: [],
                visibleLineToSourceLine: Array(0..<lineCount),
                visibleLineDepths: foldMap.lineDepths,
                segments: [
                    FoldComposition.Segment(
                        visibleRange: NSRange(location: 0, length: totalLength),
                        sourceRange: NSRange(location: 0, length: totalLength)
                    )
                ]
            )
        }

        var visibleText = ""
        var chipRanges: [NSRange] = []
        var segments: [FoldComposition.Segment] = []
        var sourceCursor = 0
        var visibleCursor = 0

        for region in effective {
            let innerRange = region.innerCharRange
            if innerRange.location > sourceCursor {
                let prefixLength = innerRange.location - sourceCursor
                visibleText += ns.substring(with: NSRange(location: sourceCursor, length: prefixLength))
                segments.append(FoldComposition.Segment(
                    visibleRange: NSRange(location: visibleCursor, length: prefixLength),
                    sourceRange: NSRange(location: sourceCursor, length: prefixLength)
                ))
                visibleCursor += prefixLength
            }

            visibleText += "\u{FFFC}"
            let chipRange = NSRange(location: visibleCursor, length: 1)
            chipRanges.append(chipRange)
            segments.append(FoldComposition.Segment(visibleRange: chipRange, sourceRange: innerRange))
            visibleCursor += 1
            sourceCursor = innerRange.location + innerRange.length
        }

        if sourceCursor < totalLength {
            let suffixLength = totalLength - sourceCursor
            visibleText += ns.substring(with: NSRange(location: sourceCursor, length: suffixLength))
            segments.append(FoldComposition.Segment(
                visibleRange: NSRange(location: visibleCursor, length: suffixLength),
                sourceRange: NSRange(location: sourceCursor, length: suffixLength)
            ))
        }

        let lineCount = foldMap.lineDepths.count
        var visibleLineToSourceLine: [Int] = []
        var visibleLineDepths: [Int] = []
        var line = 0
        var regionIndex = 0
        while line < lineCount {
            visibleLineToSourceLine.append(line)
            visibleLineDepths.append(foldMap.lineDepths[line])
            if regionIndex < effective.count && effective[regionIndex].openLine == line {
                line = effective[regionIndex].closeLine + 1
                regionIndex += 1
            } else {
                line += 1
            }
        }

        return FoldComposition(
            visibleText: visibleText,
            chipRanges: chipRanges,
            visibleLineToSourceLine: visibleLineToSourceLine,
            visibleLineDepths: visibleLineDepths,
            segments: segments
        )
    }

    /// 可见坐标范围 → 源坐标范围。与 chip 段有交集时，交集部分展开为该 chip 的
    /// 完整源范围（复制含折叠 chip 的选区得到完整底层 JSON 的依据）。
    static func sourceRange(forVisible range: NSRange, in composition: FoldComposition) -> NSRange {
        let segments = composition.segments
        guard !segments.isEmpty else { return range }

        let queryStart = range.location
        let queryEnd = range.location + range.length

        if range.length == 0 {
            let position = mappedPosition(
                forOffset: queryStart,
                segments: segments,
                segmentRange: { $0.visibleRange },
                mappedRange: { $0.sourceRange }
            )
            return NSRange(location: position, length: 0)
        }

        var resultStart: Int?
        var resultEnd = 0

        for segment in segments {
            let segStart = segment.visibleRange.location
            let segEnd = segStart + segment.visibleRange.length
            guard segStart < queryEnd && queryStart < segEnd else { continue }

            let contributionStart: Int
            let contributionEnd: Int
            if isIdentitySegment(segment) {
                let lowOffset = max(queryStart, segStart) - segStart
                let highOffset = min(queryEnd, segEnd) - segStart
                contributionStart = segment.sourceRange.location + lowOffset
                contributionEnd = segment.sourceRange.location + highOffset
            } else {
                contributionStart = segment.sourceRange.location
                contributionEnd = segment.sourceRange.location + segment.sourceRange.length
            }

            if resultStart == nil {
                resultStart = contributionStart
            }
            resultEnd = contributionEnd
        }

        guard let start = resultStart else { return NSRange(location: queryStart, length: 0) }
        return NSRange(location: start, length: resultEnd - start)
    }

    /// 源坐标范围 → 可见坐标范围。完全落在某个被折叠区内容中时返回该 chip 的
    /// 可见范围（长度 1）；部分重叠时返回覆盖全部重叠内容的最小可见范围；
    /// 源范围越界（超出全部段覆盖）时返回 nil。
    static func visibleRange(forSource range: NSRange, in composition: FoldComposition) -> NSRange? {
        let segments = composition.segments
        guard !segments.isEmpty else { return nil }

        let coverageStart = segments[0].sourceRange.location
        let lastSegment = segments[segments.count - 1]
        let coverageEnd = lastSegment.sourceRange.location + lastSegment.sourceRange.length

        let queryStart = range.location
        let queryEnd = range.location + range.length

        guard queryStart >= coverageStart, queryEnd <= coverageEnd else { return nil }

        if range.length == 0 {
            let position = mappedPosition(
                forOffset: queryStart,
                segments: segments,
                segmentRange: { $0.sourceRange },
                mappedRange: { $0.visibleRange }
            )
            return NSRange(location: position, length: 0)
        }

        var resultStart: Int?
        var resultEnd = 0

        for segment in segments {
            let segStart = segment.sourceRange.location
            let segEnd = segStart + segment.sourceRange.length
            guard segStart < queryEnd && queryStart < segEnd else { continue }

            let contributionStart: Int
            let contributionEnd: Int
            if isIdentitySegment(segment) {
                let lowOffset = max(queryStart, segStart) - segStart
                let highOffset = min(queryEnd, segEnd) - segStart
                contributionStart = segment.visibleRange.location + lowOffset
                contributionEnd = segment.visibleRange.location + highOffset
            } else {
                contributionStart = segment.visibleRange.location
                contributionEnd = segment.visibleRange.location + segment.visibleRange.length
            }

            if resultStart == nil {
                resultStart = contributionStart
            }
            resultEnd = contributionEnd
        }

        guard let start = resultStart else { return nil }
        return NSRange(location: start, length: resultEnd - start)
    }

    /// 折叠生效集：collapsed 中存在于 foldMap 的区域，按行区间互不包含关系
    /// 收敛到最外层（嵌套区域被外层吞并，不论其 id 是否也在 collapsed 中）。
    private static func effectiveRegions(foldMap: JSONFoldMap, collapsed: Set<Int>) -> [FoldRegion] {
        let candidates = foldMap.regions.filter { collapsed.contains($0.id) }
        guard !candidates.isEmpty else { return [] }
        return candidates.filter { candidate in
            !candidates.contains { other in
                other.id != candidate.id
                    && other.openLine <= candidate.openLine
                    && candidate.closeLine <= other.closeLine
            }
        }
    }

    /// 段是否为恒等段（两侧长度相等）；chip 段 visibleRange.length == 1 且
    /// sourceRange 覆盖被折叠区的完整 innerCharRange，两侧长度不等。
    private static func isIdentitySegment(_ segment: FoldComposition.Segment) -> Bool {
        segment.visibleRange.length == segment.sourceRange.length
    }

    /// 零长度坐标（光标）在两套坐标系间的映射：落在恒等段内按偏移量平移；
    /// 落在 chip 段的范围内（含边界）时，起点侧映射到 chip 对侧范围的起点，
    /// 终点侧映射到 chip 对侧范围的终点（与相邻段在边界处的映射值天然一致，
    /// 因为全部段在两套坐标系中都连续衔接、无缝隙）。
    private static func mappedPosition(
        forOffset offset: Int,
        segments: [FoldComposition.Segment],
        segmentRange: (FoldComposition.Segment) -> NSRange,
        mappedRange: (FoldComposition.Segment) -> NSRange
    ) -> Int {
        for segment in segments {
            let range = segmentRange(segment)
            let segStart = range.location
            let segEnd = segStart + range.length
            guard offset >= segStart && offset <= segEnd else { continue }

            let target = mappedRange(segment)
            if isIdentitySegment(segment) {
                return target.location + (offset - segStart)
            }
            return offset < segEnd ? target.location : target.location + target.length
        }
        if let last = segments.last {
            let target = mappedRange(last)
            return target.location + target.length
        }
        return offset
    }
}
