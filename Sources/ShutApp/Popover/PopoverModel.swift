import AppKit
import Combine
import LidSensor
import SwiftUI
import TransitionKit
import Tuner

/// Everything the popover reads and every action it can take, so the view stays
/// declarative and can be rendered in a test without a running app.
@MainActor
final class PopoverModel: ObservableObject {
    let settings: AppSettings
    let registry: TransitionRegistry
    let preview: PreviewModel
    let sensor: LidSensorMonitor
    let thumbnails: TransitionThumbnailRenderer?

    /// Actions supplied by the app; tests pass no-ops.
    var play: () -> Void = {}
    var openTuner: () -> Void = {}
    var openWindow: () -> Void = {}
    var quit: () -> Void = { DispatchQueue.main.async { NSApp.terminate(nil) } }
    var allowScreenRecording: () -> Void = {}
    var relaunch: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var launchAtLogin: () -> Bool = { false }
    /// The featured dials for a style, drawn with Tuner rows.
    var featuredDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    var resetStyle: (String) -> Void = { _ in }

    @Published var stateDescription = "idle"
    @Published var thumbnailGeneration = 0
    /// Per-style counters so a changed dial re-draws one card, not the grid.
    @Published private(set) var thumbnailVersions: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, registry: TransitionRegistry, preview: PreviewModel, sensor: LidSensorMonitor,
         thumbnails: TransitionThumbnailRenderer?) {
        self.settings = settings
        self.registry = registry
        self.preview = preview
        self.sensor = sensor
        self.thumbnails = thumbnails
        registry.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Thumbnails draw over the real desktop once we have one.
        preview.onRealSnapshot = { [weak self] image in
            guard let self, let thumbnails = self.thumbnails else { return }
            if let small = Self.downscale(image, to: PlaceholderDesktop.defaultSize),
               (try? thumbnails.setBackdrop(small, isPlaceholder: false)) != nil {
                self.thumbnailGeneration += 1
                for t in self.registry.all { self.thumbnailVersions[t.id, default: 0] += 1 }
            }
        }
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sensor.$capability.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var statusLine: String {
        if !settings.isEnabled { return "Paused" }
        if registry.isSubstituting { return "\(registry.current.displayName) needs Screen Recording" }
        if BuiltInDisplay.screen == nil, BuiltInDisplay.externalCount > 0 {
            return "Lid shut on an external display: nothing to play"
        }
        let base: String
        switch sensor.capability {
        case .continuousAngle: base = "Following the lid"
        case .lidStateOnly: base = "Plays when the lid closes"
        case .unsupported: return "Preview only: no lid sensor on this Mac"
        }
        return BuiltInDisplay.externalCount > 0 ? "\(base), on the built-in display" : base
    }

    var needsPermissionCard: Bool {
        registry.current.needsSnapshot && !registry.captureAvailable
    }

    /// Speed: 0 = slow (100°), 1 = fast (20°).
    var speed: Double {
        get { 1 - (settings.bandDegrees - AppSettings.bandRange.lowerBound) / (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
        set { settings.bandDegrees = AppSettings.bandRange.upperBound - newValue * (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
    }

    func select(_ id: String) {
        guard let transition = registry.transition(id: id) else {
            Log.app.error("select: unknown style \(id, privacy: .public)")
            return
        }
        registry.select(id: id)
        settings.transitionID = id
        Log.app.info("style selected: \(id, privacy: .public)")
        // Every style is the untouched desktop at Open, so a pick made with the
        // scrubber resting there would look like nothing happened. Glide to the
        // point where the style is recognisable; a scrubber already mid-way just
        // re-renders in place.
        if preview.progress < 0.05, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preview.glide(to: transition.thumbnailProgress)
        } else {
            preview.render()
        }
    }

    func thumbnail(for transition: TransitionKit.AnyTransition) -> CGImage? {
        thumbnails?.image(for: transition)
    }

    private static func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func invalidateThumbnail(id: String) {
        thumbnails?.invalidate(id: id)
        thumbnailGeneration += 1
        thumbnailVersions[id, default: 0] += 1
    }

    func thumbnailVersion(for id: String) -> Int { thumbnailVersions[id] ?? 0 }
}
