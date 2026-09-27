import AppKit
import SwitchboardCore
import os

/// PRD F1.3 — raise **that window**, not just its app.
///
/// Order matters and was verified against a back-most Safari window (RESEARCH §2): mark the
/// window main, AXRaise it, then make its app frontmost through AX. `kAXFrontmostAttribute`
/// works from a background app, where `NSRunningApplication.activate` is refused under
/// macOS 14 cooperative activation.
///
/// Each activation has one overall time budget and is abandoned as soon as a newer one is
/// requested, so a hung app can neither pile up queued switches nor steal focus late.
enum WindowActivator {
    private static let queue = DispatchQueue(label: "com.fiavaion.switchboard.activate", qos: .userInteractive)
    private static let lock = NSLock()
    private static var latest = 0
    private static let budget: TimeInterval = 1.0

    private struct Attempt {
        let token: Int
        let deadline: Date
        var isLive: Bool { Date() < deadline && WindowActivator.isLatest(token) }
    }

    static func activate(_ window: WindowInfo, element: AXUIElement?) {
        let token = lock.withLock { latest += 1; return latest }
        let attempt = Attempt(token: token, deadline: Date() + budget)   // budget runs from the key release
        queue.async {
            guard attempt.isLive else { return }
            let app = AX.bounded(AXUIElementCreateApplication(window.pid), AX.actionTimeout)
            // LESSON-API-001: unhide through AX, in order: NSRunningApplication.unhide() is asynchronous, and a
            // frontmost request that reaches a still-hidden app is ignored.
            if window.isAppHidden { AX.set(app, kAXHiddenAttribute, false) }
            if let element {
                raise(element, app: app, attempt)
                return
            }
            // No AX element (window on another Space): bring the app forward so macOS switches
            // Space, then wait for the window to appear in the app's list and raise it.
            bringToFront(app, attempt)
            while attempt.isLive {
                if let found = AX.windows(of: app)?.first(where: { AX.windowID($0) == window.id }) {
                    raise(found, app: app, attempt)
                    return
                }
                usleep(50_000)
            }
            Logger.windows.error("Window \(window.id) not found after app activation; app-level switch only")
        }
    }

    private static func isLatest(_ token: Int) -> Bool {
        lock.withLock { latest == token }
    }

    private static func raise(_ element: AXUIElement, app: AXUIElement, _ attempt: Attempt) {
        // The element is shared with enumeration (0.2 s reads); a raise can take ~0.3 s (Safari).
        AX.bounded(element, AX.actionTimeout)
        defer { AX.bounded(element) }
        if AX.bool(element, kAXMinimizedAttribute) { AX.set(element, kAXMinimizedAttribute, false) }
        guard attempt.isLive else { return }
        AX.set(element, kAXMainAttribute, true)
        guard attempt.isLive else { return }
        AX.perform(element, kAXRaiseAction)
        guard attempt.isLive, bringToFront(app, attempt) else { return }
        let focused = AX.element(app, kAXFocusedWindowAttribute).map(AX.windowID) ?? 0
        let target = AX.windowID(element)
        if focused == target {
            Logger.windows.info("Raised window \(target)")
        } else {
            Logger.windows.error("Raise of window \(target) left window \(focused) focused")
        }
    }

    /// A frontmost request can be dropped while an app is still unhiding or its Space is still
    /// switching, so re-assert until the app reports itself frontmost or the attempt expires.
    /// Only an app that answered is asked again: a timed-out request still sits in a busy app's
    /// queue, and piling up more would let it grab focus long after the user moved on.
    @discardableResult
    private static func bringToFront(_ app: AXUIElement, _ attempt: Attempt) -> Bool {
        while attempt.isLive {
            guard AX.set(app, kAXFrontmostAttribute, true) else {
                Logger.windows.error("App did not answer the frontmost request; not retrying")
                return false
            }
            if AX.bool(app, kAXFrontmostAttribute) { return true }
            usleep(50_000)
        }
        Logger.windows.error("App did not become frontmost (superseded or out of time)")
        return false
    }
}
