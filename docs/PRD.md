# PRD.md — Switchboard

**Working title:** Switchboard
**Owner:** Mark
**Licence:** MIT
**Platform:** macOS 14 Sonoma and later, Apple Silicon + Intel
**Status:** Draft v0.1 — 2026-09-26

## 1. Purpose

A free, open-source, telemetry-free macOS utility that replaces app-level Cmd+Tab with a
Windows-style per-window switcher and makes Cmd+Shift+3 / Cmd+Shift+4 copy screenshots
directly to the clipboard. Every feature ships free. The codebase is structured so new
features (search, gestures, window management) can be added without rework.

## 2. Non-goals (v1)

- Window tiling / resizing (Rectangle covers this).
- App Store distribution.
- Windows or Linux ports.
- Replacing Mission Control or Stage Manager.

## 3. Binding design decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Swift + SwiftUI/AppKit, SPM build, no Xcode project | Builds and iterates from VS Code + Claude Code; hermetic; CLT-only toolchain |
| D2 | Zero third-party dependencies through M3 | Small binary, no licence entanglement, no supply-chain surface |
| D3 | Screenshots delegate to `/usr/sbin/screencapture` | Pixel-identical to system behaviour; no custom capture code to maintain |
| D4 | Cmd+Tab takeover via `CGEvent` tap, default ON, Option+Tab fallback | The whole point is muscle memory from Windows |
| D5 | One window = one entry, all apps, with per-app exclusion list | Solves the Chrome-profiles / VS Code-workspaces problem generically |
| D6 | Thumbnails via ScreenCaptureKit, graceful fallback to icon+title | Screen Recording permission may be refused on lab machines |
| D7 | Settings stored in `UserDefaults` under the bundle ID `com.fiavaion.switchboard` (ADR-0001), exportable as JSON | Scriptable for golden-image deployment |
| D8 | No network access of any kind. No update checker in v1. | Data sovereignty; updates via Homebrew tap or GitHub Releases |
| D9 | Menu-bar-only app (`LSUIElement`) | Stays out of Cmd+Tab list itself |

## 4. Users

- **Primary:** Mark, daily driver, 3 Chrome profiles + multiple VS Code windows.
- **Secondary:** NCAD lab Macs (managed fleet) and any Windows-to-Mac migrant.

## 5. Functional requirements

### F1 — Window switcher
- F1.1 Holding the trigger modifier and pressing Tab shows a floating panel listing every
  eligible window across all running apps, most-recently-used first.
- F1.2 Repeated Tab moves selection forward; Shift+Tab backward; arrow keys also work.
- F1.3 Releasing the modifier activates the selected window (raises **that window**, not just the app).
- F1.4 Escape or clicking outside cancels with no focus change.
- F1.5 Each entry shows app icon, window title, and (when permitted) live thumbnail.
- F1.6 Eligible = normal layer (0), at least 50×50 pt (filters invisible helper windows), has a title or is the app's main window. Minimised windows, hidden apps' windows and windows on other Spaces are included by default and marked, each switchable off (F4.2).
- F1.7 Exclusion list (bundle IDs) in settings; excluded apps' windows never appear.
- F1.8 Works across displays; panel appears on the display with the mouse cursor.
- F1.9 Panel appears in ≤ 100 ms from first Tab press on a machine with 20 windows.

### F2 — Screenshot to clipboard
- F2.1 Cmd+Shift+3 → full-screen capture placed on the clipboard as PNG; no file written.
- F2.2 Cmd+Shift+4 → interactive region/window selection; result on clipboard as PNG.
- F2.3 Optional (off by default): also save a file to a configurable folder.
- F2.4 Optional: brief HUD confirmation ("Copied to clipboard").
- F2.5 "Make permanent" button applies the equivalent `com.apple.screencapture` /
  symbolic-hotkey defaults so behaviour survives Switchboard quitting.

### F3 — Permissions & onboarding
- F3.1 On first launch, detect Accessibility and Screen Recording state.
- F3.2 Single onboarding window with two rows, each with a status indicator and an
  "Open System Settings" button deep-linking to the correct pane.
- F3.3 App remains functional in degraded mode without Screen Recording (F1.5 falls back).
- F3.4 Re-check permissions on app activation and after settings pane is closed.

### F4 — Settings
- F4.1 Trigger modifier: Cmd (default) or Option.
- F4.2 Show/hide: minimised windows, hidden apps, windows on other Spaces.
- F4.3 Exclusion list editor.
- F4.4 Thumbnail size: S/M/L/auto.
- F4.5 Launch at login toggle (`SMAppService`).
- F4.6 Export/import settings as JSON.

### F5 — Menu bar
- F5.1 Status item with menu: Settings…, Check permissions…, About, Quit.
- F5.2 Option to hide status item (relaunch app to restore).

## 6. Non-functional requirements

- N1 Idle CPU < 0.5 %; no polling — window list refreshed on demand and via `NSWorkspace` notifications.
- N2 Memory < 60 MB with thumbnails cached for ≤ 30 windows.
- N3 Universal binary; signed with Developer ID; notarized.
- N4 Unit tests for window-eligibility filtering and MRU ordering; UI smoke test script.
- N5 Accessibility: panel navigable by keyboard only; VoiceOver labels on entries.

## 7. Milestones

Each milestone ends with a tagged commit and a passing `scripts/build.sh`.

### M0 — Skeleton (target: 1 session)
- SPM package, `scripts/bundle.sh` producing a launchable `.app`, menu bar icon, Quit.
- Permission detection + onboarding window (F3.1–F3.2).
- **Accept:** App launches from `open build/Switchboard.app`, status item visible, onboarding shows correct permission state.

### M1 — Screenshot to clipboard
- Event tap capturing Cmd+Shift+3/4; invokes `screencapture -c` / `-ci`.
- HUD (F2.4). "Make permanent" (F2.5).
- **Accept:** After Cmd+Shift+4, pasting into Gmail/VS Code/browser inserts the image; no file in ~/Desktop.

### M2 — Switcher core (no thumbnails)
- Window enumeration + eligibility filter (F1.6) with unit tests.
- Event tap for modifier+Tab; MRU tracking via `NSWorkspace.didActivateApplicationNotification` + AX focused-window observer.
- Panel: icon + title rows, keyboard navigation, raise-on-release via AX.
- **Accept:** With 3 Chrome profiles and 2 VS Code windows open, each appears as its own entry and Cmd+Tab-release lands on the chosen window every time.

### M3 — Thumbnails, search, polish
- ScreenCaptureKit thumbnails with cache; fallback (D6).
- Type-to-filter while panel is open.
- Multi-display placement (F1.8), minimised marker, exclusion list (F1.7).
- **Accept:** F1.9 timing met; search narrows list live; excluded app absent.

### M4 — Settings & persistence
- SwiftUI settings window covering F4; JSON export/import; launch at login.
- **Accept:** Settings survive relaunch; JSON round-trips; login item registers.

### M5 — Release engineering
- `scripts/release.sh`: universal build, codesign, notarize, staple, zip.
- Homebrew cask formula in a `homebrew-tap` repo.
- GitHub Actions workflow on macOS runner running tests + unsigned build on every push.
- **Accept:** Fresh Mac: `brew install --cask <tap>/switchboard` → app runs, Gatekeeper silent.

### M6 — Fleet deployment (NCAD)
- PPPC configuration profile pre-granting Accessibility and letting standard users enable Screen Recording (PPPC can't pre-grant Screen Recording; RESEARCH §5).
- Golden-image notes: preinstall path, default settings JSON, exclusion list for lab software.
- **Accept:** Imaged lab Mac boots with Switchboard installed and the PPPC profile applied. Cmd+Tab works with no prompt (Accessibility is pre-granted). A standard user can enable Screen Recording without an admin password, and until they do the switcher shows icon + title.

## 8. Future backlog (post-v1)
- Trackpad swipe to switch; window-preview on hover; per-Space filtering with public APIs only;
  quick actions on entries (close, minimise); Raycast/Alfred-style command palette;
  optional Ollama-backed "jump to the window about X" if it ever proves useful.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Cmd+Tab swallow conflicts with Dock on some macOS versions | Option+Tab fallback (D4); test on each macOS point release |
| Private CGS Spaces APIs break | Public fallback in D5/RESEARCH §2; feature-flag the private path |
| Notarization / hardened runtime rejects event tap | Entitlements documented in `scripts/`; hardened runtime does permit event taps for non-sandboxed apps |
| Screen Recording refused on lab machines | D6 fallback; M6 PPPC profile |
