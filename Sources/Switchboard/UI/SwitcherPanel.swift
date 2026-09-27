import AppKit
import Combine
import SwiftUI
import SwitchboardCore

/// PRD F1.1 / F1.8 — the floating switcher. A non-activating, never-key panel: keyboard input
/// arrives through the event tap, so the app being switched away from keeps focus until release.
final class SwitcherPanel {
    private static let tilePadding: Double = 8, spacing: Double = 8, margin: Double = 16

    private let panel: NSPanel
    private let hosting: NSHostingView<SwitcherView>
    private let model: SwitcherModel
    private var screen: NSScreen?
    private var subscription: AnyCancellable?

    init(model: SwitcherModel, onPick: @escaping (Int) -> Void) {
        self.model = model
        hosting = NSHostingView(rootView: SwitcherView(model: model, onPick: onPick))
        panel = KeylessPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = hosting
        panel.setAccessibilityLabel("Window switcher")
        // Search narrows the list: keep the panel sized to its content and centred.
        subscription = model.$state.map(\.visible.count).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
    }

    func show(on screen: NSScreen) {
        self.screen = screen
        layout()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        screen = nil
    }

    private func layout() {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let tile = model.tileWidth + 2 * Self.tilePadding
        let fit = Int((visible.width * 0.9 - 2 * Self.margin + Self.spacing) / (tile + Self.spacing))
        model.columns = max(1, min(model.state.visible.count, fit))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: min(size.height, visible.height)), display: true)
    }
}

private final class KeylessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if !model.state.query.isEmpty {
                Label(model.state.query, systemImage: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .accessibilityLabel("Search: \(model.state.query)")
            }
            if model.state.visible.isEmpty {
                Text(model.state.query.isEmpty ? "No windows" : "No matching windows")
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.tileWidth + 16), spacing: 8), count: model.columns),
                          spacing: 8) {
                    ForEach(Array(model.state.visible.enumerated()), id: \.element.id) { index, window in
                        WindowTile(window: window, selected: index == model.state.selectedIndex,
                                   icon: model.icon(for: window.pid), thumbnail: model.thumbnails[window.id],
                                   width: model.tileWidth) { onPick(index) }
                    }
                }
            }
        }
        .padding(16)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct WindowTile: View {
    let window: WindowInfo
    let selected: Bool
    let icon: NSImage
    let thumbnail: CGImage?
    let width: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    preview.frame(width: width, height: width * 0.625)
                    if thumbnail != nil {
                        Image(nsImage: icon).resizable().frame(width: 28, height: 28).offset(x: 4, y: 4)
                    }
                }
                HStack(spacing: 4) {
                    if window.isMinimized { Image(systemName: "minus.circle.fill") }
                    if window.isAppHidden { Image(systemName: "eye.slash") }
                    Text(window.title.isEmpty ? window.appName : window.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                }
                .frame(width: width)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.35) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SwitcherModel.accessibilityLabel(for: window))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: min(96, width * 0.45))
        }
    }
}

/// HUD material, or an opaque background when Reduce Transparency is on.
struct PanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            VisualEffect()
        }
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
