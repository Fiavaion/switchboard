import AppKit
import os

enum KeyCode {
    static let tab: Int64 = 48
    static let returnKey: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let escape: Int64 = 53
    static let delete: Int64 = 51
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
    static let three: Int64 = 20
    static let four: Int64 = 21
}

/// One session-level CGEvent tap for every shortcut Switchboard owns (Cmd+Tab, Cmd+Shift+3/4).
/// It must sit ahead of the Dock and the screenshot hotkeys, so it is a filtering tap
/// (`.defaultTap`) at `.headInsertEventTap`; verified to swallow both on macOS 26.6 (RESEARCH §2).
/// Requires Accessibility. The callback runs on the main run loop and must return quickly.
final class EventTap {
    /// Return true to swallow the event.
    var onEvent: ((CGEventType, CGEvent) -> Bool)?
    /// The system disabled the tap for a while; events (e.g. a modifier release) may have been missed.
    var onReenabled: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: eventTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Logger.input.error("CGEvent.tapCreate failed — Accessibility not granted?")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        self.source = source
        Logger.input.info("Event tap live")
        return true
    }

    /// Removes the tap entirely (Accessibility revoked); `start()` can create a new one later.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        Logger.input.info("Event tap removed")
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system disables a tap whose callback is slow; turn it straight back on.
            Logger.input.error("Event tap disabled (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onReenabled?()
            return Unmanaged.passUnretained(event)
        }
        return onEvent?(type, event) == true ? nil : Unmanaged.passUnretained(event)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
