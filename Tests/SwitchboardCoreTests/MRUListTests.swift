import XCTest
@testable import SwitchboardCore

final class MRUListTests: XCTestCase {
    func win(_ id: UInt32) -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: nil, appName: "A", title: "\(id)",
                   bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isMinimized: false, isOnScreen: true)
    }

    func testTouchMovesToFront() {
        var m = MRUList()
        m.touch(1); m.touch(2); m.touch(1)
        XCTAssertEqual(m.ids, [1, 2])
    }

    func testRecentFirstThenZOrder() {
        var m = MRUList()
        m.touch(3); m.touch(1)                               // 1 most recent, then 3
        let out = m.ordered([win(1), win(2), win(3), win(4)], zOrder: [4, 2, 3, 1])
        XCTAssertEqual(out.map(\.id), [1, 3, 4, 2])          // unseen 4, 2 follow z-order
    }

    func testUnknownToBothKeepsInputOrderAtEnd() {
        let out = MRUList().ordered([win(9), win(8), win(1)], zOrder: [1])
        XCTAssertEqual(out.map(\.id), [1, 9, 8])
    }

    func testPrune() {
        var m = MRUList(ids: [1, 2, 3])
        m.prune(keeping: [2])
        XCTAssertEqual(m.ids, [2])
    }
}
