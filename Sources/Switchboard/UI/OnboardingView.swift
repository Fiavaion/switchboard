import SwiftUI
import SwitchboardCore

/// PRD F3.2 — one window, one row per permission, each with status and a deep link.
struct OnboardingView: View {
    @ObservedObject var permissions: PermissionState
    @ObservedObject var store: SettingsStore
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Switchboard")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Switchboard needs your permission for two things. Grant them in System Settings; this window updates by itself.")
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(title: "Accessibility",
                          detail: "Required. Lets Switchboard take over the switcher shortcut and bring the exact window you pick to the front.",
                          granted: permissions.accessibility, kind: .accessibility)
            PermissionRow(title: "Screen Recording",
                          detail: "Optional. Shows live window previews and handles screenshots. Without it the switcher shows app icons and titles.",
                          granted: permissions.screenRecording, kind: .screenRecording)

            Divider()

            Picker("Switcher shortcut", selection: $store.settings.triggerModifier) {
                Text("⌘ Command-Tab (replaces the app switcher)").tag(Settings.TriggerModifier.command)
                Text("⌥ Option-Tab (leaves Command-Tab alone)").tag(Settings.TriggerModifier.option)
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let kind: Permissions.Kind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(title) — \(granted ? "Granted" : "Not granted")").bold()
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !granted {
                Button("Open System Settings") { Permissions.request(kind) }
                    .accessibilityLabel("Open System Settings for \(title)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
