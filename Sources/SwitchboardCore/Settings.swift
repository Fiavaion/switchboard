import Foundation

/// PRD F4 / D7 — every user setting. Each property is one flat UserDefaults key in the
/// `com.fiavaion.switchboard` domain (so `defaults write` works for golden images), and the
/// JSON export (F4.6) is the same flat object. Missing keys fall back to the defaults below.
public struct Settings: Codable, Equatable {
    public enum TriggerModifier: String, Codable, CaseIterable { case command, option }
    public enum ThumbnailSize: String, Codable, CaseIterable { case small, medium, large, auto }

    public var triggerModifier: TriggerModifier = .command
    public var showMinimizedWindows = true
    public var showHiddenApps = true
    public var showOtherSpaces = true
    public var excludedBundleIDs: [String] = []
    public var thumbnailSize: ThumbnailSize = .auto
    public var launchAtLogin = false
    public var screenshotSaveToFolder = false
    public var screenshotFolder = "~/Desktop"
    public var showScreenshotHUD = true
    public var showStatusItem = true

    public init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case triggerModifier, showMinimizedWindows, showHiddenApps, showOtherSpaces, excludedBundleIDs,
             thumbnailSize, launchAtLogin, screenshotSaveToFolder, screenshotFolder, showScreenshotHUD,
             showStatusItem
    }

    /// The UserDefaults / JSON key names, in declaration order.
    public static var keys: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        triggerModifier = try c.decodeIfPresent(TriggerModifier.self, forKey: .triggerModifier) ?? d.triggerModifier
        showMinimizedWindows = try c.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? d.showMinimizedWindows
        showHiddenApps = try c.decodeIfPresent(Bool.self, forKey: .showHiddenApps) ?? d.showHiddenApps
        showOtherSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOtherSpaces) ?? d.showOtherSpaces
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? d.excludedBundleIDs
        thumbnailSize = try c.decodeIfPresent(ThumbnailSize.self, forKey: .thumbnailSize) ?? d.thumbnailSize
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        screenshotSaveToFolder = try c.decodeIfPresent(Bool.self, forKey: .screenshotSaveToFolder) ?? d.screenshotSaveToFolder
        screenshotFolder = try c.decodeIfPresent(String.self, forKey: .screenshotFolder) ?? d.screenshotFolder
        showScreenshotHUD = try c.decodeIfPresent(Bool.self, forKey: .showScreenshotHUD) ?? d.showScreenshotHUD
        showStatusItem = try c.decodeIfPresent(Bool.self, forKey: .showStatusItem) ?? d.showStatusItem
    }

    // MARK: JSON (F4.6)

    public func exportJSON() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func importJSON(_ data: Data) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: data)
    }

    // MARK: Flat key/value form (UserDefaults)

    /// Plist-compatible values keyed by setting name.
    public func dictionary() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: exportJSON()) as? [String: Any] ?? [:]
    }

    /// Builds settings from stored values key by key. Unknown keys are ignored; a known key
    /// with a wrong type (e.g. a hand-edited `defaults write` or MDM payload) keeps its default
    /// and is reported in `rejected`, so one bad key never resets the others.
    public static func from(dictionary: [String: Any]) -> (settings: Settings, rejected: [String]) {
        var accepted: [String: Any] = [:]
        var rejected: [String] = []
        for key in keys {
            guard let value = dictionary[key] else { continue }
            let single = [key: value]
            // LESSON-API-003: isValidJSONObject first: data(withJSONObject:) raises an uncatchable ObjC
            // exception for Date or Data values.
            guard JSONSerialization.isValidJSONObject(single),
                  let data = try? JSONSerialization.data(withJSONObject: single),
                  (try? importJSON(data)) != nil else {
                rejected.append(key)
                continue
            }
            accepted[key] = value
        }
        let settings = (try? JSONSerialization.data(withJSONObject: accepted)).flatMap { try? importJSON($0) } ?? Settings()
        return (settings, rejected)
    }
}
