import AppKit
import SwiftUI

/// PRD F2.4 — brief "Copied to clipboard" confirmation near the bottom of the active screen.
final class HUD {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return p
    }()
    private var hideWork: DispatchWorkItem?

    func show(_ message: String) {
        let hosting = NSHostingView(rootView: HUDView(message: message))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 120, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                     completionHandler: { panel.orderOut(nil) })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

private struct HUDView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "doc.on.clipboard")
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(PanelBackground())
            .clipShape(Capsule())
    }
}
