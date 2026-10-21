import AppKit

// 空白窗口（窗口里没有打开的文件）里的最近文件列表：EmptyStateGroup 装着既有的「Peeky + Open File」
// 与 RecentFilesSectionView；每一行是一个 RecentFileRowView。显示内容全部来自 RecentFiles.Item。

/// 固有宽度向上取整到整点的标签。文字宽常带半点（如 72.5），布局按像素取整时可能落到 72，
/// 恰好少半点，文件名被截出一个省略号；取整之后宽度只会多、不会少。
final class WholePointLabel: NSTextField {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: ceil(size.width), height: size.height)
    }
}

/// 一条最近文件。无壳、悬停出浅底，单击打开——与侧栏文件卡片同一套悬停约定：
/// 整行宽度用 0.06（悬停底的不透明度随面积取值，见 PATTERNS「按钮外观统一走 HoverButton」）。
/// 不可打开的行整行落到三级色、没有悬停底、点击无反应，原因写在行尾。
final class RecentFileRowView: NSControl {
    enum Arrangement {
        /// 文件名 · 位置 · 原因 排一行，行高 22。
        case singleLine
        /// 文件名与原因在上，位置在下，行高 40（行内两行间距 1、行与行之间 9，位置读得出归哪个文件名）。
        /// 列表宽度装不下一行时用。
        case twoLine
    }

    static let hoverAlpha: CGFloat = 0.06
    static let singleLineHeight: CGFloat = 22
    static let twoLineHeight: CGFloat = 40
    /// 列表宽度低于它就换两行排。长文件名 + worktree 位置 + 原因单行约需 470pt。
    static let singleLineMinimumWidth: CGFloat = 480

    static func arrangement(forWidth width: CGFloat) -> Arrangement {
        width >= singleLineMinimumWidth ? .singleLine : .twoLine
    }

    static func height(for arrangement: Arrangement) -> CGFloat {
        arrangement == .singleLine ? singleLineHeight : twoLineHeight
    }

    var onOpen: ((String) -> Void)?

    var arrangement: Arrangement = .singleLine {
        didSet {
            guard arrangement != oldValue else { return }
            applyArrangement()
        }
    }

    let item: RecentFiles.Item
    private let nameLabel = WholePointLabel(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(labelWithString: "")
    private var heightConstraint: NSLayoutConstraint!
    private var singleLineConstraints: [NSLayoutConstraint] = []
    private var twoLineConstraints: [NSLayoutConstraint] = []
    private var hoverTrackingArea: NSTrackingArea?

    private var isHovering = false {
        didSet { updateAppearance() }
    }

    init(item: RecentFiles.Item) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        toolTip = item.tooltip

        nameLabel.stringValue = item.name
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle

        locationLabel.stringValue = item.location
        locationLabel.font = NSFont.systemFont(ofSize: 11)
        locationLabel.lineBreakMode = .byTruncatingMiddle

        reasonLabel.stringValue = item.reason ?? ""
        reasonLabel.font = NSFont.systemFont(ofSize: 11)
        reasonLabel.isHidden = item.reason == nil

        // 文件名与原因按自身宽度排；位置一路铺到原因前面（文字靠左，多出来的宽度是空白），
        // 所以它只在真装不下时才截。装不下时先截位置、再截文件名，最后才截原因。
        // 抗压缩一律低于 500：行宽经 rowStack → clipView → scrollView 一路连到窗口宽，
        // 高于窗口「保持当前尺寸」的 500 就会把窗口撑宽，而不是让文字截断。
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        reasonLabel.setContentHuggingPriority(.required, for: .horizontal)
        locationLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(200), for: .horizontal)
        reasonLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(499), for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(490), for: .horizontal)
        locationLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(480), for: .horizontal)

        for view in [nameLabel, locationLabel, reasonLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        // 文件名左缘 6 = 「Recent Files」标题的左缘，整列共用一条左边线。
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.singleLineHeight)
        NSLayoutConstraint.activate([
            heightConstraint,
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            reasonLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            reasonLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor)
        ])

        singleLineConstraints = [
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            locationLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            locationLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            locationLabel.trailingAnchor.constraint(lessThanOrEqualTo: reasonLabel.leadingAnchor, constant: -16),
            fill(locationLabel.trailingAnchor, to: reasonLabel.leadingAnchor, constant: -16)
        ]
        twoLineConstraints = [
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: reasonLabel.leadingAnchor, constant: -16),
            locationLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            locationLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            locationLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            fill(locationLabel.trailingAnchor, to: trailingAnchor, constant: -8)
        ]
        applyArrangement()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 弱于一切抗压缩的「铺满」：标签宽度只在有富余时向右铺开。
    private func fill(_ anchor: NSLayoutXAxisAnchor, to target: NSLayoutXAxisAnchor, constant: CGFloat) -> NSLayoutConstraint {
        let constraint = anchor.constraint(equalTo: target, constant: constant)
        constraint.priority = NSLayoutConstraint.Priority(240)
        return constraint
    }

    private func applyArrangement() {
        NSLayoutConstraint.deactivate(arrangement == .singleLine ? twoLineConstraints : singleLineConstraints)
        NSLayoutConstraint.activate(arrangement == .singleLine ? singleLineConstraints : twoLineConstraints)
        heightConstraint.constant = Self.height(for: arrangement)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        HoverTracking.reinstall(on: self, previous: &hoverTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        guard item.isOpenable else { return }
        onOpen?(item.path)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isHovering && item.isOpenable)
                ? NSColor.labelColor.withAlphaComponent(Self.hoverAlpha).cgColor
                : NSColor.clear.cgColor
        }
        nameLabel.textColor = item.isOpenable ? .labelColor : .tertiaryLabelColor
        locationLabel.textColor = item.isOpenable ? .secondaryLabelColor : .tertiaryLabelColor
        reasonLabel.textColor = .secondaryLabelColor
    }
}

/// 「Recent Files」标题行（右端 Clear）+ 可滚动的行列表。
/// 高度 = 标题行 + 全部行高，外层约束装不下时列表区收矮、内部滚动。
final class RecentFilesSectionView: NSView {
    static let maximumWidth: CGFloat = 560
    static let headerHeight: CGFloat = 20
    static let headerToList: CGFloat = 4

    var onOpen: ((String) -> Void)?
    var onClear: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Recent Files")
    private let clearButton = HoverButton()
    private let scrollView = NSScrollView()
    private let rowStack = FlippedStackView()
    private var rows: [RecentFileRowView] = []
    private var listHeightConstraint: NSLayoutConstraint!
    private var arrangement: RecentFileRowView.Arrangement = .singleLine

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 与侧栏 Open 区的「Close All」同款：HoverButton、11pt 文字、右对齐在列表上方。
        clearButton.title = "Clear"
        clearButton.font = NSFont.systemFont(ofSize: 11)
        clearButton.toolTip = "Clear Recent Files"
        clearButton.target = self
        clearButton.action = #selector(clearClicked(_:))
        clearButton.prepareHoverAppearance()
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        rowStack.orientation = .vertical
        rowStack.alignment = .width
        rowStack.spacing = 0
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = rowStack
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(clearButton)
        addSubview(scrollView)

        // 列表区想要「装下全部行」，但让位给外层的上下边距约束：装不下时收矮、滚动。
        // 低于窗口「保持当前尺寸」的 500，否则 20 行会把矮窗口撑高。
        listHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
        listHeightConstraint.priority = NSLayoutConstraint.Priority(490)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight / 2),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.heightAnchor.constraint(equalToConstant: 18),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerHeight + Self.headerToList),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: RecentFileRowView.twoLineHeight),
            listHeightConstraint,

            rowStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ items: [RecentFiles.Item]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { item in
            let row = RecentFileRowView(item: item)
            row.arrangement = arrangement
            row.onOpen = { [weak self] path in self?.onOpen?(path) }
            rowStack.addArrangedSubview(row)
            return row
        }
        updateListHeight()
        // 叠加式滚动条平时不显示；列表被截短时闪一下，告诉读者下面还有。
        scrollView.flashScrollers()
    }

    override func layout() {
        super.layout()
        let next = RecentFileRowView.arrangement(forWidth: bounds.width)
        guard next != arrangement else { return }
        arrangement = next
        rows.forEach { $0.arrangement = next }
        updateListHeight()
    }

    private func updateListHeight() {
        listHeightConstraint.constant = CGFloat(rows.count) * RecentFileRowView.height(for: arrangement)
    }

    @objc private func clearClicked(_ sender: Any?) {
        onClear?()
    }
}

/// 空白窗口的整块内容。既有的标题 + 按钮栈（`launcher`）原样放进来，最近文件列表排在它下方；
/// 容器代替原来的 emptyView 去对齐 contentView。
///
/// 两套约束显式切换，不交给 NSStackView 的隐藏视图摘除——列表在「有记录 / 清空」之间来回切，
/// 摘除再挂回会丢掉挂在它身上的外部约束；NSStackView 在装不下时也会让排进去的视图溢出，
/// 而这里要的是列表收矮、内部滚动。
final class EmptyStateGroup: NSView {
    /// 按钮与列表之间 28，标题与按钮之间 12（既有）：前两件是一组，最近文件是另一组。
    static let launcherToRecentFiles: CGFloat = 28
    static let edgeMargin: CGFloat = 24

    let launcher: NSView
    let recentFiles: RecentFilesSectionView
    private var visibleConstraints: [NSLayoutConstraint] = []
    private var hiddenConstraints: [NSLayoutConstraint] = []

    init(launcher: NSView, recentFiles: RecentFilesSectionView) {
        self.launcher = launcher
        self.recentFiles = recentFiles
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        launcher.translatesAutoresizingMaskIntoConstraints = false
        addSubview(launcher)
        addSubview(recentFiles)

        let hugLauncher = widthAnchor.constraint(equalTo: launcher.widthAnchor)
        hugLauncher.priority = .defaultLow
        // 有富余时取满 560；低于窗口「保持当前尺寸」的 500，窄窗口里收窄而不是把窗口撑宽。
        let preferredWidth = widthAnchor.constraint(equalToConstant: RecentFilesSectionView.maximumWidth)
        preferredWidth.priority = NSLayoutConstraint.Priority(490)

        NSLayoutConstraint.activate([
            launcher.topAnchor.constraint(equalTo: topAnchor),
            launcher.centerXAnchor.constraint(equalTo: centerXAnchor),
            launcher.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: RecentFilesSectionView.maximumWidth),
            hugLauncher,
            recentFiles.topAnchor.constraint(equalTo: launcher.bottomAnchor, constant: Self.launcherToRecentFiles),
            recentFiles.leadingAnchor.constraint(equalTo: leadingAnchor),
            recentFiles.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        visibleConstraints = [recentFiles.bottomAnchor.constraint(equalTo: bottomAnchor), preferredWidth]
        hiddenConstraints = [launcher.bottomAnchor.constraint(equalTo: bottomAnchor)]
        setRecentFilesVisible(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 零条记录时列表隐藏、容器收回到只包住标题 + 按钮，空白窗口与原来一模一样。
    func setRecentFilesVisible(_ visible: Bool) {
        recentFiles.isHidden = !visible
        NSLayoutConstraint.deactivate(visible ? hiddenConstraints : visibleConstraints)
        NSLayoutConstraint.activate(visible ? visibleConstraints : hiddenConstraints)
    }

    /// 容器在 contentView 里的位置：照旧水平、竖直居中，但两条都降到 500——
    /// 列表长时整块往上让、不压标题区；四周至少留 24。
    func constraints(centeredIn content: NSView, below topEdge: NSLayoutYAxisAnchor) -> [NSLayoutConstraint] {
        let centerX = centerXAnchor.constraint(equalTo: content.centerXAnchor)
        centerX.priority = NSLayoutConstraint.Priority(500)
        let centerY = centerYAnchor.constraint(equalTo: content.centerYAnchor)
        centerY.priority = NSLayoutConstraint.Priority(500)
        return [
            centerX,
            centerY,
            topAnchor.constraint(greaterThanOrEqualTo: topEdge, constant: Self.edgeMargin),
            bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -Self.edgeMargin),
            leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: Self.edgeMargin),
            trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -Self.edgeMargin)
        ]
    }
}
