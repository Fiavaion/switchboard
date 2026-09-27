import XCTest
@testable import SwitchboardCore

final class SwitcherStateTests: XCTestCase {
    func win(_ id: UInt32, _ title: String, app: String = "Safari") -> WindowInfo {
        WindowInfo(id: id, pid: 1, bundleID: nil, appName: app, title: title,
                   bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isMinimized: false, isOnScreen: true)
    }
    lazy var three = [win(1, "Inbox", app: "Mail"), win(2, "Café menu"), win(3, "PRD.md — switchboard", app: "Code")]

    func testFirstTabSelectsPreviousWindow() { XCTAssertEqual(SwitcherState(windows: three, focusedID: 1).selected?.id, 2) }
    func testFocusedWindowNotListedStartsAtMostRecent() {
        XCTAssertEqual(SwitcherState(windows: three, focusedID: 99).selected?.id, 1)   // e.g. Settings or excluded app in front
        XCTAssertEqual(SwitcherState(windows: three).selected?.id, 1)
    }
    func testShiftTabStartsAtEnd() { XCTAssertEqual(SwitcherState(windows: three, backwards: true).selected?.id, 3) }
    func testSingleWindowSelectsIt() { XCTAssertEqual(SwitcherState(windows: [win(7, "x")]).selected?.id, 7) }
    func testEmpty() { XCTAssertNil(SwitcherState(windows: []).selected) }

    func testWraps() {
        var s = SwitcherState(windows: three, focusedID: 1)
        s.move(by: 1); XCTAssertEqual(s.selected?.id, 3)
        s.move(by: 1); XCTAssertEqual(s.selected?.id, 1)
        s.move(by: -1); XCTAssertEqual(s.selected?.id, 3)
    }

    func testSearchMatchesTitleAndAppIgnoringCaseAndAccents() {
        var s = SwitcherState(windows: three)
        s.setQuery("cafe"); XCTAssertEqual(s.visible.map(\.id), [2])
        s.setQuery("code prd"); XCTAssertEqual(s.visible.map(\.id), [3])
        s.setQuery("zzz"); XCTAssertTrue(s.visible.isEmpty); XCTAssertNil(s.selected)
        s.setQuery(""); XCTAssertEqual(s.visible.count, 3); XCTAssertEqual(s.selectedIndex, 0)
    }

    func testGridMoveWraps() {
        var s = SwitcherState(windows: three)             // selected index 0
        s.move(by: 2); XCTAssertEqual(s.selectedIndex, 2)
        s.move(by: 2); XCTAssertEqual(s.selectedIndex, 1)
        s.move(by: -4); XCTAssertEqual(s.selectedIndex, 0)
    }

    func testAutoThumbnailShrinksWithCount() {
        XCTAssertGreaterThan(Settings.ThumbnailSize.auto.tileWidth(windowCount: 3),
                             Settings.ThumbnailSize.auto.tileWidth(windowCount: 30))
        XCTAssertEqual(Settings.ThumbnailSize.medium.tileWidth(windowCount: 30), 200)
    }
}
