import AppKit
import ScreenCaptureKit
import os

/// PRD F1.5 / D6 — window thumbnails via ScreenCaptureKit, cached for at most 30 windows (N2).
/// Callers check Screen Recording first; without it the panel shows icon + title.
final class Thumbnailer {
    static let cacheLimit = 30
    private var cache: [CGWindowID: CGImage] = [:]
    private var recency: [CGWindowID] = []

    func cached(_ id: CGWindowID) -> CGImage? { cache[id] }

    /// Captures `ids` (at most `cacheLimit`), calling `update` on the main thread per image.
    /// Cancel the returned task when the switcher closes.
    func refresh(_ ids: [CGWindowID], width: Double, update: @escaping (CGWindowID, CGImage) -> Void) -> Task<Void, Never> {
        let wanted = Array(ids.prefix(Self.cacheLimit))
        return Task.detached(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
                await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                    for id in wanted {
                        guard let window = byID[id] else { continue }
                        group.addTask { (id, try? await Self.capture(window, width: width)) }
                    }
                    for await (id, image) in group {
                        guard let image, !Task.isCancelled else { continue }
                        await MainActor.run {
                            self.store(id, image)
                            update(id, image)
                        }
                    }
                }
            } catch {
                Logger.capture.error("Thumbnail enumeration failed: \(error.localizedDescription)")
            }
        }
    }

    private static func capture(_ window: SCWindow, width: Double) async throws -> CGImage {
        let config = SCStreamConfiguration()
        let scale = 2.0
        let aspect = window.frame.height / max(window.frame.width, 1)
        config.width = Int(width * scale)
        config.height = max(Int(width * scale * aspect), 1)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }

    private func store(_ id: CGWindowID, _ image: CGImage) {
        cache[id] = image
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
        while recency.count > Self.cacheLimit { cache[recency.removeLast()] = nil }
    }
}
