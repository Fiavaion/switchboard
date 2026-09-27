import AppKit
import SwitchboardCore
import os

/// PRD F2 — Cmd+Shift+3 / Cmd+Shift+4 straight to the clipboard via `/usr/sbin/screencapture`
/// (D3: pixel-identical to the system tool; the only subprocess Switchboard runs).
final class ScreenshotController {
    private let store: SettingsStore
    private let hud: HUD
    private var running = false

    init(store: SettingsStore, hud: HUD) {
        self.store = store
        self.hud = hud
    }

    /// Event-tap entry point (main thread). Swallows exactly Cmd+Shift+3 and Cmd+Shift+4, so
    /// the system hotkeys never fire; Cmd+Ctrl+Shift variants and Cmd+Shift+5 pass through.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let mods = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        guard mods == [.maskCommand, .maskShift], key == KeyCode.three || key == KeyCode.four else { return false }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let interactive = key == KeyCode.four
            DispatchQueue.main.async { self.capture(interactive: interactive) }
        }
        return true
    }

    func capture(interactive: Bool) {
        guard !running else { return }                          // one capture at a time
        let settings = store.settings
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        var file: URL?
        var args = interactive ? ["-i"] : []
        if settings.screenshotSaveToFolder {                    // F2.3: file too, then copy it
            let url = Self.fileURL(folder: settings.screenshotFolder)
            file = url
            args.append(url.path)
        } else {
            args.insert("-c", at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.finish(status: p.terminationStatus, file: file, pasteboard: pasteboard, before: before)
            }
        }
        do {
            running = true
            try process.run()
            Logger.capture.info("screencapture \(args.joined(separator: " "), privacy: .public)")
        } catch {
            running = false
            Logger.capture.error("screencapture failed to start: \(error.localizedDescription)")
        }
    }

    private func finish(status: Int32, file: URL?, pasteboard: NSPasteboard, before: Int) {
        running = false
        if let file, let data = try? Data(contentsOf: file) {
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        }
        // Cancelling an interactive capture (Esc) leaves the clipboard untouched: no HUD then.
        let copied = pasteboard.changeCount != before
        Logger.capture.info("screencapture exited \(status); clipboard updated: \(copied)")
        if copied, store.settings.showScreenshotHUD { hud.show("Copied to clipboard") }
    }

    private static func fileURL(folder: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        return dir.appendingPathComponent("Screenshot \(formatter.string(from: Date())).png")
    }
}

/// PRD F2.5 — make clipboard screenshots survive Switchboard quitting. Writing the system's own
/// `com.apple.screencapture target` preference makes plain Cmd+Shift+3/4 copy to the clipboard,
/// so the symbolic hotkeys need no change. Written through CFPreferences, not a `defaults`
/// subprocess (CLAUDE.md: `screencapture` is the only subprocess).
enum SystemScreenshotDefaults {
    private static let domain = "com.apple.screencapture" as CFString
    private static let key = "target" as CFString

    static var targetsClipboard: Bool {
        CFPreferencesCopyAppValue(key, domain) as? String == "clipboard"
    }

    static func setTargetsClipboard(_ on: Bool) {
        CFPreferencesSetAppValue(key, on ? "clipboard" as CFString : nil, domain)
        CFPreferencesAppSynchronize(domain)
        Logger.capture.info("System screenshot target set to \(on ? "clipboard" : "default (files)", privacy: .public)")
    }
}
