import AppKit
import Combine
import ServiceManagement
import SwitchboardCore
import os

/// PRD D7 / F4 — persists `Settings` as flat keys in UserDefaults (`com.fiavaion.switchboard`).
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet { if settings != oldValue { save() } }
    }
    @Published private(set) var launchAtLoginError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Settings.from(dictionary: defaults.dictionaryRepresentation())
        settings = loaded.settings
        if !loaded.rejected.isEmpty {
            Logger.settings.error("Ignored malformed settings (defaults used): \(loaded.rejected.joined(separator: ", "), privacy: .public)")
        }
    }

    private func save() {
        do {
            for (key, value) in try settings.dictionary() { defaults.set(value, forKey: key) }
        } catch {
            Logger.settings.error("Saving settings failed: \(error.localizedDescription)")
        }
    }

    // MARK: F4.6 JSON export / import

    func export(to url: URL) throws {
        try settings.exportJSON().write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) throws {
        settings = try Settings.importJSON(Data(contentsOf: url))
    }

    // MARK: F4.5 launch at login

    /// Brings the login item in line with the setting; called at launch and on every change.
    func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin, service.status != .enabled {
                try service.register()
            } else if !settings.launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
            launchAtLoginError = service.status == .requiresApproval
                ? "Approve Switchboard in System Settings → General → Login Items." : nil
        } catch {
            Logger.settings.error("Launch at login failed: \(error.localizedDescription)")
            launchAtLoginError = error.localizedDescription
        }
    }
}
