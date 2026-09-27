// Smoke driver (PRD N4): posts real key events through the HID event stream, exactly as a
// keyboard would, and reports which window ends up focused. The process running it needs
// Accessibility (to post events) and Screen Recording (for `hold` screenshots).
//
//   swift scripts/smoke/drive.swift front                 # print focused app + window
//   swift scripts/smoke/drive.swift switch <tabs>         # Cmd down, Tab x N, Cmd up
//   swift scripts/smoke/drive.swift quick                 # Cmd+Tab released within ~1 ms (before the list loads)
//   swift scripts/smoke/drive.swift hold <tabs> <png>     # as switch, screenshot before release
//   swift scripts/smoke/drive.swift search <text> <png>   # Cmd+Tab, type text, screenshot, release
//   swift scripts/smoke/drive.swift cancel <png>          # Cmd+Tab, screenshot, Esc, release
//   swift scripts/smoke/drive.swift shot3 | shot4         # Cmd+Shift+3 / Cmd+Shift+4 (+Esc)
// Set MOD=option to drive Option+Tab instead.
import AppKit

let source = CGEventSource(stateID: .hidSystemState)
let modKey: CGKeyCode = ProcessInfo.processInfo.environment["MOD"] == "option" ? 58 : 55
let modFlag: CGEventFlags = modKey == 58 ? .maskAlternate : .maskCommand

func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, gap: useconds_t = 60_000) {
    let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
    e.flags = flags
    e.post(tap: .cghidEventTap)
    usleep(gap)
}
func tap(_ key: CGKeyCode, flags: CGEventFlags) { post(key, down: true, flags: flags); post(key, down: false, flags: flags) }
func modDown() { post(modKey, down: true, flags: modFlag) }
func modUp() { post(modKey, down: false, flags: []) }
func shot(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", path]
    try! p.run(); p.waitUntilExit()
}
/// LESSON-TEST-001: reads the window server, not NSWorkspace: without a running event loop
/// `frontmostApplication` is a stale cached value, and AX's system-wide focus query gets no
/// answer from some apps (Chrome). The topmost on-screen normal window is what the user sees.
func front() -> String {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // Apps like Chrome float untitled strips (tab bar, toolbar) above the real window.
    guard let top = list.first(where: {
        ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerName as String] as? String) != "Switchboard"
            && !(($0[kCGWindowName as String] as? String) ?? "").isEmpty
    }), let pid = top[kCGWindowOwnerPID as String] as? pid_t,
          let app = NSRunningApplication(processIdentifier: pid) else { return "?" }
    return "\(app.bundleIdentifier ?? "?") | \(top[kCGWindowName as String] as? String ?? "<untitled>")"
}
/// True when Switchboard's panel is on screen (layer .popUpMenu = 101).
func switcherVisible() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.contains { $0[kCGWindowOwnerName as String] as? String == "Switchboard" && $0[kCGWindowLayer as String] as? Int == 101 }
}
/// Never type letters with the modifier held unless the switcher is up: they would be shortcuts.
func requirePanel() {
    guard switcherVisible() else { modUp(); print("ABORT: switcher panel not visible"); exit(1) }
}
// Key codes for typing lowercase ASCII letters/digits/space in `search`.
let letters: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46," ":49]

let args = CommandLine.arguments.dropFirst().map { $0 }
let before = front()
switch args.first {
case "front":
    print(before); exit(0)
case "switch":
    modDown(); for _ in 0..<(Int(args[1]) ?? 1) { tap(48, flags: modFlag) }; modUp()
case "quick":
    post(modKey, down: true, flags: modFlag, gap: 500); post(48, down: true, flags: modFlag, gap: 500)
    post(48, down: false, flags: modFlag, gap: 500); post(modKey, down: false, flags: [], gap: 500)
case "hold":
    modDown(); for _ in 0..<(Int(args[1]) ?? 1) { tap(48, flags: modFlag) }
    usleep(700_000); shot(args[2]); modUp()
case "search":
    modDown(); tap(48, flags: modFlag); usleep(400_000); requirePanel()
    for ch in args[1].lowercased() { if let k = letters[ch] { tap(k, flags: modFlag) } }
    usleep(500_000); shot(args[2]); modUp()
case "cancel":
    modDown(); tap(48, flags: modFlag); usleep(600_000); requirePanel(); shot(args[1]); tap(53, flags: modFlag); modUp()
case "shot3", "shot4":
    let flags: CGEventFlags = [.maskCommand, .maskShift]
    let pb = NSPasteboard.general.changeCount
    post(55, down: true, flags: .maskCommand); post(56, down: true, flags: flags)
    tap(args[0] == "shot3" ? 20 : 21, flags: flags)
    post(56, down: false, flags: .maskCommand); post(55, down: false, flags: [])
    if args[0] == "shot4" { usleep(1_000_000); tap(53, flags: []) }   // leave interactive mode
    sleep(2)
    print("clipboard changed:", NSPasteboard.general.changeCount != pb)
    exit(0)
default:
    print("usage: see header"); exit(2)
}
sleep(1)   // Space switches animate (~0.6 s) before focus settles
print("before:", before)
print("after: ", front())
