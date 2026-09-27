# DEPLOYMENT.md — Switchboard

How to cut a release (PRD M5) and put Switchboard on NCAD lab Macs (PRD M6).

## 1. Release procedure

### One-time setup
1. Signing identity: `Developer ID Application: Mark Jones (9RWD38STJV)` must be in the login
   keychain (`security find-identity -v -p codesigning`). Override with `SIGN_IDENTITY=...` if needed.
2. Store notarization credentials in the keychain under a profile name (app-specific password from
   appleid.apple.com, or an App Store Connect API key):
   ```bash
   xcrun notarytool store-credentials switchboard-notary \
     --apple-id <apple-id-email> --team-id 9RWD38STJV --password <app-specific-password>
   ```
3. Make `Fiavaion/switchboard` **public** before the first published release. Homebrew downloads
   the zip anonymously from GitHub Releases, so a cask pointing at a private repo fails with a 404.
4. Create the tap repo `Fiavaion/homebrew-tap` (public) and copy
   `packaging/homebrew/switchboard.rb` to `Casks/switchboard.rb` in it.

### Each release
1. Set `CFBundleShortVersionString` in `Resources/Info.plist` (e.g. `0.5.0`) and bump `CFBundleVersion`.
2. Validate locally without uploading anything to Apple:
   ```bash
   scripts/release.sh --skip-notarize
   codesign -dv --verbose=2 build/release/Switchboard.app   # Authority=Developer ID Application..., flags=0x10000(runtime)
   lipo -archs build/release/Switchboard.app/Contents/MacOS/Switchboard   # x86_64 arm64
   ```
3. Build, sign, notarize, staple and zip:
   ```bash
   NOTARY_PROFILE=switchboard-notary scripts/release.sh
   ```
   It stops with an error if `NOTARY_PROFILE` is unset. The last lines print the zip path,
   `version` and `sha256`.
4. Check Gatekeeper accepts it: `spctl -a -vv -t exec build/release/Switchboard.app` should say
   `source=Notarized Developer ID`.
5. Tag and publish (tag convention `v<version>`, matching the cask URL):
   ```bash
   git tag v0.5.0 && git push origin v0.5.0
   gh release create v0.5.0 build/release/Switchboard-0.5.0.zip --repo Fiavaion/switchboard --title "Switchboard 0.5.0"
   ```
6. In `Fiavaion/homebrew-tap`, update `version` and `sha256` in `Casks/switchboard.rb` to the
   values release.sh printed, then commit and push. Keep `packaging/homebrew/switchboard.rb` in
   this repo in step.
7. M5 acceptance check on a clean Mac:
   `brew install --cask fiavaion/tap/switchboard`, launch, confirm no Gatekeeper dialog.

## 2. Fleet deployment (NCAD golden image)

### What a profile can and cannot pre-grant
| Permission | Needed for | PPPC can |
|---|---|---|
| Accessibility | Cmd+Tab event tap, raising windows via AX | **Allow** (silently pre-granted) |
| Screen Recording | Window thumbnails (ScreenCaptureKit) | **Not grant.** Only Deny, or `AllowStandardUserToSetSystemService` so a non-admin can switch it on |

Source: Apple Device Management reference, `PrivacyPreferencesPolicyControl.Services`
("ScreenCapture … A profile can't grant access to the contents; it can only deny it") and
`Services.Identity` (`AllowStandardUserToSetSystemService` is valid only for `ListenEvent` and
`ScreenCapture`). Details in RESEARCH.md §5.

### Steps
1. **Install** the notarized `Switchboard.app` to `/Applications/Switchboard.app` (copy from the
   release zip with `ditto -x -k Switchboard-<version>.zip /Applications`, or `brew install --cask`).
   The PPPC profile matches by bundle ID + Team ID, so the path doesn't matter to TCC, but
   `/Applications` is the supported location.
2. **PPPC profile:** upload `deploy/Switchboard-PPPC.mobileconfig` to the MDM and scope it to the lab
   machines. It must arrive via MDM (user-approved or supervised enrolment); macOS ignores PPPC
   payloads installed by double-clicking. The profile's `CodeRequirement` is the designated
   requirement of the Developer ID build and does not change between versions unless the
   bundle ID or signing team changes. Re-derive it with `codesign -dr - /Applications/Switchboard.app`.
   On macOS 15.1+ you can also add the Restrictions payload key `forceBypassScreenCaptureAlert`
   to suppress the recurring Screen Recording confirmation alerts (check Apple's docs for its
   supervision requirement).
3. **Default settings.** `deploy/default-settings.json` is the lab default in the app's JSON export
   format (F4.6). Pick one way to apply it:
   - *Per user* (run as that user, e.g. from a login script). `defaults import` takes a plist,
     not JSON, so convert first:
     ```bash
     plutil -convert xml1 -o /tmp/switchboard.plist deploy/default-settings.json
     defaults import com.fiavaion.switchboard /tmp/switchboard.plist
     ```
     Or set single keys: `defaults write com.fiavaion.switchboard showOtherSpaces -bool true`,
     `defaults write com.fiavaion.switchboard excludedBundleIDs -array com.example.examapp`,
     `defaults write com.fiavaion.switchboard triggerModifier -string option`.
   - *Enforced by MDM*: a Custom Settings (Application & Custom Settings) payload for the domain
     `com.fiavaion.switchboard` with the same keys. Values become managed; users can't change them.
   - Or have the user choose Import in Settings and pick the JSON file.

   Keys (all optional; missing keys fall back to app defaults): `triggerModifier`
   (`"command"`/`"option"`), `showMinimizedWindows`, `showHiddenApps`, `showOtherSpaces`,
   `excludedBundleIDs` (array of bundle IDs: add lab software here, e.g. exam or kiosk apps),
   `thumbnailSize` (`"small"`/`"medium"`/`"large"`/`"auto"`), `launchAtLogin`,
   `screenshotSaveToFolder`, `screenshotFolder`, `showScreenshotHUD`, `showStatusItem`.
4. **Launch at login.** `launchAtLogin: true` registers a per-user login item (`SMAppService`) the
   first time the app runs for that user. For the image to boot with Switchboard already running,
   launch it once per user profile, or have the MDM open it at first login.
5. **What the user still has to do: Screen Recording.** On first use, open System Settings >
   Privacy & Security > Screen & System Audio Recording, turn on Switchboard (a standard user may
   do this because of the profile), then quit and reopen Switchboard. The onboarding window
   (Check permissions… in the menu) deep-links there.
6. **Without Screen Recording** the app still works: the switcher shows app icon + window title
   instead of thumbnails (PRD D6). Screenshots use `/usr/sbin/screencapture` and are unaffected.

### M6 acceptance (corrected)
Imaged lab Mac boots with Switchboard installed, the PPPC profile applied, Accessibility
pre-granted, and Screen Recording user-enableable without an admin password. Cmd+Tab
switching works with no prompt; thumbnails appear after the user enables Screen Recording
once, and the switcher falls back to icon + title until then.
