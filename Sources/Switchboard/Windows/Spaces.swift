import CoreGraphics
import Foundation

/// Which Spaces a window is on, through the private SkyLight calls AltTab and other window
/// managers use (read for understanding only). They are looked up at run time: if a macOS
/// release removes them, `isAvailable` goes false and callers fall back to public API only
/// (PRD §9 risk: "feature-flag the private path").
enum Spaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let mainConnection: MainConnection? = symbol("CGSMainConnectionID")
    private static let activeSpace: ActiveSpace? = symbol("CGSGetActiveSpace")
    private static let spacesForWindows: SpacesForWindows? = symbol("CGSCopySpacesForWindows")

    static var isAvailable: Bool { mainConnection != nil && activeSpace != nil && spacesForWindows != nil }

    /// True when the window belongs to a Space other than the current one. False for windows on
    /// no Space at all, such as closed windows an app keeps alive off screen.
    static func isOnOtherSpace(_ id: CGWindowID) -> Bool {
        guard let mainConnection, let activeSpace, let spacesForWindows else { return false }
        let cid = mainConnection()
        let allSpaces: Int32 = 0x7
        guard let spaces = spacesForWindows(cid, allSpaces, [NSNumber(value: id)] as CFArray)?
            .takeRetainedValue() as? [NSNumber], !spaces.isEmpty else { return false }
        let active = activeSpace(cid)
        return !spaces.contains { $0.uint64Value == active }
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
