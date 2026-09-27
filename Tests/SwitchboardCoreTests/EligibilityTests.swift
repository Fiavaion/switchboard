import XCTest
@testable import SwitchboardCore

final class EligibilityTests: XCTestCase {
    func make(bundle: String? = "com.google.Chrome", title: String = "T", layer: Int = 0, w: CGFloat = 800,
              minimized: Bool = false, onScreen: Bool = true, main: Bool = false, hidden: Bool = false) -> WindowInfo {
        WindowInfo(id: 1, pid: 1, bundleID: bundle, appName: "Chrome", title: title,
                   bounds: CGRect(x: 0, y: 0, width: w, height: 600),
                   layer: layer, isMinimized: minimized, isOnScreen: onScreen, isMain: main, isAppHidden: hidden)
    }

    func testNormalWindowEligible() { XCTAssertTrue(EligibilityFilter().isEligible(make())) }
    func testExcludedBundle() { XCTAssertFalse(EligibilityFilter(excludedBundleIDs: ["com.google.Chrome"]).isEligible(make())) }
    func testNonZeroLayerRejected() { XCTAssertFalse(EligibilityFilter().isEligible(make(layer: 25))) }
    func testTinyWindowRejected() { XCTAssertFalse(EligibilityFilter().isEligible(make(w: 10))) }

    func testUntitledWindowNeedsToBeMain() {
        XCTAssertFalse(EligibilityFilter().isEligible(make(title: "")))
        XCTAssertTrue(EligibilityFilter().isEligible(make(title: "", main: true)))
    }

    func testMinimizedRespectsSetting() {
        XCTAssertTrue(EligibilityFilter(includeMinimized: true).isEligible(make(minimized: true, onScreen: false)))
        XCTAssertFalse(EligibilityFilter(includeMinimized: false).isEligible(make(minimized: true, onScreen: false)))
    }

    func testHiddenAppRespectsSetting() {
        XCTAssertTrue(EligibilityFilter(includeHiddenApps: true).isEligible(make(onScreen: false, hidden: true)))
        XCTAssertFalse(EligibilityFilter(includeHiddenApps: false).isEligible(make(onScreen: false, hidden: true)))
    }

    func testOtherSpaceRespectsSetting() {
        let w = make(onScreen: false)
        XCTAssertTrue(EligibilityFilter(includeOtherSpaces: true).isEligible(w))
        XCTAssertFalse(EligibilityFilter(includeOtherSpaces: false).isEligible(w))
    }

    func testFilterFromSettings() {
        var s = Settings()
        s.excludedBundleIDs = ["com.google.Chrome"]
        XCTAssertFalse(EligibilityFilter(settings: s).isEligible(make()))
    }
}
