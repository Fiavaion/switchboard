import AppKit
import Combine
import SwitchboardCore
import os

/// Observable state the switcher panel renders.
final class SwitcherModel: ObservableObject {
    @Published var state = SwitcherState(windows: [])
    @Published var thumbnails: [CGWindowID: CGImage] = [:]
    @Published var tileWidth: Double = 200
    @Published var columns = 1
    var icons: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        icons[pid] = icon
        return icon
    }

    static func accessibilityLabel(for w: WindowInfo) -> String {
        var label = w.title.isEmpty ? w.appName : "\(w.title), \(w.appName)"
        if w.isMinimized { label += ", minimised" }
        if w.isAppHidden { label += ", hidden" }
        return label
    }
}

/// PRD F1 — the trigger-modifier + Tab state machine.
///
/// While the switcher is active every key event is swallowed; releasing the trigger modifier
/// commits. Enumeration runs off the main thread so the tap callback returns at once. Tabs that
/// arrive before the list is ready are replayed when it lands. A release before then ends the
/// active state at once, so the keyboard is never held, and the switch completes when the list
/// arrives: a quick Cmd+Tab goes to the previous window without the panel ever appearing.
final class SwitcherController {
    let model = SwitcherModel()
    private let store: SettingsStore
    private let focus: FocusTracker
    private let thumbnailer = Thumbnailer()
    private lazy var panel = SwitcherPanel(model: model, onPick: { [weak self] index in self?.pick(index) })
    private let enumerateQueue = DispatchQueue(label: "com.fiavaion.switchboard.enumerate", qos: .userInteractive)
    /// Separate from `enumerateQueue` so an open never waits behind a prewarm.
    private let prewarmQueue = DispatchQueue(label: "com.fiavaion.switchboard.prewarm", qos: .utility)
    private var prewarming = false

    private(set) var isActive = false
    private var generation = 0
    private var snapshot = WindowSnapshot()
    private var loaded = false
    private var pendingSteps = 0
    /// Released before the list loaded: switch when it lands, unless it lands too late to be
    /// the obvious consequence of the key press.
    private var pendingCommitSince: Date?
    private static let pendingCommitLimit: TimeInterval = 0.3
    private var openedAt = Date()
    private var mouseMonitor: Any?
    private var thumbnailTask: Task<Void, Never>?

    init(store: SettingsStore, focus: FocusTracker) {
        self.store = store
        self.focus = focus
    }

    private var trigger: CGEventFlags {
        store.settings.triggerModifier == .command ? .maskCommand : .maskAlternate
    }

    /// Event-tap entry point (main thread). Returns true to swallow.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        if !isActive {
            if pendingCommitSince != nil, type == .keyDown, key == KeyCode.escape {
                cancelPending()                                     // Esc right after a quick release: don't switch
                return false
            }
            guard type == .keyDown || type == .keyUp, key == KeyCode.tab, isTriggerOnly(flags) else { return false }
            if type == .keyDown { open(backwards: flags.contains(.maskShift)) }
            return true
        }

        // Safety net: never hold the keyboard once the modifier is gone, even if its release was missed.
        guard flags.contains(trigger) else {
            commit()
            return false
        }
        switch type {
        case .flagsChanged: return false
        case .keyUp: return true
        case .keyDown: break
        default: return false
        }
        switch key {
        case KeyCode.tab: flags.contains(.maskShift) ? step(-1) : step(1)
        case KeyCode.left: step(-1)
        case KeyCode.right: step(1)
        case KeyCode.up: step(-model.columns)
        case KeyCode.down: step(model.columns)
        case KeyCode.escape: cancel()
        case KeyCode.returnKey, KeyCode.keypadEnter: commit()
        case KeyCode.delete:
            if !model.state.query.isEmpty { updateQuery(String(model.state.query.dropLast())) }
        default:
            if let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
               !chars.isEmpty, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                updateQuery(model.state.query + chars)
            }
        }
        return true
    }

    /// Trigger modifier held, optionally with Shift, and nothing else.
    private func isTriggerOnly(_ flags: CGEventFlags) -> Bool {
        let relevant = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
        return relevant == trigger
    }

    // MARK: Lifecycle

    /// Fills the AX element cache in the background (launch, Space changes), so opening the
    /// switcher never waits on the element scan for windows on other Spaces.
    func prewarm() {
        guard !prewarming else { return }
        prewarming = true
        let cached = focus.elements, unresolved = focus.unresolved
        prewarmQueue.async { [weak self] in
            let snap = WindowEnumerator.snapshot(cachedElements: cached, unresolved: unresolved)
            DispatchQueue.main.async {
                self?.prewarming = false
                self?.focus.merge(snap)
                Logger.windows.info("Prewarmed \(snap.elements.count) of \(snap.windows.count) windows with AX elements")
            }
        }
    }

    private func open(backwards: Bool) {
        removeMouseMonitor()
        isActive = true
        generation += 1
        loaded = false
        pendingSteps = 0
        pendingCommitSince = nil
        openedAt = Date()
        let gen = generation
        let cached = focus.elements, unresolved = focus.unresolved
        enumerateQueue.async { [weak self] in
            let snap = WindowEnumerator.snapshot(cachedElements: cached, unresolved: unresolved)
            DispatchQueue.main.async { self?.present(snap, backwards: backwards, generation: gen) }
        }
    }

    private func present(_ snap: WindowSnapshot, backwards: Bool, generation gen: Int) {
        guard gen == generation, isActive || pendingCommitSince != nil else { return }
        snapshot = snap
        focus.merge(snap)
        if let focused = snap.focusedID { focus.record(focused, element: snap.elements[focused]) }
        let settings = store.settings
        let filter = EligibilityFilter(settings: settings)
        let windows = focus.mru.ordered(snap.windows.filter(filter.isEligible), zOrder: snap.zOrder)
        var state = SwitcherState(windows: windows, backwards: backwards, focusedID: snap.focusedID)
        state.move(by: pendingSteps)
        model.state = state
        loaded = true
        let ms = Int(Date().timeIntervalSince(openedAt) * 1000)
        Logger.switcher.info("Switcher ready in \(ms) ms with \(windows.count) of \(snap.windows.count) windows")
        removeMouseMonitor()
        if let since = pendingCommitSince {
            pendingCommitSince = nil
            if Date().timeIntervalSince(since) <= Self.pendingCommitLimit {
                activate(model.state.selected)
            } else {
                Logger.switcher.info("Window list arrived \(Int(Date().timeIntervalSince(since) * 1000)) ms after release; not switching")
            }
            return
        }

        model.tileWidth = settings.thumbnailSize.tileWidth(windowCount: windows.count)
        model.thumbnails = [:]
        if Permissions.screenRecording {
            for w in windows { if let img = thumbnailer.cached(w.id) { model.thumbnails[w.id] = img } }
            thumbnailTask = thumbnailer.refresh(windows.filter { !$0.isMinimized }.map(\.id), width: model.tileWidth) { [weak self] id, image in
                guard let self, self.isActive, gen == self.generation else { return }
                self.model.thumbnails[id] = image
            }
        }
        guard let screen = Self.screenWithMouse() else { return }
        panel.show(on: screen)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.cancel()                                      // F1.4: click outside cancels
        }
        announceSelection()
    }

    private func step(_ delta: Int) {
        guard loaded else { pendingSteps += delta; return }
        model.state.move(by: delta)
        announceSelection()
    }

    private func updateQuery(_ q: String) {
        guard loaded else { return }
        model.state.setQuery(q)
        announceSelection()
    }

    private func pick(_ index: Int) {
        guard isActive, loaded else { return }
        model.state.select(index: index)
        commit()
    }

    func commit() {
        guard isActive else { return }
        guard loaded else {
            // Released before the list arrived: stop capturing keys now, switch when it lands
            // unless Esc (see handle) or a click says otherwise first.
            pendingCommitSince = Date()
            isActive = false
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.cancelPending()
            }
            return
        }
        let target = model.state.selected
        close()
        activate(target)
    }

    /// Called after the event tap was disabled and re-enabled: a release may have been missed,
    /// possibly long ago, so cancel rather than switch late.
    func resyncModifiers() {
        guard isActive, !CGEventSource.flagsState(.combinedSessionState).contains(trigger) else { return }
        Logger.switcher.info("Trigger released while the tap was disabled; cancelling")
        cancel()
    }

    private func activate(_ target: WindowInfo?) {
        guard let target else { return }
        let element = snapshot.elements[target.id]
        focus.record(target.id, element: element)
        Logger.switcher.info("Activating window \(target.id) (\(target.appName, privacy: .public))")
        WindowActivator.activate(target, element: element)
    }

    func cancel() {
        guard isActive else { return }
        close()
        Logger.switcher.info("Switcher cancelled")
    }

    private func close() {
        isActive = false
        pendingCommitSince = nil
        generation += 1
        thumbnailTask?.cancel()
        thumbnailTask = nil
        removeMouseMonitor()
        panel.hide()
    }

    private func cancelPending() {
        pendingCommitSince = nil
        removeMouseMonitor()
        Logger.switcher.info("Pending switch cancelled")
    }

    private func removeMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    // MARK: Helpers

    private func announceSelection() {
        guard let w = model.state.selected else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: SwitcherModel.accessibilityLabel(for: w),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
