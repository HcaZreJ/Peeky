import AppKit

/// 代码视图里要画的查找高亮：全部匹配（UTF-16 区间，升序）与其中的当前一个。
struct FindHighlights: Equatable {
    var ranges: [NSRange]
    var currentIndex: Int?
}

/// ⌘F 查找栏：内容区顶部一条，顶栏分隔线之下、正文之上。
///
/// 一排从左到右：搜索框（计数写在框内右侧）· 上一个 / 下一个 ……富余宽度…… Done。
/// 「搜」与「走」一组（组内 8），Done 单独钉在右边（与上一组至少隔 20），两档间距沿用顶栏。
/// 背景与顶栏同一材质，底边一条与顶栏同款的分隔线。
///
/// 只管控件与按键，不持有查找状态：输入、跳转、关闭都经回调交给 `PreviewWindowController`，
/// 计数文字由它算好后写回来。
///
/// 横向所有宽度约束都低于窗口「保持当前尺寸」的 500：窗口变窄时先收掉 Done 前的空隙，
/// 再把搜索框从 300 收到 160，不会反过来把窗口撑宽。
final class FindBarView: NSView, NSSearchFieldDelegate {
    /// 栏高 = 常规尺寸控件 24pt + 上下各 6pt（上下留白与系统查找栏相同）。
    static let height: CGFloat = 36
    /// 左右内边距与顶栏相同：搜索框左缘对齐上方文件名，Done 右缘对齐上方 More 按钮。
    static let horizontalInset: CGFloat = 14
    /// 搜索框 → 上一个 / 下一个：与顶栏按钮组内间距相同。
    static let clusterSpacing: CGFloat = 8
    /// 上一个 / 下一个 → Done 的最小间距，与顶栏两大组之间相同；窗口变宽时富余宽度全部落在这里。
    static let doneMinimumGap: CGFloat = 20
    /// 搜索框首选宽度：装得下 12 个汉字的搜索词加最长的计数「3 of 100000+」。
    static let fieldPreferredWidth: CGFloat = 300
    /// 搜索框最窄宽度：窗口窄到这一步时搜索词在框内横向滚动。
    static let fieldMinimumWidth: CGFloat = 160
    static let navigationSegmentWidth: CGFloat = 26

    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    let searchField = FindSearchField()
    let navigationControl = NSSegmentedControl()
    let doneButton = NSButton(title: "Done", target: nil, action: nil)

    private let background = NSVisualEffectView()
    private let bottomDivider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()
    /// 最近一次交给回调的搜索词；清除按钮、Enter 都会触发 action，靠它过滤掉没变的那些。
    private var reportedQuery = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 当前搜索词。程序写入不触发 `onQueryChanged`。
    var query: String {
        get { searchField.stringValue }
        set {
            searchField.stringValue = newValue
            reportedQuery = newValue
            searchField.needsLayout = true
        }
    }

    /// 框内计数的文字（「3 of 12」/「No matches」，空搜索词时为空）。
    var countText: String {
        searchField.countText
    }

    /// 焦点进搜索框并全选，接着打字就是换一个词。
    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    /// 写计数。`isNoMatch` 时用系统红：搜索词打错时这一处变色，余光就能看到。没有匹配时上一个 / 下一个置灰。
    func setCount(_ text: String, hasMatches: Bool, isNoMatch: Bool = false) {
        searchField.setCount(text, color: isNoMatch ? .systemRed : .secondaryLabelColor)
        navigationControl.isEnabled = hasMatches
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // 与顶栏同一材质：查找栏是顶栏之外的第二条工具条，不是正文的一部分。
        background.material = .headerView
        background.blendingMode = .withinWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        addSubview(bottomDivider)

        searchField.placeholderString = "Find"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .regular
        searchField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        (searchField.cell as? NSSearchFieldCell)?.maximumRecents = 0
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // 系统查找栏、Safari、Xcode 的上一个 / 下一个都是这对左右 chevron。
        navigationControl.segmentCount = 2
        navigationControl.trackingMode = .momentary
        navigationControl.segmentStyle = .rounded
        navigationControl.controlSize = .regular
        navigationControl.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Match"), forSegment: 0)
        navigationControl.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Match"), forSegment: 1)
        navigationControl.setToolTip("Previous Match (⇧⌘G)", forSegment: 0)
        navigationControl.setToolTip("Next Match (⌘G)", forSegment: 1)
        navigationControl.setWidth(Self.navigationSegmentWidth, forSegment: 0)
        navigationControl.setWidth(Self.navigationSegmentWidth, forSegment: 1)
        navigationControl.target = self
        navigationControl.action = #selector(navigationClicked(_:))
        navigationControl.isEnabled = false
        navigationControl.translatesAutoresizingMaskIntoConstraints = false
        navigationControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .regular
        doneButton.target = self
        doneButton.action = #selector(doneClicked(_:))
        doneButton.toolTip = "Close Find Bar (Esc)"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(searchField)
        addSubview(navigationControl)
        addSubview(doneButton)

        // 搜索框首选宽度的优先级低于「Done 前的空隙至少 20」：窗口窄时先吃掉空隙、再收窄搜索框。
        let preferredFieldWidth = searchField.widthAnchor.constraint(equalToConstant: Self.fieldPreferredWidth)
        preferredFieldWidth.priority = .init(240)
        let minimumFieldWidth = searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.fieldMinimumWidth)
        minimumFieldWidth.priority = .init(480)
        let doneGap = doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: navigationControl.trailingAnchor, constant: Self.doneMinimumGap)
        doneGap.priority = .init(490)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
            preferredFieldWidth,
            minimumFieldWidth,

            navigationControl.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: Self.clusterSpacing),
            navigationControl.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            doneGap,
            doneButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset)
        ])
    }

    // MARK: - 输入与按键

    func controlTextDidChange(_ obj: Notification) {
        reportQueryIfChanged()
    }

    /// 清除按钮（搜索框右端的 ×）走 action，不走 textDidChange。
    @objc private func searchFieldAction(_ sender: Any?) {
        reportQueryIfChanged()
    }

    private func reportQueryIfChanged() {
        let current = searchField.stringValue
        guard current != reportedQuery else { return }
        reportedQuery = current
        onQueryChanged?(current)
    }

    /// Enter 下一个、⇧Enter 上一个、Esc 关闭（不清空搜索词）。
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onNext?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func navigationClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            onPrevious?()
        } else {
            onNext?()
        }
    }

    @objc private func doneClicked(_ sender: Any?) {
        onClose?()
    }
}

/// 计数写在框内、清除按钮左边（与系统查找栏、Chrome 同一个位置）：打字时眼睛不用离开搜索框
/// 就能看到「有没有、有几个」。
///
/// cell 把搜索文字区从右边让出「计数宽 + 6pt」（不编辑时的绘制与编辑时的字段编辑器都按这个矩形走），
/// 计数用一个不接收点击的 label 摆在让出来的那一段里。
final class FindSearchField: NSSearchField {
    /// 计数：11pt 等宽数字，与顶栏副标题同一档字号（同属元信息）。
    static let countFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// 计数文字右缘到清除按钮左缘。
    static let countGapToCancel: CGFloat = 2
    /// 搜索文字右缘到计数左缘的最小间隔（长搜索词在框内滚动时停在这里）。
    static let countGapToText: CGFloat = 6

    override class var cellClass: AnyClass? {
        get { FindSearchFieldCell.self }
        set {}
    }

    private let countLabel = PassThroughLabel(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        countLabel.font = Self.countFont
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byClipping
        countLabel.maximumNumberOfLines = 1
        countLabel.isHidden = true
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(countLabel)
    }

    var countText: String {
        countLabel.stringValue
    }

    func setCount(_ text: String, color: NSColor) {
        countLabel.stringValue = text
        countLabel.textColor = color
        countLabel.isHidden = text.isEmpty
        findCell?.countWidth = countWidth
        needsLayout = true
        needsDisplay = true
        positionCountLabel()
        refitFieldEditor()
    }

    private var findCell: FindSearchFieldCell? {
        cell as? FindSearchFieldCell
    }

    /// 计数文字实际占的宽度（label 两侧各有 2pt 内衬，算进去免得末位被裁）。
    private var countWidth: CGFloat {
        guard !countLabel.isHidden else { return 0 }
        return ceil(countLabel.cell?.cellSize.width ?? countLabel.intrinsicContentSize.width)
    }

    override func layout() {
        super.layout()
        positionCountLabel()
    }

    /// 编辑中计数出现、变宽或消失：字段编辑器所在的裁切区是开始编辑那一刻按文字区定的，
    /// 这里按新的文字区重摆，并把插入点滚回可见范围。
    private func refitFieldEditor() {
        guard let editor = currentEditor() as? NSTextView, let clip = editor.superview, let findCell else { return }
        let textRect = findCell.searchTextRect(forBounds: bounds)
        clip.frame = NSRect(x: textRect.minX, y: clip.frame.minY, width: textRect.width, height: clip.frame.height)
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    private func positionCountLabel() {
        guard !countLabel.isHidden, let findCell else { return }
        let height = ceil(countLabel.cell?.cellSize.height ?? 14)
        let left = findCell.countMinX(forBounds: bounds)
        // 与搜索文字同一条基线：两者都在框里垂直居中，13pt 与 11pt 的降部差约 0.5pt，取整后重合。
        let y = ((bounds.height - height) / 2).rounded()
        countLabel.frame = NSRect(x: left, y: y, width: countWidth, height: height)
    }
}

/// 搜索文字区 = 系统给的文字区，右端截到「计数左缘 − 6pt」。不编辑时的绘制与编辑时的字段编辑器都走它。
final class FindSearchFieldCell: NSSearchFieldCell {
    var countWidth: CGFloat = 0

    func countMinX(forBounds rect: NSRect) -> CGFloat {
        let cancel = cancelButtonRect(forBounds: rect)
        let right = cancel.width > 0 ? cancel.minX - FindSearchField.countGapToCancel : rect.maxX - 8
        return right - countWidth
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect)
        guard countWidth > 0 else { return text }
        text.size.width = max(24, countMinX(forBounds: rect) - FindSearchField.countGapToText - text.minX)
        return text
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawing = super.drawingRect(forBounds: rect)
        guard countWidth > 0 else { return drawing }
        drawing.size.width = max(24, countMinX(forBounds: rect) - FindSearchField.countGapToText - drawing.minX)
        return drawing
    }
}

/// 不接收点击的 label：点在计数上等于点在搜索框里。
final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
