import CoreGraphics  // LESSON-BUILD-001: CGRect.width/height live in CoreGraphics, not Foundation
import Foundation

/// Minimal, AppKit-free model of a window. Populated by the app target from AX + CGWindowList.
public struct WindowInfo: Identifiable, Equatable {
    public let id: UInt32          // CGWindowID
    public let pid: Int32
    public let bundleID: String?
    public let appName: String
    public let title: String
    public let bounds: CGRect
    public let layer: Int
    public let isMinimized: Bool
    public let isOnScreen: Bool
    /// The app reports this window as its main window (kAXMainAttribute).
    public let isMain: Bool
    /// The owning app is hidden (Cmd+H).
    public let isAppHidden: Bool

    public init(id: UInt32, pid: Int32, bundleID: String?, appName: String, title: String,
                bounds: CGRect, layer: Int, isMinimized: Bool, isOnScreen: Bool,
                isMain: Bool = false, isAppHidden: Bool = false) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.appName = appName
        self.title = title; self.bounds = bounds; self.layer = layer
        self.isMinimized = isMinimized; self.isOnScreen = isOnScreen
        self.isMain = isMain; self.isAppHidden = isAppHidden
    }
}

/// PRD F1.6 / F1.7 / F4.2 — pure eligibility filter, unit-tested.
public struct EligibilityFilter {
    /// Smallest window edge shown. Filters the invisible helper windows many apps keep at layer 0.
    public static let minimumEdge: CGFloat = 50

    public var excludedBundleIDs: Set<String>
    public var includeMinimized: Bool
    public var includeHiddenApps: Bool
    public var includeOtherSpaces: Bool

    public init(excludedBundleIDs: Set<String> = [], includeMinimized: Bool = true,
                includeHiddenApps: Bool = true, includeOtherSpaces: Bool = true) {
        self.excludedBundleIDs = excludedBundleIDs
        self.includeMinimized = includeMinimized
        self.includeHiddenApps = includeHiddenApps
        self.includeOtherSpaces = includeOtherSpaces
    }

    public init(settings: Settings) {
        self.init(excludedBundleIDs: Set(settings.excludedBundleIDs),
                  includeMinimized: settings.showMinimizedWindows,
                  includeHiddenApps: settings.showHiddenApps,
                  includeOtherSpaces: settings.showOtherSpaces)
    }

    public func isEligible(_ w: WindowInfo) -> Bool {
        if let b = w.bundleID, excludedBundleIDs.contains(b) { return false }
        if w.layer != 0 { return false }                       // normal window layer only
        if w.bounds.width < Self.minimumEdge || w.bounds.height < Self.minimumEdge { return false }
        if w.title.isEmpty && !w.isMain { return false }
        if w.isMinimized { return includeMinimized }
        if w.isAppHidden { return includeHiddenApps }
        if !w.isOnScreen { return includeOtherSpaces }
        return true
    }
}
