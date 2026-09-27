import AppKit
import SwiftUI

/// Shows at most one instance of each regular window (onboarding, settings).
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    func show<Content: View>(id: String, title: String, onClose: (() -> Void)? = nil, content: () -> Content) {
        NSApp.activate()
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.windows[id] = nil
            if let token = self?.closeObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(token) }
            onClose?()
        }
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
