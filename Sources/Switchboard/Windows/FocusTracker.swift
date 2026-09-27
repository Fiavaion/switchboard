import AppKit
import SwitchboardCore
import os

/// PRD M2 — feeds MRU order from real focus changes: app activation (NSWorkspace) plus an
/// AX focused-window observer per app, so switching windows *within* an app counts too.
/// Event-driven only (N1). Also caches each focused window's AX element, which is how windows
/// that later sit on another Space stay raisable. Main thread only.
final class FocusTracker {
    private(set) var mru = MRUList()
    private(set) var elements: [CGWindowID: AXUIElement] = [:]
    /// Windows the element scan could not resolve (see `WindowSnapshot.unresolved`).
    private(set) var unresolved: Set<CGWindowID> = []
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []

    var isRunning: Bool { !tokens.isEmpty }

    func start() {
        guard !isRunning else { return }
        let nc = NSWorkspace.shared.notificationCenter
        tokens = [
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.observe(app) }
            },
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.unobserve(app.processIdentifier) }
            },
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.observe(app)                               // retries apps whose observer failed at launch
                self?.recordFocusedWindow(of: app.processIdentifier)
            },
        ]
        NSWorkspace.shared.runningApplications.forEach(observe)
        if let front = NSWorkspace.shared.frontmostApplication { recordFocusedWindow(of: front.processIdentifier) }
        Logger.windows.info("Focus tracker observing \(self.observers.count) apps")
    }

    /// Records a focus change Switchboard itself caused, or one found at switcher open.
    func record(_ id: CGWindowID, element: AXUIElement?) {
        guard id != 0 else { return }
        mru.touch(id)
        if let element { elements[id] = AX.bounded(element) }
    }

    /// Adds elements seen during enumeration and forgets windows that no longer exist. The
    /// snapshot was taken off main a moment ago, so a window created since then is kept by
    /// checking the window server again before pruning.
    func merge(_ snapshot: WindowSnapshot) {
        elements.merge(snapshot.elements) { _, new in new }
        unresolved.formUnion(snapshot.unresolved)
        let now = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        let live = Set(snapshot.zOrder).union(now)
        elements = elements.filter { live.contains($0.key) }
        unresolved = unresolved.filter { live.contains($0) }
        mru.prune(keeping: live)
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axFocusCallback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Freshly launched apps often answer cannotComplete; don't store the observer, so the
        // next activation of the app tries again.
        guard AXObserverAddNotification(observer, AX.application(pid), kAXFocusedWindowChangedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func recordFocusedWindow(of pid: pid_t) {
        guard let window = AX.element(AX.application(pid), kAXFocusedWindowAttribute) else { return }
        record(AX.windowID(window), element: window)
    }

    fileprivate func focusChanged(_ window: AXUIElement) {
        AX.bounded(window)                                    // runs on main: never wait on a hung app
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        // A background app changing its own focused window (e.g. opening one) is not a user switch.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        record(AX.windowID(window), element: window)
    }
}

private func axFocusCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue().focusChanged(element)
}
