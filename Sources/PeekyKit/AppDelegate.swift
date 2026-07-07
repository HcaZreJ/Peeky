import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [PreviewWindowController] = []

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

        NSApp.mainMenu = mainMenu
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
