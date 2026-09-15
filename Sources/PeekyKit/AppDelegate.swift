import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var windows: [PreviewWindowController] = []
    private var editMenu: NSMenu?
    private var copyRelativePathMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动早期后台预热高亮引擎（eval bundle + init + 空 tokenize）：非阻塞，
        // 首个源码/JSON 原文文件打开时首屏高亮已无感知延迟。
        HighlightService.shared.warmUp()

        buildMainMenu()

        let launchRequests = CommandLine.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-") }
            .compactMap(OpenRequest.commandLineArgument)

        if !launchRequests.isEmpty {
            open(requests: launchRequests)
        }

        if windows.isEmpty {
            showEmptyWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        open(requests: filenames.map { OpenRequest(url: URL(fileURLWithPath: $0)) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(requests: urls.compactMap(OpenRequest.incomingURL))
    }

    @objc private func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Peeky",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Peeky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(.separator())

        let closeFileItem = NSMenuItem(
            title: "Close File",
            action: #selector(closeFileAction(_:)),
            keyEquivalent: "w"
        )
        closeFileItem.target = self
        fileMenu.addItem(closeFileItem)

        let closeWindowItem = NSMenuItem(
            title: "Close Window",
            action: #selector(closeWindowAction(_:)),
            keyEquivalent: "w"
        )
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
        closeWindowItem.target = self
        fileMenu.addItem(closeWindowItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let copyAllItem = NSMenuItem(title: "Copy File Content", action: #selector(copyAllTextAction(_:)), keyEquivalent: "c")
        copyAllItem.keyEquivalentModifierMask = [.command, .option]
        copyAllItem.target = self
        editMenu.addItem(copyAllItem)

        let copyFileNameItem = NSMenuItem(
            title: "Copy File Name",
            action: #selector(copyFileNameAction(_:)),
            keyEquivalent: ""
        )
        copyFileNameItem.target = self
        editMenu.addItem(copyFileNameItem)

        let copyAbsolutePathItem = NSMenuItem(
            title: "Copy Absolute Path",
            action: #selector(copyAbsolutePathAction(_:)),
            keyEquivalent: "c"
        )
        copyAbsolutePathItem.keyEquivalentModifierMask = [.command, .shift]
        copyAbsolutePathItem.target = self
        editMenu.addItem(copyAbsolutePathItem)

        let copyRelativePathItem = NSMenuItem(
            title: "Copy Relative Path",
            action: #selector(copyRelativePathAction(_:)),
            keyEquivalent: "c"
        )
        copyRelativePathItem.keyEquivalentModifierMask = [.command, .shift, .option]
        copyRelativePathItem.target = self
        editMenu.addItem(copyRelativePathItem)
        copyRelativePathMenuItem = copyRelativePathItem

        editMenu.delegate = self
        self.editMenu = editMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)

        // Reload/Refresh 在 macOS 上的标准归宿是 View（Safari 的 Reload Page 也在这里，
        // 快捷键同样是 ⌘R）；File 菜单的共同总体是「对文档做的事」，装不下目录树。
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let refreshItem = NSMenuItem(
            title: "Refresh from Disk",
            action: #selector(refreshFromDiskAction(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        viewMenu.addItem(refreshItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Edit 菜单复制四件套（转发到当前 key/main 窗口的 PreviewWindowController）

    private func activeWindowController() -> PreviewWindowController? {
        if let keyWindowController = windows.first(where: { $0.window?.isKeyWindow == true }) {
            return keyWindowController
        }
        return windows.first(where: { $0.window?.isMainWindow == true })
    }

    /// 弹出前隐藏「复制相对路径」——当前活跃文件不在任何 repo 内时该项不出现。
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === editMenu else { return }

        let showRelativePath: Bool
        if let controller = activeWindowController(), !controller.isEmpty, let url = controller.activeFileURL {
            showRelativePath = RepoRoot.discover(from: url) != nil
        } else {
            showRelativePath = false
        }

        copyRelativePathMenuItem?.isHidden = !showRelativePath
    }

    /// 复制四件套：无打开文件时全部禁用；相对路径项额外要求命中 repo root。
    /// 两个关闭项要求存在 key 窗口。刷新要求当前窗口有树根。
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(refreshFromDiskAction(_:)) {
            return activeWindowController()?.hasFileTreeRoot == true
        }

        let closeActions: Set<Selector> = [
            #selector(closeFileAction(_:)),
            #selector(closeWindowAction(_:))
        ]

        if let action = menuItem.action, closeActions.contains(action) {
            return closeTargetWindow() != nil
        }

        let copyActions: Set<Selector> = [
            #selector(copyAllTextAction(_:)),
            #selector(copyFileNameAction(_:)),
            #selector(copyAbsolutePathAction(_:)),
            #selector(copyRelativePathAction(_:))
        ]

        guard let action = menuItem.action, copyActions.contains(action) else {
            return true
        }

        guard let controller = activeWindowController(), !controller.isEmpty else {
            return false
        }

        if action == #selector(copyRelativePathAction(_:)) {
            guard let url = controller.activeFileURL else { return false }
            return RepoRoot.discover(from: url) != nil
        }

        return true
    }

    @objc private func copyAllTextAction(_ sender: Any?) {
        activeWindowController()?.copyAllText()
    }

    @objc private func copyFileNameAction(_ sender: Any?) {
        activeWindowController()?.copyFileName()
    }

    @objc private func copyAbsolutePathAction(_ sender: Any?) {
        activeWindowController()?.copyAbsolutePath()
    }

    @objc private func copyRelativePathAction(_ sender: Any?) {
        activeWindowController()?.copyRelativePath()
    }

    /// ⌘R：文件树与当前文件一起跟磁盘对一次账。
    @objc private func refreshFromDiskAction(_ sender: Any?) {
        activeWindowController()?.refreshFromDisk()
    }

    // MARK: - 关闭（⌘W 关文件，⇧⌘W 关窗口）

    /// 关闭目标窗口当前显示的文件；该窗口没有打开文件时（空窗口、About 等面板）关闭窗口本身，
    /// 让 ⌘W 连按可以「一个个关掉文件，最后关窗」。
    @objc private func closeFileAction(_ sender: Any?) {
        guard let window = closeTargetWindow() else { return }

        if let controller = windows.first(where: { $0.window === window }), !controller.isEmpty {
            controller.closeActiveTab()
        } else {
            window.performClose(sender)
        }
    }

    @objc private func closeWindowAction(_ sender: Any?) {
        closeTargetWindow()?.performClose(sender)
    }

    /// 关闭动作的落点：key 窗口优先，与复制四件套的 activeWindowController() 同一取法。
    private func closeTargetWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        let response = panel.runModal()
        guard response == .OK else { return }
        open(urls: panel.urls)
    }

    private func showEmptyWindow() {
        let controller = makeWindowController()
        controller.showWindow(nil)
    }

    private func open(urls: [URL]) {
        open(requests: urls.compactMap(OpenRequest.fileURL))
    }

    private func open(requests: [OpenRequest]) {
        // 目录请求同样路由到 targetWindowController：由窗口按其自身逻辑设置/切换树根
        // （不产生内容 tab），不在此处过滤掉。
        guard !requests.isEmpty else { return }

        let controller = targetWindowController()
        controller.showWindow(nil)
        controller.open(requests: requests)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func targetWindowController() -> PreviewWindowController {
        if let keyWindowController = windows.first(where: { $0.window?.isKeyWindow == true }) {
            return keyWindowController
        }

        if let mainWindowController = windows.first(where: { $0.window?.isMainWindow == true }) {
            return mainWindowController
        }

        if let existingWindowController = windows.first {
            return existingWindowController
        }

        return makeWindowController()
    }

    private func makeWindowController() -> PreviewWindowController {
        let controller = PreviewWindowController()
        controller.onOpenRequested = { [weak self] in
            self?.showOpenPanel()
        }
        controller.onURLsDropped = { [weak self] urls in
            self?.open(urls: urls)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        return controller
    }
}
