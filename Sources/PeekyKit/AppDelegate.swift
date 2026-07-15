import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var windows: [PreviewWindowController] = []
    private var editMenu: NSMenu?
    private var copyRelativePathMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())

        let copyAllItem = NSMenuItem(title: "Copy All", action: #selector(copyAllTextAction(_:)), keyEquivalent: "c")
        copyAllItem.keyEquivalentModifierMask = [.command, .option]
        copyAllItem.target = self
        editMenu.addItem(copyAllItem)

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

        editMenu.addItem(.separator())

        let copyFileItem = NSMenuItem(title: "Copy File", action: #selector(copyFileAction(_:)), keyEquivalent: "")
        copyFileItem.target = self
        editMenu.addItem(copyFileItem)

        let copyPathLineItem = NSMenuItem(
            title: "Copy Path:Line",
            action: #selector(copyPathLineAction(_:)),
            keyEquivalent: ""
        )
        copyPathLineItem.target = self
        editMenu.addItem(copyPathLineItem)

        editMenu.addItem(.separator())

        let openInEditorItem = NSMenuItem(
            title: "Open in Editor",
            action: #selector(openInEditorAction(_:)),
            keyEquivalent: "e"
        )
        openInEditorItem.keyEquivalentModifierMask = [.command]
        openInEditorItem.target = self
        editMenu.addItem(openInEditorItem)

        editMenu.delegate = self
        self.editMenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Edit 菜单复制五件套 + ⌘E（转发到当前 key/main 窗口的 PreviewWindowController）

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

    /// 复制五件套 + ⌘E 六项：无打开文件时全部禁用；相对路径项额外要求命中 repo root。
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let copyActions: Set<Selector> = [
            #selector(copyAllTextAction(_:)),
            #selector(copyAbsolutePathAction(_:)),
            #selector(copyRelativePathAction(_:)),
            #selector(copyFileAction(_:)),
            #selector(copyPathLineAction(_:)),
            #selector(openInEditorAction(_:))
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

    @objc private func copyAbsolutePathAction(_ sender: Any?) {
        activeWindowController()?.copyAbsolutePath()
    }

    @objc private func copyRelativePathAction(_ sender: Any?) {
        activeWindowController()?.copyRelativePath()
    }

    @objc private func copyFileAction(_ sender: Any?) {
        activeWindowController()?.copyFileReference()
    }

    @objc private func copyPathLineAction(_ sender: Any?) {
        activeWindowController()?.copyPathLineReference()
    }

    @objc private func openInEditorAction(_ sender: Any?) {
        activeWindowController()?.openInEditor()
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
