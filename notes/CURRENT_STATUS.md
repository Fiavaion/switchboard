# Current Status

**Last updated:** 2026-09-27
**Phase / focus:** v0.4.0 (M0–M4) tagged, Success Metric verified; M5 release pending notarization credentials.
**Build:** ✅ `scripts/build.sh` (0 warnings)   **Tests:** 28/28 passing (`swift test`)

## What works right now (seen working on the real app, macOS 26.6.2)
- [x] M0: menu bar app, onboarding with live permission state, Settings on reopen
- [x] M1: ⌘⇧3 / ⌘⇧4 → clipboard via `screencapture`, system hotkeys swallowed, HUD, no Desktop file
- [x] M2: per-window ⌘Tab, exact window raised (same-app windows, other Spaces, minimised, hidden apps), MRU toggle, Esc, quick release; panel ready in 24–31 ms
- [x] M3: live thumbnails (icon fallback), type-to-filter, exclusions
- [x] M4: flat-key settings persist; ⌥Tab mode; JSON round-trip (unit tests)
- [x] N1 idle CPU 0.0 %, N2 footprint 41 MB
- [x] M5: `scripts/release.sh --skip-notarize` → universal, Developer ID, hardened runtime (not notarized)
- [x] **Success Metric** (2026-09-27): 3 full-screen Chrome profile windows + 4 VS Code windows, 14/14 exact landings from a fresh launch (fixed by AX remote-token element discovery, LESSON-API-004)
- [x] Login item registers/unregisters; clipboard holds PNG after ⌘⇧3
- [ ] Not yet seen: VoiceOver, multi-display, Export/Import panels, click-outside cancel, paste into apps — see `docs/SMOKE_TEST.md`

## What's broken
- Nothing known. (The full-screen "flash through the other window" is gone since element discovery: direct in ~0.65 s.)

## Next 3 tasks (in order)
1. Notarization credentials (Mark, once): create an app-specific password at account.apple.com, then
   `xcrun notarytool store-credentials switchboard --apple-id <id> --team-id 9RWD38STJV`.
2. `NOTARY_PROFILE=switchboard scripts/release.sh` → GitHub Release v0.4.0 → `Fiavaion/homebrew-tap` (docs/DEPLOYMENT.md).
3. Remaining hands-on checks in `docs/SMOKE_TEST.md`.

## Blockers
- Notarization needs Mark's Apple ID app-specific password (no stored notarytool profile or API key on this Mac).

## Reference links
- Success metric / definition of done: CLAUDE.md → Success Metric
- Morning test: docs/SMOKE_TEST.md · Tasks: notes/TODOs.md · Lessons: notes/lessons.md
