# RESEARCH.md — Switchboard

Background research for a self-built macOS window switcher + screenshot-to-clipboard utility.
Read this before PRD.md.

## 1. Problem statement

Moving a Windows-centred workflow to macOS exposes two friction points:

1. **Cmd+Tab switches apps, not windows.** Three Chrome profiles and several VS Code
   workspaces collapse into two entries. Reaching the right window is Cmd+Tab then Cmd+`
   (cycle within app), with no visual preview.
2. **Cmd+Shift+3/4 save files by default.** Getting an image into the clipboard is
   file → open → copy. macOS does support Cmd+Ctrl+Shift+3/4 and a clipboard default via
   `defaults write com.apple.screencapture target clipboard`, but the behaviour should be
   owned by the same tool so it survives reinstalls and is one install on every Mac.

Existing free option (AltTab, lwouis/alt-tab-macos, GPL-3) covers (1) but gates search,
icon/title styles, auto-sizing and extra shortcuts behind a paid tier. We want zero paywall,
zero telemetry, and a codebase we can extend.

## 2. Platform APIs (what's actually required)

| Need | API | Permission |
|---|---|---|
| Enumerate on-screen windows (id, owner PID, title, bounds, layer) | `CGWindowListCopyWindowInfo` | none |
| Raise/focus a specific window (not just the app) | `AXUIElement` (Accessibility): `kAXRaiseAction`, `kAXMainAttribute`, plus `NSRunningApplication.activate` | **Accessibility** |
| Minimised / hidden windows | `AXUIElement` `kAXMinimizedAttribute`, `NSRunningApplication.isHidden` | Accessibility |
| Window thumbnails | `ScreenCaptureKit` (`SCShareableContent`, `SCScreenshotManager`) on macOS 14+; `CGWindowListCreateImage` is deprecated | **Screen Recording** |
| Global hotkey that intercepts Cmd+Tab | `CGEvent.tapCreate` (`.cgSessionEventTap`, listen+filter) | Accessibility |
| Detect Cmd held / released | same event tap, `flagsChanged` | |
| Screenshot to clipboard | Shell out to `/usr/sbin/screencapture -c` (full) / `-ci` (interactive). Identical output to the system tool, no extra permission surface. | Screen Recording |
| Register Cmd+Shift+3/4 | (a) event tap swallow + `screencapture`, or (b) rewrite `com.apple.symbolichotkeys` keys 28–31. (a) is self-contained; (b) survives app quit. PRD chooses (a). For "make it permanent" (F2.5), setting `com.apple.screencapture target = clipboard` is enough: the plain Cmd+Shift+3/4 hotkeys then copy instead of saving, so the symbolic hotkeys are left alone. | |
| Spaces / multi-display | `NSScreen.screens`; per-Space window membership via private `CGSCopySpacesForWindows` (AltTab uses this). Public fallback: show windows whose bounds intersect a screen. | |
| Menu bar presence | `NSStatusItem`; `LSUIElement = true` in Info.plist (no Dock icon) | |
| Launch at login | `SMAppService.mainApp.register()` (macOS 13+) | |

Key constraint: **Cmd+Tab is owned by the Dock.** To take it over, the event tap must
swallow the keydown before the Dock sees it. This works reliably with a session-level
tap; it is what AltTab does. Fallback default binding is Option+Tab.

### Verified on macOS 26.6.2 (2026-09-26, Apple Silicon)

- A session tap (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`) sees and swallows
  **Cmd+Tab** (no Dock switcher appears) **and Cmd+Shift+3/4** (the system screenshot never
  fires; clipboard unchanged). Synthetic events posted at `.cghidEventTap` go through the same
  path, which is what `scripts/smoke/drive.swift` relies on.
- **Raising one window from a background app:** set the window's `kAXMainAttribute`, perform
  `kAXRaiseAction`, then set the app element's `kAXFrontmostAttribute`. This landed on the
  exact back-most Safari window, and on each of two VS Code windows, every time. It costs about
  260 ms against Safari and single-digit ms elsewhere. `NSRunningApplication.activate` is not
  used: macOS 14 cooperative activation refuses it from a non-active app.
- **AX → CGWindowID** needs the private `_AXUIElementGetWindow`, which has been stable since
  10.x. Everything else is public API.
- **Spaces:** `kAXWindowsAttribute` omits windows on other Spaces for some apps, full-screen
  windows in particular. `CGWindowListCopyWindowInfo(.optionAll)` still lists them, in
  window-server order, which tracks recency across Spaces. Activating the app first and hoping
  **fails** when the app has several full-screen windows (3 Chrome profiles, each on its own
  Space): macOS always lands on the app's most recent window. The fix is the private
  `_AXUIElementCreateWithRemoteToken`, which addresses an app's AX elements directly: a 20-byte
  token of pid, 0, `'coco'`, then the element ID. Scanning element IDs 0–999 takes 24–36 ms per
  app and found every window, full-screen ones included (the highest ID seen was 475, in Chrome).
  Raising those elements switches Space and lands on the exact window. Switchboard runs the scan
  in the background at launch and on each Space change, and caches the elements.
  `CGSCopySpacesForWindows` restricts the scan, and the CG-only fallback, to windows that really
  sit on another Space.
- **CGWindowList titles** (`kCGWindowName`) are empty without Screen Recording, while AX titles
  need only Accessibility. That makes AX the primary title source.
- **ScreenCaptureKit on macOS 15+** shows a system alert the first time `SCShareableContent` is
  used ("…requesting to bypass the system private window picker…"). The user must allow it,
  and macOS re-asks periodically. On managed Macs the Restrictions key
  `forceBypassScreenCaptureAlert` (macOS 15.1+) suppresses it; see `docs/DEPLOYMENT.md`.
  Windows on inactive full-screen Spaces don't capture, so their tiles fall back to the app
  icon (D6).
- **Secure Input** (a focused password field, some terminals' "Secure Keyboard Entry") hides
  keystrokes from every event tap, so while it is on, Cmd+Tab reaches the Dock as usual. This
  is a platform limit shared by every tap-based switcher.
- Dev builds must be signed with a stable certificate (`scripts/bundle.sh`). An ad-hoc
  signature's designated requirement is its cdhash, so every rebuild silently drops the TCC grants.

## 3. Language / toolchain decision

- **Swift 5.9+, AppKit + SwiftUI hybrid.** SwiftUI for the switcher panel and settings;
  AppKit (`NSPanel`, `NSStatusItem`, event taps) for system integration.
- **Swift Package Manager, not an .xcodeproj.** Builds with `swift build` from VS Code /
  Claude Code. `scripts/bundle.sh` assembles the `.app` (Info.plist, icon, entitlements).
  Xcode Command Line Tools are sufficient for build, sign and notarize.
- **No third-party dependencies in M0–M3.** Everything above is first-party. Keeps the
  build hermetic and the licence story clean (MIT).
- Python/PySide6 rejected: no clean bridge to AXUIElement/ScreenCaptureKit, and a Python
  runtime for a 5 MB utility is the wrong weight.

## 4. Permissions UX

Accessibility and Screen Recording must be granted by the user in System Settings; they
cannot be scripted. On managed Macs an MDM PPPC profile can pre-grant Accessibility and let a standard user enable Screen Recording, but it can't pre-grant Screen Recording (§5, M6). The app must:

- Detect missing permission (`AXIsProcessTrusted()`, `CGPreflightScreenCaptureAccess()`).
- Show a one-screen onboarding that deep-links to the right pane
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
- Degrade gracefully: without Screen Recording, show icon+title list instead of thumbnails.

## 5. Distribution

- Direct download `.zip` from GitHub Releases, signed with Developer ID and notarized.
  Not App Store — sandboxing forbids event taps and AX.
- Homebrew tap for one-line install on lab Macs.
- Lab fleet: an MDM-delivered PPPC payload (`com.apple.TCC.configuration-profile-policy`) can
  pre-grant **Accessibility** only. It **cannot pre-grant Screen Recording**: for `ScreenCapture`
  a profile can only Deny, or set `Authorization: AllowStandardUserToSetSystemService` so a
  standard (non-admin) user can turn it on in System Settings. The user must still toggle it
  once and relaunch; until then the app falls back to icon+title (D6). Source: Apple Device
  Management reference, `PrivacyPreferencesPolicyControl.Services` ("A profile can't grant
  access to the contents; it can only deny it") and `Services.Identity` (`Authorization`
  values). PPPC keys are marked deprecated in macOS 27 in favour of declarative
  `com.apple.configuration.app.settings`; they still apply on macOS 14–26. Profile:
  `deploy/Switchboard-PPPC.mobileconfig`; procedure: `docs/DEPLOYMENT.md`.

## 6. Prior art (for reading, not copying)

- lwouis/alt-tab-macos — GPL-3. Reference for event-tap handling and Spaces edge cases. **Do not copy code** (licence incompatible with MIT).
- rxhanson/Rectangle — MIT. Reference for clean AppKit menu-bar-app structure, `SMAppService`, permission onboarding.
- Apple sample: "Capturing screen content in macOS" (ScreenCaptureKit).

## 7. Open questions carried into PRD

- Per-window entries for all apps, or a configurable list? PRD: all, with an exclusion list.
- Search-by-typing: cheap once the panel exists (M3).
- Cmd+Tab replacement default-on? PRD: yes, Option+Tab offered during onboarding.
