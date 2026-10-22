/// 终端颜色：默认色（跟随终端主题）或 24 位真彩。
package enum TerminalColor: Equatable, Sendable {
    case `default`
    case rgb(UInt8, UInt8, UInt8)
}

/// 一格的样式。`link` 非 nil 时该格属于一个 OSC 8 超链接。
package struct CellStyle: Equatable, Sendable {
    package var foreground: TerminalColor
    package var background: TerminalColor
    package var bold: Bool
    package var dim: Bool
    package var italic: Bool
    package var underline: Bool
    package var strikethrough: Bool
    package var inverse: Bool
    package var link: String?

    package init(
        foreground: TerminalColor = .default,
        background: TerminalColor = .default,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        inverse: Bool = false,
        link: String? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverse = inverse
        self.link = link
    }

    package static let plain = CellStyle()
}

/// kitty 文字尺寸协议（OSC 66）的放大规格：`scale` 倍的格子（每个字占 `scale × 字宽` 列、`scale` 行），
/// 字号再乘 `numerator / denominator`；`verticalAlignment` 为 2 时字在格子里竖直居中。
package struct ScaleSpec: Equatable, Sendable {
    package let scale: Int
    package let numerator: Int
    package let denominator: Int
    package let verticalAlignment: Int?

    /// H1：2 倍字。
    package static let h1 = ScaleSpec(scale: 2, numerator: 1, denominator: 1, verticalAlignment: nil)
    /// H2：2 倍格子里 3/4 的字号（约 1.5 倍），竖直居中。
    package static let h2 = ScaleSpec(scale: 2, numerator: 3, denominator: 4, verticalAlignment: 2)

    /// OSC 66 的元数据段，如 `s=2` 或 `s=2:n=3:d=4:v=2`。
    package var metadata: String {
        var parts = ["s=\(scale)"]
        if numerator != denominator {
            parts += ["n=\(numerator)", "d=\(denominator)"]
        }
        if let verticalAlignment { parts.append("v=\(verticalAlignment)") }
        return parts.joined(separator: ":")
    }
}

/// 一段放大文字：整块从它所在的格子开始，占 `columns × rows` 个格子。
package struct ScaledText: Equatable, Sendable {
    package let text: String
    package let spec: ScaleSpec

    package init(text: String, spec: ScaleSpec) {
        self.text = text
        self.spec = spec
    }

    package var columns: Int { TextWidth.width(of: text) * spec.scale }
    package var rows: Int { spec.scale }
}

/// 一格内容。宽字符占两格：首格 `width == 2`，第二格是续格（`width == 0`、`text` 为空）。
/// 放大文字的块：左上格带 `scaled`（`text` 为整段文字），块里其余格子是 `isCovered` 的续格。
package struct Cell: Equatable, Sendable {
    package var text: String
    package var width: Int
    package var style: CellStyle
    package var scaled: ScaledText?
    package var isCovered: Bool

    package init(text: String, width: Int, style: CellStyle, scaled: ScaledText? = nil, isCovered: Bool = false) {
        self.text = text
        self.width = width
        self.style = style
        self.scaled = scaled
        self.isCovered = isCovered
    }

    package static let blank = Cell(text: " ", width: 1, style: .plain)

    package var isContinuation: Bool { width == 0 }

    /// 这一格属于放大文字的块（左上格或被覆盖的格子）。
    package var isScaledBlock: Bool { scaled != nil || isCovered }
}

/// 一帧屏幕内容：`rows × columns` 的格子网格，行优先存储。
package struct CellBuffer: Equatable, Sendable {
    package let columns: Int
    package let rows: Int
    package private(set) var cells: [Cell]
    /// 这一帧里出现的图（占位符所指的图）：运行时据此把还没传过的图传给终端
    package var images: [TerminalImage] = []

    package init(columns: Int, rows: Int) {
        self.columns = max(columns, 0)
        self.rows = max(rows, 0)
        self.cells = Array(repeating: .blank, count: self.columns * self.rows)
    }

    package subscript(row: Int, column: Int) -> Cell {
        guard contains(row: row, column: column) else { return .blank }
        return cells[row * columns + column]
    }

    /// 从 `(row, column)` 起写入文本，写到 `limit`（不含，缺省为行宽）为止；返回写完后的下一列。
    /// 零宽字形簇（控制字符等）直接跳过；宽字符放不下时在剩下那一格写空格并停止。
    @discardableResult
    package mutating func write(_ text: String, row: Int, column: Int, style: CellStyle, limit: Int? = nil) -> Int {
        guard row >= 0, row < rows else { return column }
        let end = min(limit ?? columns, columns)
        var cursor = max(column, 0)
        for character in text {
            let width = TextWidth.width(of: character)
            guard width > 0 else { continue }
            guard cursor + width <= end else {
                if cursor < end {
                    setCell(Cell(text: " ", width: 1, style: style), row: row, column: cursor)
                    cursor += 1
                }
                break
            }
            setCell(Cell(text: String(character), width: width, style: style), row: row, column: cursor)
            if width == 2 {
                setCell(Cell(text: "", width: 0, style: style), row: row, column: cursor + 1)
            }
            cursor += width
        }
        return cursor
    }

    /// 把 `[from, to)` 这一段格子填成带样式的空格。
    package mutating func fill(row: Int, from: Int, to: Int, style: CellStyle) {
        guard row >= 0, row < rows else { return }
        for column in max(from, 0)..<max(min(to, columns), max(from, 0)) {
            setCell(Cell(text: " ", width: 1, style: style), row: row, column: column)
        }
    }

    /// 从 `(row, column)` 起写一块放大文字；块超出缓冲区时不写并返回 false。
    @discardableResult
    package mutating func writeScaled(_ scaled: ScaledText, row: Int, column: Int, style: CellStyle) -> Bool {
        guard row >= 0, column >= 0, row + scaled.rows <= rows, column + scaled.columns <= columns, scaled.columns > 0 else {
            return false
        }
        for coveredRow in row..<(row + scaled.rows) {
            for coveredColumn in column..<(column + scaled.columns) {
                cells[coveredRow * columns + coveredColumn] = Cell(text: "", width: 0, style: style, isCovered: true)
            }
        }
        cells[row * columns + column] = Cell(text: scaled.text, width: 1, style: style, scaled: scaled)
        return true
    }

    /// 把 `[from, to)` 这一段格子的底色换成 `color`，文字不变。
    package mutating func setBackground(row: Int, from: Int, to: Int, color: TerminalColor) {
        guard row >= 0, row < rows else { return }
        for column in max(from, 0)..<max(min(to, columns), max(from, 0)) {
            cells[row * columns + column].style.background = color
        }
    }

    /// 把 `other` 的 `rowRange` 这几行贴到本缓冲区的同一行、从第 `column` 列起，超出右边界的部分丢掉。
    package mutating func paste(_ other: CellBuffer, rows rowRange: Range<Int>, atColumn column: Int) {
        for row in rowRange where row >= 0 && row < min(rows, other.rows) {
            for sourceColumn in 0..<min(other.columns, max(columns - column, 0)) {
                setCell(other[row, sourceColumn], row: row, column: column + sourceColumn)
            }
        }
    }

    /// 一行的可见文字（续格跳过），用于测试与纯文本输出。
    package func rowText(_ row: Int) -> String {
        guard row >= 0, row < rows else { return "" }
        return (0..<columns).map { self[row, $0] }.filter { !$0.isContinuation }.map(\.text).joined()
    }

    private func contains(row: Int, column: Int) -> Bool {
        row >= 0 && row < rows && column >= 0 && column < columns
    }

    /// 写一格；被覆盖掉一半的宽字符，另一半改成空格，避免留下半个字。
    private mutating func setCell(_ cell: Cell, row: Int, column: Int) {
        guard contains(row: row, column: column) else { return }
        let index = row * columns + column
        let old = cells[index]
        if old.isContinuation, column > 0, cell.width != 0 {
            cells[index - 1] = Cell(text: " ", width: 1, style: cells[index - 1].style)
        }
        if old.width == 2, cell.width != 2, column + 1 < columns {
            cells[index + 1] = Cell(text: " ", width: 1, style: old.style)
        }
        cells[index] = cell
    }
}
