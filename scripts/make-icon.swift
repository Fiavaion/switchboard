// Regenerates Resources/AppIcon.icns: the menu bar symbol on a blue squircle (macOS icon grid).
// Usage: swift scripts/make-icon.swift   (needs iconutil from the Command Line Tools)
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)   // 824/1024 content box
    let path = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.56, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.27, blue: 0.78, alpha: 1))!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = symbol.size
    symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! render(pt).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! render(pt * 2).write(to: iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
