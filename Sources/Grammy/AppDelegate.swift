import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let coordinator = Coordinator()
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem!
    private let enabledItem = NSMenuItem(title: "有効", action: #selector(toggleEnabled), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openAccessibility), keyEquivalent: "")
    private let resetPermissionItem = NSMenuItem(title: "アクセシビリティ権限をリセットして再許可…",
                                                 action: #selector(resetAccessibility), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        coordinator.onCheckingChanged = { [weak self] checking in
            self?.updateIcon(checking: checking)
        }
        coordinator.start()
        if CommandLine.arguments.contains("--debug-panel") { coordinator.showDebugPanel() }

        if !AX.isTrusted { AX.requestTrust() }
        if settings.apiKey == nil { settingsWindow.show() }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(checking: false)

        let menu = NSMenu()
        menu.delegate = self
        enabledItem.target = self
        permissionItem.target = self
        resetPermissionItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(withTitle: "今すぐチェック", action: #selector(checkNow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(resetPermissionItem)
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Grammy を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateIcon(checking: Bool) {
        let name = checking ? "ellipsis.bubble" : (settings.isEnabled ? "text.badge.checkmark" : "text.badge.xmark")
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Grammy")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = settings.isEnabled ? .on : .off
        permissionItem.title = AX.isTrusted ? "アクセシビリティ: 許可済み" : "⚠️ アクセシビリティ権限を許可…"
        resetPermissionItem.isHidden = AX.isTrusted
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        updateIcon(checking: false)
    }

    @objc private func checkNow() { coordinator.checkNow() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openAccessibility() { AX.openAccessibilitySettings() }
    @objc private func resetAccessibility() { AX.resetAndRequestTrust() }
}
