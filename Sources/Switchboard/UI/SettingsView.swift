import AppKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// PRD F4 (plus F2.3–F2.5 and F5.2) — the settings window.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(store: store).padding(12).tabItem { Label("General", systemImage: "gearshape") }
            ExclusionsTab(store: store).padding(12).tabItem { Label("Exclusions", systemImage: "nosign") }
            ScreenshotsTab(store: store).padding(12).tabItem { Label("Screenshots", systemImage: "camera.viewfinder") }
            BackupTab(store: store).padding(12).tabItem { Label("Backup", systemImage: "square.and.arrow.up.on.square") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(20)
        .frame(width: 540, height: 420)
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("Switcher shortcut", selection: $store.settings.triggerModifier) {
                Text("⌘ Command-Tab").tag(Settings.TriggerModifier.command)
                Text("⌥ Option-Tab").tag(Settings.TriggerModifier.option)
            }
            .pickerStyle(.radioGroup)
            Toggle("Show minimised windows", isOn: $store.settings.showMinimizedWindows)
            Toggle("Show windows of hidden apps", isOn: $store.settings.showHiddenApps)
            Toggle("Show windows on other Spaces", isOn: $store.settings.showOtherSpaces)
            Picker("Preview size", selection: $store.settings.thumbnailSize) {
                Text("Small").tag(Settings.ThumbnailSize.small)
                Text("Medium").tag(Settings.ThumbnailSize.medium)
                Text("Large").tag(Settings.ThumbnailSize.large)
                Text("Automatic").tag(Settings.ThumbnailSize.auto)
            }
            .pickerStyle(.segmented)
            Toggle("Open at login", isOn: $store.settings.launchAtLogin)
            if let error = store.launchAtLoginError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Show menu bar icon", isOn: $store.settings.showStatusItem)
            if !store.settings.showStatusItem {
                Text("To get back here, open Switchboard again from Finder or Spotlight.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ExclusionsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Windows from these apps never appear in the switcher.").foregroundStyle(.secondary)
            List {
                ForEach(store.settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        Text(Self.name(for: id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { store.settings.excludedBundleIDs.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(Self.name(for: id))")
                    }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Menu("Add Running App") {
                    ForEach(runningApps, id: \.self) { id in
                        Button(Self.name(for: id)) { add(id) }
                    }
                }
                .fixedSize()
                Button("Add App…", action: chooseApp)
            }
        }
    }

    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !store.settings.excludedBundleIDs.contains($0) && $0 != Bundle.main.bundleIdentifier }
            .sorted { Self.name(for: $0).localizedCaseInsensitiveCompare(Self.name(for: $1)) == .orderedAscending }
    }

    private func add(_ id: String) {
        if !store.settings.excludedBundleIDs.contains(id) { store.settings.excludedBundleIDs.append(id) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

private struct ScreenshotsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var systemTargetsClipboard = SystemScreenshotDefaults.targetsClipboard

    var body: some View {
        Form {
            Text("⌘⇧3 copies the whole screen and ⌘⇧4 a selection to the clipboard.")
                .foregroundStyle(.secondary)
            Toggle("Show “Copied to clipboard” confirmation", isOn: $store.settings.showScreenshotHUD)
            Toggle("Also save each screenshot to a folder", isOn: $store.settings.screenshotSaveToFolder)
            HStack {
                Text(store.settings.screenshotFolder).lineLimit(1).truncationMode(.middle)
                Button("Choose…", action: chooseFolder)
            }
            .disabled(!store.settings.screenshotSaveToFolder)

            Section("When Switchboard isn’t running") {
                Text(systemTargetsClipboard
                     ? "macOS screenshots go to the clipboard."
                     : "macOS screenshots are saved as files.")
                Button(systemTargetsClipboard ? "Go Back to Saving Files" : "Make Clipboard Screenshots Permanent") {
                    SystemScreenshotDefaults.setTargetsClipboard(!systemTargetsClipboard)
                    systemTargetsClipboard = SystemScreenshotDefaults.targetsClipboard
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.screenshotFolder = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

private struct BackupTab: View {
    @ObservedObject var store: SettingsStore
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your settings as JSON, or load them on another Mac.").foregroundStyle(.secondary)
            HStack {
                Button("Export Settings…", action: exportSettings)
                Button("Import Settings…", action: importSettings)
            }
            if !status.isEmpty {
                Text(status).font(.callout).accessibilityAddTraits(.updatesFrequently)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Switchboard Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            status = "Exported to \(url.lastPathComponent)."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importSettings(from: url)
            status = "Imported \(url.lastPathComponent)."
        } catch {
            status = "That file isn’t a Switchboard settings file (\(error.localizedDescription))."
        }
    }
}
