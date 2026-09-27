# ADR-0001: Bundle identifier `com.fiavaion.switchboard`

**Date:** 2026-09-26
**Status:** Accepted
**Deciders:** Mark

## Context
PRD D7 carried a placeholder domain (`ie.<yourcompany>.switchboard`), `Info.plist` used
`ie.switchboard.app`, and the logger used `ie.switchboard`. The bundle identifier keys
Accessibility and Screen Recording TCC grants, the `UserDefaults` domain (D7), the M6 PPPC
configuration profile and the Homebrew cask. Changing it after release resets every user's
permissions and orphans their settings, so it has to be fixed before M0 ships.

## Decision
Use `com.fiavaion.switchboard` everywhere: `CFBundleIdentifier`, the `UserDefaults.standard`
domain (follows the bundle ID), and the `os.Logger` subsystem.

## Consequences
- ✅ One identifier for code, logs, settings and MDM; reverse-DNS of a name the owner controls.
- ✅ `log stream --predicate 'subsystem == "com.fiavaion.switchboard"'` matches the bundle ID.
- ❌ Any TCC grant made to a pre-bootstrap local build (`ie.switchboard.app`) must be re-granted.

## Alternatives considered
1. `ie.switchboard.app` — rejected: implies owning `switchboard.ie`, and diverged from the logger subsystem.
2. An NCAD domain — rejected: the app is Mark's own open-source project; NCAD is a deployment target (M6), not the publisher.
