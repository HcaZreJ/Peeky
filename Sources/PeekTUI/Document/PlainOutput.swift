import Foundation
import PeekyCore

/// 标准输出不是终端时输出的文字：Markdown 按 80 列排成纯文字（项目符号、表格边框照常显示），
/// 其余按显示规则格式化（JSON / XML 缩进），不带任何转义序列，以换行结尾。
package enum PlainOutput {
    package static let width = 80

    package static func text(for loaded: LoadedText) -> String {
        let prepared = DocumentPreparer.prepare(loaded)
        let text: String
        if prepared.presentation == .markdown {
            text = MarkdownLayout.render(prepared.text, width: width, theme: .dark).rows
                .map { row in
                    row.spans.map(\.text).joined().replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                }
                .joined(separator: "\n")
        } else {
            text = prepared.text
        }
        return text.hasSuffix("\n") ? text : text + "\n"
    }
}
