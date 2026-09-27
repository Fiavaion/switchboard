import AppKit
import Combine
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let onboardingShownKey = "onboardingShown"

    private let store = SettingsStore()
    private let permissions = PermissionState()
    private let focus = FocusTracker()
    private let tap = EventTap()
    private let hud = HUD()
    private let presenter = WindowPresenter()
    private lazy var switcher = SwitcherController(store: store, focus: focus)
    private lazy var screenshots = ScreenshotController(store: store, hud: hud)
    private var statusItem: StatusItemController!
    private var subscriptions: Set<AnyCancellable> = []
    private var spaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(onSettings: { [weak self] in self?.showSettings() },
                                          onPermissions: { [weak self] in self?.showOnboarding() })
        statusItem.isVisible = store.settings.showStatusItem
        tap.onEvent = { [unowned self] type, event in
            screenshots.handle(type, event) || switcher.handle(type, event)
        }
        tap.onReenabled = { [unowned self] in switcher.resyncModifiers() }
        Logger.app.info("Switchboard launched. AX trusted: \(self.permissions.accessibility), screen capture: \(self.permissions.screenRecording)")

        permissions.$accessibility
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in granted ? self?.startInput() : self?.stopInput() }
            .store(in: &subscriptions)
        store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in self?.statusItem.isVisible = settings.showStatusItem }
            .store(in: &subscriptions)
        store.$settings
            .map(\.launchAtLogin)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.store.applyLaunchAtLogin() }
            .store(in: &subscriptions)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.permissions.refresh()                          // F3.4
        }
        // Posted when any app's Accessibility grant changes; the TCC write lands a moment later.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.permissions.refresh() }
        }

        if !permissions.accessibility || !UserDefaults.standard.bool(forKey: Self.onboardingShownKey) {
            showOnboarding()
        }
    }

    /// Relaunching the app (Finder, Spotlight, `open`) opens Settings — the way back when the
    /// menu bar icon is hidden (F5.2).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func startInput() {
        guard !tap.isRunning else { return }
        guard tap.start() else { return }
        focus.start()
        switcher.prewarm()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.switcher.prewarm() }
    }

    /// Accessibility was revoked: release the keyboard now rather than leave a dead tap in place.
    private func stopInput() {
        switcher.cancel()
        tap.stop()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }

    private func showOnboarding() {
        permissions.refresh()
        permissions.startPolling()
        presenter.show(id: "onboarding", title: "Switchboard", onClose: { [weak self] in
            self?.permissions.stopPolling()
            UserDefaults.standard.set(true, forKey: Self.onboardingShownKey)
        }) {
            OnboardingView(permissions: permissions, store: store) { [weak self] in
                self?.presenter.close(id: "onboarding")
            }
        }
    }

    private func showSettings() {
        presenter.show(id: "settings", title: "Switchboard Settings") { SettingsView(store: store) }
    }
}
