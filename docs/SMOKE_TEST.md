# Smoke test — Switchboard v0.4 (M0–M4)

The acceptance walk-through for each milestone. **Auto** = already verified on the real app by
driving real key events (`scripts/smoke/drive.swift`) and reading the focused window back.
**You** = needs a human, or hardware the automated run didn't have.

## Before you start

```bash
cd ~/Desktop/AIProjects/switchboard
scripts/build.sh && open build/Switchboard.app
```

- **Quit other window switchers** (AltTab and the like): two switchers make results hard to read.
- If macOS shows **"Switchboard is requesting to bypass the system private window picker"**,
  click **Allow**. This is the macOS 15+ ScreenCaptureKit consent; thumbnails need it (RESEARCH §2).
- If your `com.apple.screencapture target` is already `clipboard`, plain macOS shortcuts
  copy to the clipboard too. The M1 checks below tell the two apart by the HUD and the log.
- Live log: `log stream --predicate 'subsystem == "com.fiavaion.switchboard"' --level info`

## M0 — Skeleton

| Check | Result |
|---|---|
| App launches, menu bar icon visible, no Dock icon | Auto ✅ |
| Onboarding shows correct state for both permissions, deep-link buttons, ⌘/⌥ choice | Auto ✅ (screenshot + AX tree) |
| Onboarding "Done" closes it and it doesn't return on relaunch | Auto ✅ |
| Revoke Accessibility in System Settings while running → onboarding row turns orange on reactivation; keyboard is never captured | **You** |
| Menu: Settings…, Check Permissions…, About, Quit all work | **You** (Settings via reopen: Auto ✅) |

To see onboarding again: `defaults delete com.fiavaion.switchboard onboardingShown`, relaunch.

## M1 — Screenshot to clipboard

| Check | Result |
|---|---|
| ⌘⇧3 → Switchboard runs `screencapture -c`, clipboard updated, **no file on Desktop**, "Copied to clipboard" HUD | Auto ✅ |
| ⌘⇧4, then Esc → nothing copied, no HUD | Auto ✅ |
| ⌘⇧4 → drag a region → **paste into Gmail, VS Code and a browser** | **You** (the PRD acceptance). Auto ✅: the clipboard holds a PNG (`«class PNGf»`) after ⌘⇧3 |
| ⌘⇧4, Space, click a window → window capture pasted | **You** |
| Settings → Screenshots → "Also save to a folder" → file appears there *and* on clipboard | **You** |
| "Go Back to Saving Files" / "Make Clipboard Screenshots Permanent" flips the line above it; quit Switchboard and ⌘⇧3 behaves accordingly | **You** (changes your system setting — put it back to clipboard after) |

## M2 — Switcher core (the Success Metric)

| Check | Result |
|---|---|
| Three windows of one app (Safari) each switchable by exact window | Auto ✅ |
| Two VS Code windows, each raised exactly — including one on another Space | Auto ✅ |
| Quick ⌘Tab toggles between the last two windows, even within one app | Auto ✅ |
| ⌘Tab released instantly (before the list loads) still switches | Auto ✅ |
| Esc cancels with no focus change; click outside cancels | Auto ✅ (Esc) / **You** (click) |
| Minimised window restored and focused; hidden app unhidden and focused | Auto ✅ |
| Panel ready ≤ 100 ms (F1.9) | Auto ✅ — 24–31 ms with 25–29 windows |
| **With 3 Chrome profiles + 2 VS Code windows open, each is its own entry and ⌘Tab-release lands on the chosen one every time** | Auto ✅ 2026-09-27 — 3 full-screen Chrome profile windows + 4 VS Code windows, 14/14 twice around from a fresh launch; toggles between two Chrome windows alternate correctly. Worth one run by hand too. |
| VoiceOver (⌘F5) announces the selected entry as you Tab | **You** |

## M3 — Thumbnails, search, polish

| Check | Result |
|---|---|
| Live thumbnails; icon + title fallback for windows SCK can't capture | Auto ✅ |
| Type while holding ⌘ to filter live (e.g. `⌘Tab` then `n c a d`) | Auto ✅ |
| Excluded app absent (exclusion via `defaults`) | Auto ✅ |
| Add/remove an exclusion in Settings → Exclusions | **You** |
| Panel appears on the display with the mouse (F1.8) | **You** — needs a second display |
| Up/Down move by row, Left/Right by one | **You** |

## M4 — Settings & persistence

| Check | Result |
|---|---|
| Settings survive relaunch (flat keys in `com.fiavaion.switchboard`) | Auto ✅ |
| JSON round-trip, bad keys tolerated | Auto ✅ (unit tests) |
| Export… then Import… in Settings → Backup | **You** (save panels) |
| "Open at login" registers (System Settings → General → Login Items) and survives a logout | Auto ✅ registers and unregisters with no approval prompt / **You**: survives a logout |
| ⌥Tab mode: ⌥Tab switches, ⌘Tab goes back to the Dock | Auto ✅ |
| Hide menu bar icon → reopen Switchboard from Finder → Settings opens | **You** |

## Known behaviour (not bugs)

- Windows on inactive **full-screen** Spaces show an app icon instead of a thumbnail.
- ⌘Tab does nothing special while a password field has focus: macOS Secure Input hides keystrokes from all event taps, so the Dock's switcher appears instead.
- Until Switchboard has seen you use a window, its first ⌘Tab order follows the window server's
  order, which is close to, but not exactly, recency.

## After testing

If you granted your terminal or editor Accessibility and Screen Recording to run
`scripts/smoke/drive.swift`, revoke them in System Settings → Privacy & Security.
