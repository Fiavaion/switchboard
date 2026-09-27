import AppKit

/// PRD F5.1 — menu bar status item.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onSettings: () -> Void
    private let onPermissions: () -> Void

    init(onSettings: @escaping () -> Void, onPermissions: @escaping () -> Void) {
        self.onSettings = onSettings
        self.onPermissions = onPermissions
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Switchboard")
        let menu = NSMenu()
        menu.addItem(entry("Settings…", #selector(settings), key: ","))
        menu.addItem(entry("Check Permissions…", #selector(permissions)))
        menu.addItem(.separator())
        menu.addItem(entry("About Switchboard", #selector(about)))
        menu.addItem(withTitle: "Quit Switchboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    /// F5.2 — hidden until the setting is turned back on (reopen the app to reach Settings).
    var isVisible: Bool {
        get { item.isVisible }
        set { item.isVisible = newValue }
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func settings() { onSettings() }
    @objc private func permissions() { onPermissions() }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
