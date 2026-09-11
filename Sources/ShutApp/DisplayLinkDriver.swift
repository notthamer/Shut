import AppKit
import QuartzCore

/// Thin wrapper around the macOS 14 `CADisplayLink` so callers just get a
/// closure with the frame delta. Stopped links cost nothing.
final class DisplayLinkDriver {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let screen: NSScreen
    var onFrame: ((Double) -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
    }

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        lastTimestamp = nil
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp.map { min(max(now - $0, 0.001), 0.05) } ?? (1.0 / 60)
        lastTimestamp = now
        onFrame?(dt)
    }
}
