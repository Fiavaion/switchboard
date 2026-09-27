# CLAUDE.md — Switchboard

Read `docs/RESEARCH.md` then `docs/PRD.md` before doing anything. The PRD's design decisions
(D1–D9) are binding; propose a PRD edit rather than silently deviating.

## Rule #0 — This file is the source of truth
Hierarchy (highest first): (1) this file, (2) Mark's direct instructions, (3) other docs
(PRD, RESEARCH, README), (4) config files, (5) conversation summaries. Higher wins on conflict.
If told you're wrong, re-read this file before arguing. If genuinely unsure, ask — never guess.

## Success Metric
With 3 Chrome profiles and 2 VS Code windows open, each window appears as its own entry in the
switcher, and releasing Cmd+Tab raises **the chosen window** (not just its app) every time.
(PRD M2 acceptance.) This is the gate — not feature count, not coverage %.

## Scope freeze
- **In scope now:** M0 → M1 → M2, in PRD order.
- **Deferred until the Success Metric passes:** M3–M6 and PRD §8 backlog. Not "maybe" — deferred.
- A dependency is added only when an in-scope feature needs it now (D2: none through M3).
- UI-first: sketch the switcher panel with dummy `WindowInfo` data before wiring enumeration/AX.

## Project
Free, MIT-licensed macOS menu-bar utility: per-window Cmd+Tab switcher + screenshot-to-clipboard.
Swift 5.9+, SwiftUI + AppKit, Swift Package Manager. macOS 14+. No third-party dependencies through M3.
Bundle ID / UserDefaults domain / log subsystem: `com.fiavaion.switchboard` (`docs/adr/0001-bundle-identifier.md`).

## Build & run
```bash
scripts/build.sh          # swift build -c debug, then bundle to build/Switchboard.app
open build/Switchboard.app
scripts/build.sh release  # optimised build
swift test                # unit tests (SwitchboardCore only)
```
Debug logging: `log stream --predicate 'subsystem == "com.fiavaion.switchboard"' --level debug`

## Testing
- Runner: XCTest via `swift test` (what the global `/test` runs). Scope a run with
  `swift test --filter EligibilityTests` (or `<Class>/<testMethod>`).
- Depth: standard — unit tests for every `SwitchboardCore` module (eligibility, MRU ordering,
  settings codable, per PRD N4), written alongside the code, never after.
- **Smoke test = the Success Metric path, driven for real** (checklist: `docs/SMOKE_TEST.md`) against
  `build/Switchboard.app`: open 3 Chrome profiles + 2 VS Code windows, Cmd+Tab, cycle, release,
  confirm the focused window. Run at every milestone gate and at `/end` once M2 exists.
  Green `swift test` alone never closes a milestone — the event tap, AX and TCC paths are
  untestable in XCTest.
- Smoke driver: `swift scripts/smoke/drive.swift switch 1 | search <text> <png> | shot3 …` posts real
  key events and prints the focused window (the running process needs Accessibility + Screen Recording).
- Dev builds are signed with "Apple Development" so TCC grants survive rebuilds; if grants stop
  sticking, check `codesign -dr - build/Switchboard.app` first.

## Layout
```
Package.swift
Sources/SwitchboardCore/   # pure logic, no AppKit: WindowInfo + EligibilityFilter, MRUList, Settings, SwitcherState. Unit-tested.
Sources/Switchboard/       # app target
  App/        AppDelegate, StatusItem, Permissions (the only TCC checks), SettingsStore, SwitcherController, Log
  Input/      EventTap.swift (one session tap: trigger+Tab, Cmd+Shift+3/4)
  Windows/    AX.swift, WindowEnumerator (AX + CGWindowList), WindowActivator (AX raise), FocusTracker (MRU)
  Capture/    Thumbnailer.swift (SCK), Screenshot.swift (screencapture wrapper + F2.5 defaults)
  UI/         SwitcherPanel, OnboardingView, SettingsView, HUD, WindowPresenter
Resources/    Info.plist, Switchboard.entitlements, AppIcon.icns (scripts/make-icon.swift)
Tests/SwitchboardCoreTests/
scripts/      build.sh, bundle.sh, release.sh (→ build/release/), make-icon.swift, smoke/drive.swift
packaging/    homebrew/switchboard.rb (cask template)
deploy/       Switchboard-PPPC.mobileconfig, default-settings.json
docs/         RESEARCH.md, PRD.md, DEPLOYMENT.md, adr/
notes/        CURRENT_STATUS.md, TODOs.md, lessons.md
```

## Conventions
- One milestone per branch (`m1-screenshot`, `m2-switcher`…); squash-merge to `main`; tag `v0.<M>.0`.
- Logic that can be tested without AppKit goes in `SwitchboardCore`. Keep the app target thin.
- Use `os.Logger(subsystem: "com.fiavaion.switchboard", category: ...)`; never `print` in shipped paths.
- All permission-gated calls go through `Permissions.swift`; never call `AXIsProcessTrusted` elsewhere.
- Shell out only to `/usr/sbin/screencapture`. No other subprocesses.
- No network code. If you think you need it, stop and ask.
- Do not copy code from GPL projects (AltTab). Reading for understanding is fine; cite in a comment.
- Posture: aggressive + autonomous — run agreed milestone work end to end; larger refactors are
  fine when tests exist. Still plan before a multi-file change, and stop at Change Boundaries.

## Working with Mark
- Document-driven: when a milestone's acceptance criteria are met, say so explicitly and list what was verified manually vs by test.
- Prefer small commits with messages referencing PRD IDs (e.g. `F2.1: Cmd+Shift+3 to clipboard`).
- If macOS behaviour differs from RESEARCH.md, update RESEARCH.md in the same commit.

## Coding Guidelines
- Karpathy core: think before coding · simplicity first · surgical changes · goal-driven
  execution. Verification is the binding constraint — wire "done" to a runnable check.
- **Minimalism ladder:** (1) does this need to exist? (2) Swift stdlib? (3) an AppKit/macOS
  feature? (4) one line? (5) only then, the minimum that works. Never cut error handling,
  permission fallbacks (D6, F3.3) or accessibility to be "minimal".
- **Reviewer mode:** after writing code, re-read the diff as a reviewer who intends to reject it
  (bugs, over-engineering, scope creep, missing tests); fix, *then* declare done. For risky
  changes (event tap, AX activation, signing) escalate to a fresh-context verifier.

## Zero Technical Debt
- Delete old code; never comment it out. No dead code, no parallel code paths. Git is the backup.
- Red flags in a core path — "DEFERRED", "TODO Phase X", "TEMPORARY", "refactor later" — mean
  stop and fix, not build on top. Core work is never deferred (it compounds 4–7×).
- Any accepted deferral of a non-critical item is logged and costed in `TECHNICAL_DEBT.md`.
- If a deadline would need debt, say so and get a decision — never slip it in.

## Done means verified working
- Done = the behaviour was seen working in the built app (or Mark confirmed it), not green tests.
- Never build M(n+1) on an M(n) whose acceptance criterion hasn't been seen passing.
- Write checkable acceptance criteria before non-trivial work (PRD milestone "Accept:" lines are
  the template). Before reporting progress, tie every claim to a tool result from this session.

## Change Boundaries
- **Never edit without explicit approval:**
  - `Resources/Info.plist` `CFBundleIdentifier`, and `Resources/Switchboard.entitlements` —
    TCC grants, the UserDefaults domain and the M6 PPPC profile are keyed to them.
  - Signing in `scripts/bundle.sh` (identity change = every TCC grant resets).
  - UserDefaults key names once shipped (persistence identifiers; D7 JSON export depends on them).
  - `scripts/release.sh` and `.github/` once they exist (M5).
  - Writing system defaults (`com.apple.screencapture`, `com.apple.symbolichotkeys`) outside F2.5.
- **Surgical scope:** a change to one feature touches that feature's files and direct tests;
  shared code (`SwitchboardCore`, `Permissions.swift`) only when a failing test proves it must.
- Never commit secrets, signing certs, or notarization credentials (app-specific passwords, API keys).

## Architecture Decision Records
- PRD D1–D9 are the founding decisions. Every *new* hard-to-reverse decision gets a short ADR in
  `docs/adr/NNNN-<slug>.md`, written before implementation.


## Dev & Bug-Fix Discipline
- Loop: explore → plan → implement → reviewer mode → `swift test` → `scripts/build.sh` →
  drive the app (Computer Use) → commit. One feature or fix per commit; no `wip` on `main`.
- Bugs: reproduce first; add `Logger` debug output and watch `log stream` *before* reading lots
  of code. No diagnosis in ~5 minutes → change strategy. Remove scaffolding logs after the fix.
- "Completely broken" = assume several root causes. Audit the whole chain (permission → event
  tap → enumeration → eligibility → panel → AX raise), counting expected vs actual at each step.
- Isolate parallel/background agent work in a git worktree.

## Token & Context Rules
- `@`-mention specific files; don't paste big logs — save to a file and reference it.
- `/context` to inspect · `/compact` after each milestone · `/cost` before expensive phases.
- Plan in plan mode, implement in small diffs, compact at each checkpoint.

## Scoped Rules
- `.claude/rules/accessibility.md` → `Sources/Switchboard/UI/**`: keyboard-only operation and
  VoiceOver (PRD N5), WCAG 2.2 AA adapted to AppKit/SwiftUI.

## Project Skills
- None.

## Slash Commands
- No project commands. Lifecycle and quality commands are global: `/start`, `/end`, `/todos`,
  `/lessons`, `/test`, `/release`.

## Session continuity, TODOs & lessons
- Personal, untracked: `CLAUDE.local.md` (Claude Code loads it automatically; git-ignored).
- Layout: `notes/CURRENT_STATUS.md` · `notes/TODOs.md` · `notes/lessons.md` · `TECHNICAL_DEBT.md` · `docs/adr/`.
- `notes/CURRENT_STATUS.md` is the restart package, rewritten at every `/end`.
- TODOs: single source of truth `notes/TODOs.md`; tag inline `TODO[cl]:`; `/todos` syncs.
- Lessons: tag inline `// LESSON-{ARCH|BUG|PERF|API|UI|TEST|BUILD}-NNN: summary` at the point of
  insight; `/lessons` folds them into `notes/lessons.md`.
- **Fix the process, not the output:** a correction goes into this file, a rule, or a skill.
