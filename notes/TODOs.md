# TODOs

## Backlog
- M5: notarize a real release (needs `notarytool` keychain profile) and publish; repo must be public before the cask can download (docs/DEPLOYMENT.md)
- M5: create `Fiavaion/homebrew-tap` with `packaging/homebrew/switchboard.rb`
- M6: lab boot requirement — `launchAtLogin` via SMAppService registers only after the app has run once per user. If lab Macs must boot with Switchboard running, decide between a `/Library/LaunchAgents` plist and an MDM login-item payload
- M6: check whether `forceBypassScreenCaptureAlert` requires a supervised Mac
- Decide: first ⌘Tab after launch orders unseen windows by window-server order, which approximates recency; persisting MRU across launches would fix it

## In Progress

## Ready for Review
- Remaining hands-on checks in `docs/SMOKE_TEST.md` (VoiceOver, second display, Export/Import, click-outside, paste into apps)

## Done (recent, rolling)
- 2026-09-26 M0–M4 built, live-verified with synthetic key events, two fresh-context reviews (1 blocker + 2 high fixed)
- 2026-09-26 M5 release.sh / CI / cask template; M6 PPPC profile, default settings, DEPLOYMENT.md
- 2026-09-26 Bootstrap: build fixed, bundle ID `com.fiavaion.switchboard` (ADR-0001), continuity layout, git + private remote
