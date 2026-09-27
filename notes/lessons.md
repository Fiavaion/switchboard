# Lessons Ledger

Tag inline as `// LESSON-{ARCH|BUG|PERF|API|UI|TEST|BUILD}-NNN: summary`; `/lessons` folds tags in here.

#### LESSON-BUILD-001: `CGRect` geometry needs `import CoreGraphics`
**Problem:** `swift test` failed: "value of type 'CGRect' has no member 'width'" in `SwitchboardCore`.
**Root cause:** `Foundation` re-exports the `CGRect` type but not the `width`/`height` accessors, which live in CoreGraphics.
**Fix:** `import CoreGraphics` in `WindowInfo.swift` (still AppKit-free, so the core target stays testable).
**Prevention:** any `SwitchboardCore` file touching `CGRect`/`CGPoint` geometry imports CoreGraphics explicitly.
**Location:** Sources/SwitchboardCore/WindowInfo.swift:1 · **Impact:** med (blocked every build)

#### LESSON-BUILD-002: ad-hoc signing silently drops TCC grants on every rebuild
**Problem:** Accessibility/Screen Recording had to be re-granted after each `scripts/build.sh`.
**Root cause:** an ad-hoc signature's designated requirement is its cdhash, which changes every build; TCC keys grants to the DR.
**Fix:** `bundle.sh` signs with the "Apple Development" certificate (DR = bundle ID + cert), ad hoc only when no cert exists (CI).
**Prevention:** check `codesign -dr - build/Switchboard.app` first whenever grants stop sticking. Release builds go to `build/release/` so they never re-sign the dev app.
**Location:** scripts/bundle.sh:12 · **Impact:** high (blocked all live testing)

#### LESSON-API-001: `NSRunningApplication.unhide()` is asynchronous
**Problem:** switching to a window of a hidden app unhid it but focus stayed on the previous app.
**Root cause:** the AX frontmost request reached the app while it was still hidden and was dropped.
**Fix:** unhide via `kAXHiddenAttribute` on the activation queue, then re-assert `kAXFrontmostAttribute` every 50 ms (≤1 s) until the app reports frontmost.
**Prevention:** after any activation, confirm the outcome rather than trusting a success return code.
**Location:** Sources/Switchboard/Windows/WindowActivator.swift:17 · **Impact:** med

#### LESSON-API-002: `AXUIElementSetMessagingTimeout` is per element
**Problem:** a hung app could stall enumeration for 6 s per call despite a 0.2 s timeout on the app element.
**Root cause:** the timeout applies only to the element it's set on; child/window elements keep the global 6 s default. (Found in code review.)
**Fix:** `AX.bounded` sets it on every element handed out; activation raises it to 1 s because Safari's raise takes ~0.3 s.
**Location:** Sources/Switchboard/Windows/AX.swift:12 · **Impact:** med

#### LESSON-API-003: `JSONSerialization.data(withJSONObject:)` raises an uncatchable ObjC exception
**Problem:** a `Date`-typed value in the defaults domain would crash the app at every launch.
**Fix:** check `isValidJSONObject` per key, decode each key alone, keep defaults for rejects.
**Location:** Sources/SwitchboardCore/Settings.swift:77 · **Impact:** high (crash loop) — found by review, fixed before it shipped

#### LESSON-TEST-001: `NSWorkspace.frontmostApplication` is stale in a process without a run loop
**Problem:** smoke runs reported switches landing late or on the previous window, and Preview's Open dialog looked "slow" (up to 2.5 s).
**Root cause:** the driver is a command-line process with no running event loop; NSWorkspace refreshes `frontmostApplication` from notifications on that loop, so after the first read it kept returning a cached value, one switch behind. The app was fine: timelines from fresh processes showed every switch landing in 0.3–0.6 s.
**Fix:** read the focused app from `AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute`, which is live.
**Prevention:** in any CLI/agent tooling, never trust NSWorkspace state without spinning the run loop; confirm a "slow" result with an independent measurement before recording it as behaviour.
**Location:** scripts/smoke/drive.swift (`front()`) · **Impact:** med (cost ~20 min chasing a non-bug; nearly shipped a false "known issue")

#### LESSON-API-004: `kAXWindowsAttribute` omits windows on other Spaces
**Problem:** with 3 Chrome profile windows each full screen on its own Space, only 4 of 14 success-metric switches landed. Every Chrome switch went to Chrome's most recent window.
**Root cause:** AX listed no Chrome windows at all, and the fallback (activate the app, then look for the window) always lands on the app's last-used window.
**Fix:** find the elements directly with `_AXUIElementCreateWithRemoteToken`, by scanning element IDs 0–999 (~30 ms per app). This runs in the background at launch and on each Space change, and the results are cached.
**Also:** child elements (groups, buttons) resolve to their window's ID too, so a match only counts when `kAXRoleAttribute` is `AXWindow`. Windows that are never found go in a negative cache, so a miss costs one scan, not one on every open. (Both found in code review.)
**Prevention:** test the success metric in exactly its described setup (several windows of one app, full screen) before calling it met. Last night's Safari/VS Code proxy runs hid this.
**Location:** Sources/Switchboard/Windows/AX.swift (`windowElements`) · **Impact:** high (the product's core promise)

#### LESSON-BUILD-003: CGFloat/Double arithmetic can time out older Swift type-checkers
**Problem:** CI (macos-15 runner) failed with "unable to type-check this expression in reasonable time" on a one-line layout calculation that compiled instantly with local Swift 6.3.
**Root cause:** implicit CGFloat↔Double conversion multiplies the overloads the solver must try; older compilers give up.
**Fix:** annotate intermediates as `Double` and convert `CGFloat` explicitly.
**Prevention:** before pushing UI code, build once with `-Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking=30` and fix anything flagged.
**Location:** Sources/Switchboard/UI/SwitcherPanel.swift (`layout()`) · **Impact:** med (red CI on the first public push)
