import Foundation

/// PRD F1.2 / M3 search — what the switcher panel shows and which entry is selected.
public struct SwitcherState: Equatable {
    public private(set) var all: [WindowInfo]
    public private(set) var query = ""
    public private(set) var visible: [WindowInfo]
    public private(set) var selectedIndex: Int

    /// `backwards` = opened with Shift held: start on the last entry, like Windows Alt+Shift+Tab.
    /// `focusedID` is the window already in front; the first Tab skips it only when it is
    /// actually entry 0 (it may be excluded, or be Switchboard's own window).
    public init(windows: [WindowInfo], backwards: Bool = false, focusedID: UInt32? = nil) {
        all = windows
        visible = windows
        selectedIndex = Self.initialIndex(count: windows.count, backwards: backwards,
                                          frontIsFocused: focusedID != nil && windows.first?.id == focusedID)
    }

    public var selected: WindowInfo? { visible.indices.contains(selectedIndex) ? visible[selectedIndex] : nil }

    /// Moves the selection, wrapping: ±1 for Tab and Left/Right, ±columns for Up/Down.
    public mutating func move(by delta: Int) {
        guard !visible.isEmpty else { return }
        let n = visible.count
        selectedIndex = ((selectedIndex + delta) % n + n) % n
    }

    public mutating func select(index: Int) {
        if visible.indices.contains(index) { selectedIndex = index }
    }

    /// Filters live; the best (most recent) match is selected.
    public mutating func setQuery(_ q: String) {
        query = q
        visible = all.filter { Self.matches($0, query: q) }
        selectedIndex = 0
    }

    /// Every whitespace-separated term must appear in the title or app name,
    /// ignoring case and diacritics.
    public static func matches(_ w: WindowInfo, query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let haystack = "\(w.title) \(w.appName)"
        return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// When entry 0 is the window already in front, the first Tab lands on the previous one.
    static func initialIndex(count: Int, backwards: Bool, frontIsFocused: Bool) -> Int {
        guard count > 1 else { return 0 }
        if backwards { return count - 1 }
        return frontIsFocused ? 1 : 0
    }
}

public extension Settings.ThumbnailSize {
    /// Tile width in points. `auto` shrinks as the window count grows so the panel stays on screen.
    func tileWidth(windowCount: Int) -> Double {
        switch self {
        case .small: return 140
        case .medium: return 200
        case .large: return 280
        case .auto:
            switch windowCount {
            case ...6: return 280
            case ...15: return 200
            default: return 140
            }
        }
    }
}
