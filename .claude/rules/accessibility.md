---
paths:
  - "Sources/Switchboard/UI/**/*.swift"
---
# Accessibility — WCAG 2.2 AA, adapted to AppKit/SwiftUI (binding for any UI change)

PRD N5: the switcher panel is fully keyboard-operable and every entry has a VoiceOver label.
A UI change that fails these is not done, however good it looks.

## Non-negotiables

- **Keyboard:** every control in the switcher panel, onboarding, settings and HUD is reachable
  and operable by keyboard alone, in a logical order, with no traps. Escape always cancels
  (F1.4). A visible selection/focus indicator on the switcher row and on every focusable
  control — never hidden without a replacement of equal visibility.
- **Names and roles:** every entry and control has an accessible name — SwiftUI
  `.accessibilityLabel` or the AppKit `NSAccessibility` equivalent. A switcher row reads as
  "<window title>, <app name>" plus "minimised" when F1.6 marks it. Prefer native `Button`,
  `Toggle`, `Picker`, `NSButton` over tap gestures on plain views.
- **Announcements:** selection changes in the switcher panel are announced to VoiceOver
  (`NSAccessibility.post(element:notification:)` with `.selectedChildrenChanged` or
  `.focusedUIElementChanged`); the HUD (F2.4) posts `.announcementRequested`.
- **Contrast:** text ≥ 4.5:1 (≥ 3:1 for large text); selection highlight and focus rings
  ≥ 3:1 against the panel material. Check light, dark, and Increase Contrast.
- **Colour is never the only signal** — the minimised marker and permission status (F3.2) carry
  a symbol or text, not just a colour.
- **Motion and text size:** honour Reduce Motion (`accessibilityReduceMotion`) for panel
  animations and Reduce Transparency for vibrancy; layouts survive larger text without clipping.
- **Icons:** app icons in rows are decorative (`.accessibilityHidden(true)`) because the label
  already names the app; icon-only buttons always carry a label.

## How to verify (do this, don't assert it)

1. Operate the changed surface with the keyboard only — reach everything, see focus, Escape cancels.
2. Turn on VoiceOver (Cmd+F5) and walk it; every row and control reads a sensible name.
3. Run Accessibility Inspector (Xcode → Open Developer Tool) audit on the window.
4. Check contrast in light, dark and Increase Contrast.
5. State in the change summary which of these were checked and how.

## This project
- The switcher panel is an `NSPanel` that must not steal key focus from the target app until
  release; keyboard handling comes from the event tap, so VoiceOver announcements must be posted
  explicitly rather than relying on first-responder focus changes.
