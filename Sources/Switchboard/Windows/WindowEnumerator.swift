import AppKit
import SwitchboardCore
import os

/// Everything the switcher needs from one enumeration pass.
struct WindowSnapshot {
    var windows: [WindowInfo] = []
    var elements: [CGWindowID: AXUIElement] = [:]
    /// Window-server order, front to back.
    var zOrder: [CGWindowID] = []
    /// The focused window of the frontmost app, if any.
    var focusedID: CGWindowID?
    /// Windows the element scan looked for and could not find (not real windows, or not
    /// addressable); skipped by later scans so a miss never costs a full scan twice.
    var unresolved: Set<CGWindowID> = []
}

/// PRD F1.6 — builds the window list from AX (titles, minimised/main state, the element used to
/// raise the window) joined with CGWindowList (layer, bounds, on-screen, z-order).
///
/// AX omits other-Space windows for some apps (full-screen ones in particular), so those come
/// from (a) AX elements cached by `FocusTracker`, then (b) a direct element scan of the owning
/// app (`AX.windowElements`), and only then (c) titled CGWindowList entries that SkyLight
/// confirms sit on another Space, which are activated app-first (`WindowActivator`). An app too
/// busy to answer AX in time is listed from CGWindowList alone rather than dropped.
/// Safe off the main thread.
enum WindowEnumerator {
    private struct CGEntry {
        let pid: pid_t, layer: Int, bounds: CGRect, onScreen: Bool, name: String
    }

    static func snapshot(cachedElements: [CGWindowID: AXUIElement], unresolved: Set<CGWindowID> = []) -> WindowSnapshot {
        var snap = WindowSnapshot()
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var entries: [CGWindowID: CGEntry] = [:]
        for d in raw {
            guard let id = d[kCGWindowNumber as String] as? CGWindowID,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            entries[id] = CGEntry(pid: pid, layer: d[kCGWindowLayer as String] as? Int ?? 0, bounds: bounds,
                                  onScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                  name: d[kCGWindowName as String] as? String ?? "")
            snap.zOrder.append(id)
        }

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
        let appByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })

        func add(_ id: CGWindowID, element: AXUIElement?, app: NSRunningApplication, entry: CGEntry) {
            let axTitle = element.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
            snap.windows.append(WindowInfo(
                id: id, pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                appName: app.localizedName ?? app.bundleIdentifier ?? "App",
                title: axTitle.isEmpty ? entry.name : axTitle,
                bounds: entry.bounds, layer: entry.layer,
                isMinimized: element.map { AX.bool($0, kAXMinimizedAttribute) } ?? false,
                isOnScreen: entry.onScreen,
                isMain: element.map { AX.bool($0, kAXMainAttribute) } ?? false,
                isAppHidden: app.isHidden))
            if let element { snap.elements[id] = element }
        }

        var unresponsive: Set<pid_t> = []
        for app in apps {
            guard let elements = AX.windows(of: AX.application(app.processIdentifier)) else {
                unresponsive.insert(app.processIdentifier)
                continue
            }
            for element in elements {
                let id = AX.windowID(element)
                guard id != 0, snap.elements[id] == nil, let entry = entries[id] else { continue }
                add(id, element: element, app: app, entry: entry)
            }
        }
        for (id, element) in cachedElements where snap.elements[id] == nil {
            guard let entry = entries[id], !unresponsive.contains(entry.pid), let app = appByPID[entry.pid] else { continue }
            add(id, element: element, app: app, entry: entry)
        }
        // Scan for elements of other-Space windows still missing one. Hits land in the
        // FocusTracker cache and misses in `unresolved`, so each window is scanned for once.
        // With Screen Recording, untitled entries are helper strips, not windows: skip them.
        let titlesKnown = Permissions.screenRecording
        var missing: [pid_t: Set<CGWindowID>] = [:]
        for id in snap.zOrder where snap.elements[id] == nil && !unresolved.contains(id) {
            guard let entry = entries[id], entry.layer == 0, !entry.onScreen, !titlesKnown || !entry.name.isEmpty,
                  entry.bounds.width >= EligibilityFilter.minimumEdge, entry.bounds.height >= EligibilityFilter.minimumEdge,
                  !unresponsive.contains(entry.pid), appByPID[entry.pid] != nil,
                  !Spaces.isAvailable || Spaces.isOnOtherSpace(id) else { continue }
            missing[entry.pid, default: []].insert(id)
        }
        snap.unresolved = unresolved.filter { entries[$0] != nil }
        for (pid, wanted) in missing {
            guard let app = appByPID[pid] else { continue }
            let found = AX.windowElements(pid: pid, wanted: wanted)
            for (id, element) in found {
                if let entry = entries[id] { add(id, element: element, app: app, entry: entry) }
            }
            snap.unresolved.formUnion(wanted.subtracting(found.keys))
        }

        let seen = Set(snap.windows.map(\.id))
        for id in snap.zOrder where !seen.contains(id) {
            // Windows AX never showed us: on-screen windows of a busy app, and other-Space windows.
            // The title (CGWindowList has titles only with Screen Recording) and the Space check
            // keep out helper windows and closed windows an app keeps alive off screen.
            guard let entry = entries[id], entry.layer == 0, let app = appByPID[entry.pid], !app.isHidden else { continue }
            let busyAndVisible = entry.onScreen && unresponsive.contains(entry.pid)
            let elsewhere = !entry.name.isEmpty && !entry.onScreen && Spaces.isAvailable && Spaces.isOnOtherSpace(id)
            guard busyAndVisible || elsewhere else { continue }
            // Without Screen Recording a busy app's windows have no CG title: show the app name
            // and let the size filter keep helper windows out.
            let named = entry.name.isEmpty
                ? CGEntry(pid: entry.pid, layer: entry.layer, bounds: entry.bounds, onScreen: entry.onScreen,
                          name: app.localizedName ?? "Window")
                : entry
            add(id, element: nil, app: app, entry: named)
        }

        Logger.windows.debug("Snapshot: \(snap.windows.count) windows, \(snap.elements.count) with AX elements (\(cachedElements.count) cached)")
        if let front = NSWorkspace.shared.frontmostApplication,
           let focused = AX.element(AX.application(front.processIdentifier), kAXFocusedWindowAttribute) {
            let id = AX.windowID(focused)
            if id != 0 { snap.focusedID = id }
        }
        return snap
    }
}
