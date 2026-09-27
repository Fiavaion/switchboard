import ApplicationServices
import Foundation

// Private, but stable since 10.x and the only way to map an AX window to its CGWindowID
// (needed for z-order, thumbnails and MRU identity). Used the same way by AltTab (GPL,
// read for understanding only) and other window managers. RESEARCH §2.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin typed wrappers over the AX C API.
enum AX {
    private typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    /// Private; looked up at run time so its removal degrades to "not found" instead of a crash.
    private static let createWithRemoteToken: CreateWithRemoteToken? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(sym, to: CreateWithRemoteToken.self)
    }()
    /// Every real window seen on macOS 26 had an element ID below 1,000 (Chrome's highest: 475).
    private static let elementIDLimit: UInt64 = 1000

    /// Upper bound on a read while enumerating, so one hung app cannot stall the switcher.
    /// LESSON-API-002: a timeout applies only to the element it is set on, so every element handed out gets it.
    static let readTimeout: Float = 0.2
    /// Raising can legitimately take ~0.3 s (Safari); see `WindowActivator`.
    static let actionTimeout: Float = 0.5

    static func application(_ pid: pid_t) -> AXUIElement {
        bounded(AXUIElementCreateApplication(pid))
    }

    @discardableResult
    static func bounded(_ element: AXUIElement, _ seconds: Float = readTimeout) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, seconds)
        return element
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : 0
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &v) == .success ? v : nil
    }

    /// nil when the app did not answer (hung or busy), as opposed to having no windows.
    /// LESSON-API-004: elements for windows that `kAXWindowsAttribute` omits (other Spaces, full screen in
    /// particular), found by addressing the app's AX elements directly: a remote token is
    /// (pid, 0, 'coco', element ID). The technique is the one AltTab uses (GPL; read for
    /// understanding only). Stops as soon as every wanted window is found; ~30 ms per full scan.
    static func windowElements(pid: pid_t, wanted: Set<CGWindowID>) -> [CGWindowID: AXUIElement] {
        guard let create = createWithRemoteToken, !wanted.isEmpty else { return [:] }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes {
            $0.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            $0.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)   // 'coco'
        }
        var found: [CGWindowID: AXUIElement] = [:]
        for elementID in 0..<elementIDLimit {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            var id: CGWindowID = 0
            let result = _AXUIElementGetWindow(bounded(element), &id)
            if result == .cannotComplete { break }              // app went busy: give up, don't stall
            guard result == .success, wanted.contains(id), found[id] == nil,
                  // Child elements (groups, buttons) report their window's id too; only the window will raise.
                  string(element, kAXRoleAttribute) == kAXWindowRole else { continue }
            found[id] = element
            if found.count == wanted.count { break }
        }
        return found
    }

    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        var v: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
        if result == .noValue { return [] }
        guard result == .success else { return nil }
        return (v as? [AXUIElement] ?? []).map { bounded($0) }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (value(element, attribute) as? Bool) ?? false
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return bounded(v as! AXUIElement)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}
