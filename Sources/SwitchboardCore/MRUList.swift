/// PRD F1.1 — most-recently-used window order.
///
/// Windows the app has seen focused are ranked by recency; windows it never saw focused
/// (focused before launch, or never touched) follow in window-server z-order, front to back.
public struct MRUList: Equatable {
    public private(set) var ids: [UInt32] = []

    public init(ids: [UInt32] = []) { self.ids = ids }

    /// Record that a window was just focused.
    public mutating func touch(_ id: UInt32) {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
    }

    /// Forget windows that no longer exist.
    public mutating func prune(keeping live: Set<UInt32>) {
        ids.removeAll { !live.contains($0) }
    }

    /// Sort `windows` by recency, falling back to `zOrder` (front to back) for unseen windows.
    public func ordered(_ windows: [WindowInfo], zOrder: [UInt32]) -> [WindowInfo] {
        let recency = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let depth = Dictionary(zOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func rank(_ w: WindowInfo) -> (Int, Int) {
            if let r = recency[w.id] { return (0, r) }
            return (1, depth[w.id] ?? Int.max)
        }
        return windows.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }
}
