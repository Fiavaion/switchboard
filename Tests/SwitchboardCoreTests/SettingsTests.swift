import XCTest
@testable import SwitchboardCore

final class SettingsTests: XCTestCase {
    func testJSONRoundTrip() throws {
        var s = Settings()
        s.triggerModifier = .option
        s.excludedBundleIDs = ["com.apple.finder"]
        s.thumbnailSize = .large
        s.screenshotSaveToFolder = true
        XCTAssertEqual(try Settings.importJSON(s.exportJSON()), s)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let s = try Settings.importJSON(Data(#"{"triggerModifier":"option"}"#.utf8))
        var expected = Settings()
        expected.triggerModifier = .option
        XCTAssertEqual(s, expected)
    }

    func testExportIsFlatWithEveryKey() throws {
        let obj = try JSONSerialization.jsonObject(with: Settings().exportJSON()) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), Set(Settings.keys))
    }

    func testDictionaryRoundTripIgnoresUnknownKeys() throws {
        var s = Settings()
        s.showOtherSpaces = false
        var d = try s.dictionary()
        d["NSWindow Frame Settings"] = "0 0 10 10"          // UserDefaults carries foreign keys too
        let loaded = Settings.from(dictionary: d)
        XCTAssertEqual(loaded.settings, s)
        XCTAssertEqual(loaded.rejected, [])
    }

    func testMalformedValueThrowsOnImport() {
        XCTAssertThrowsError(try Settings.importJSON(Data(#"{"thumbnailSize":"huge"}"#.utf8)))
    }

    func testBadStoredKeyKeepsTheOthers() {
        let loaded = Settings.from(dictionary: [
            "triggerModifier": "cmd",                        // not a valid case
            "screenshotFolder": Date(),                      // would crash JSONSerialization
            "showHiddenApps": false,
        ])
        XCTAssertEqual(Set(loaded.rejected), ["triggerModifier", "screenshotFolder"])
        XCTAssertFalse(loaded.settings.showHiddenApps)
        XCTAssertEqual(loaded.settings.triggerModifier, .command)
        XCTAssertEqual(loaded.settings.screenshotFolder, "~/Desktop")
    }
}
