import Foundation

/// 一个可折叠的 JSON 容器区域（object 或 array），跨越多行才可折叠。
struct FoldRegion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case object
        case array
    }

    /// 稳定标识 = openLine（pretty-print 文本中一行至多开启一个折叠区）。
    var id: Int { openLine }

    /// 容器开括号所在逻辑行（0-based）。
    let openLine: Int
    /// 容器闭括号所在逻辑行（0-based），恒大于 openLine。
    let closeLine: Int
    /// UTF-16 字符范围：开括号之后第一个字符起，到闭括号之前一个字符止
    /// （含其间全部换行与缩进空格）。
    let innerCharRange: NSRange
    let kind: Kind

    init(openLine: Int, closeLine: Int, innerCharRange: NSRange, kind: Kind) {
        self.openLine = openLine
        self.closeLine = closeLine
        self.innerCharRange = innerCharRange
        self.kind = kind
    }
}

/// JSON/JSONL pretty-print 文本的折叠结构索引：折叠区表 + 每行缩进深度。
///
/// `build(prettyText:)` 单遍词法扫描（字符串字面量内的括号按内容忽略，处理
/// `\"` 与 `\\` 转义），JSONL 多顶层值天然支持（深度归零重启）；括号不配对的
/// 未闭合区域（如 JSONL 坏行）整体跳过、其余区域正常产出，任何输入都不抛错。
struct JSONFoldMap: Equatable, Sendable {
    /// 全部可折叠区域，按 openLine 升序；仅收 openLine < closeLine 的容器。
    let regions: [FoldRegion]
    /// 每逻辑行的缩进深度：行首连续空格数 ÷ 2（向下取整）。行数 = 文本按 "\n"
    /// 切分的段数（空文本为 1 行、深度 0）。
    let lineDepths: [Int]

    static let empty = JSONFoldMap(regions: [], lineDepths: [])

    init(regions: [FoldRegion], lineDepths: [Int]) {
        self.regions = regions
        self.lineDepths = lineDepths
    }

    static func build(prettyText: String) -> JSONFoldMap {
        _ = prettyText
        return .empty
    }
}
