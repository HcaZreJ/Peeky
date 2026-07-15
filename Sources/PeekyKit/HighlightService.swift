import Foundation

/// 单个高亮 token：文本片段 + 前景色（#rrggbb，小写十六进制）。
struct HighlightedToken: Equatable {
    var text: String
    var colorHex: String
}

/// 一行的 token 序列（token.text 依序拼接 == 该行原文，不含换行符）。
typealias HighlightedLine = [HighlightedToken]

/// 分块产出的连续行区间。
struct HighlightChunk: Equatable {
    /// 0-based 起始行号
    var firstLine: Int
    var lines: [HighlightedLine]
}

/// JSC+Shiki 高亮服务：JSContext 单例 + 后台串行队列。
/// 引擎故障/超预算/未知语言一律返回 nil（调用方纯文本回退），不抛错不崩溃。
final class HighlightService: @unchecked Sendable {
    static let shared = HighlightService()

    /// 高亮预算（UTF-16 code unit 数），超限返回 nil
    static let maxUTF16Length = 1_500_000

    /// 扩展名（小写、不含点）→ shiki language id；不支持返回 nil
    static func language(forExtension ext: String) -> String? {
        nil
    }

    /// 启动预热（eval bundle + 引擎 init + 空 tokenize），幂等，后台执行。
    func warmUp() {
    }

    /// 全量高亮。返回行数与输入行数一致（text 按 \n 切分）。
    func highlight(text: String, language: String) async -> [HighlightedLine]? {
        nil
    }

    /// 分块高亮流：按文档顺序产出（首块小而快，利于首屏上色），
    /// 直至覆盖全文后结束。nil 语义同 highlight。
    func highlightStream(text: String, language: String) -> AsyncStream<HighlightChunk>? {
        nil
    }
}
