import AppKit
import ApplicationServices
import Combine
import os

/// The only place permission state is read or requested (CLAUDE.md convention). PRD F3.
enum Permissions {
    enum Kind {
        case accessibility, screenRecording

        var settingsURL: URL {
            switch self {
            case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .screenRecording: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            }
        }
    }

    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds Switchboard to the relevant System Settings list, then opens that pane.
    static func request(_ kind: Kind) {
        switch kind {
        case .accessibility:
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        NSWorkspace.shared.open(kind.settingsURL)
    }
}

/// Observable permission state for the onboarding window (F3.2) and for starting input once
/// Accessibility arrives. Re-checked on app activation and, only while onboarding is on
/// screen, once a second (F3.4) — never while idle (N1).
final class PermissionState: ObservableObject {
    @Published private(set) var accessibility = Permissions.accessibility
    @Published private(set) var screenRecording = Permissions.screenRecording
    private var timer: Timer?

    func refresh() {
        let ax = Permissions.accessibility, sr = Permissions.screenRecording
        if ax != accessibility { accessibility = ax; Logger.app.info("Accessibility permission: \(ax)") }
        if sr != screenRecording { screenRecording = sr; Logger.app.info("Screen Recording permission: \(sr)") }
    }

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
