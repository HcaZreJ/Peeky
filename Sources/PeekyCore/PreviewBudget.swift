import Foundation

/// 三档性能预算，app 与终端版共用同一组常量；新功能不得绕过。
public enum PreviewBudget {
    /// 文件读取上限：超出只读前缀并标注截断。
    public static let maxPreviewBytes = 80 * 1024 * 1024
    /// 富格式化上限：超出降级为 raw（JSON / JSONL 例外，仍格式化）。
    public static let richFormatLimit = 8 * 1024 * 1024
    /// 语法高亮上限（UTF-16 长度）：超出跳过高亮。
    public static let highlightLimit = 1_500_000
}
