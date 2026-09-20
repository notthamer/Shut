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
    let stayAwake: StayAwakeController

    /// Actions supplied by the app; tests pass no-ops.
    var openTuner: () -> Void = {}
    var openWindow: () -> Void = {}
    var quit: () -> Void = { DispatchQueue.main.async { NSApp.terminate(nil) } }
    var allowScreenRecording: () -> Void = {}
    var relaunch: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var launchAtLogin: () -> Bool = { false }
    /// nil when there is no updater (a build not signed for release): the switch is hidden.
    var automaticUpdates: () -> Bool? = { nil }
    var setAutomaticUpdates: (Bool) -> Void = { _ in }
    /// The featured dials for a style, drawn with Tuner rows.
    var featuredDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// The rest of a style's dials, grouped in folders, for "All dials".
    var moreDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Presets, copy, paste, import and export for a style.
    var shareView: (String, Binding<Bool>) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var resetStyle: (String) -> Void = { _ in }

    /// The panel has two pages of the same size: the lid styles, and Stay awake.
    enum Page { case styles, awake }
    @Published var page: Page = .styles
    @Published var showingAwakeConsent = false

    @Published var stateDescription = "idle"
    @Published var thumbnailGeneration = 0
    /// Per-style counters so a changed dial re-draws one card, not the grid.
    @Published private(set) var thumbnailVersions: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Tests pass no `stayAwake` and get one on throwaway defaults that is never started.
    init(settings: AppSettings, registry: TransitionRegistry, preview: PreviewModel, sensor: LidSensorMonitor,
         thumbnails: TransitionThumbnailRenderer?, stayAwake: StayAwakeController? = nil) {
        self.stayAwake = stayAwake ?? StayAwakeController(
            settings: StayAwakeSettings(defaults: UserDefaults(suiteName: "StayAwake-\(UUID().uuidString)") ?? .standard))
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
        self.stayAwake.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sensor.$capability.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    /// The status line's button. The first switch-on opens the page and explains itself.
    func performAwake(_ action: AwakeText.Action) {
        if action == .turnOn, stayAwake.needsConsent {
            page = .awake
            showingAwakeConsent = true
        } else {
            stayAwake.perform(action)
        }
    }

    func toggleAwake() {
        if stayAwake.needsConsent { showingAwakeConsent = true }
        else { stayAwake.settings.isOn.toggle() }
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

    /// Running and doing what it says: nothing the header needs to spell out. The
    /// permission card speaks for a style that is standing in, so that counts too.
    var statusIsOrdinary: Bool {
        guard settings.isEnabled else { return false }
        if BuiltInDisplay.screen == nil, BuiltInDisplay.externalCount > 0 { return false }
        return sensor.capability != .unsupported
    }

    /// Set once "Allow…" has opened System Settings: from then on the card's next step is
    /// the restart macOS needs before the permission counts.
    @Published var askedForScreenRecording = false
    /// The folded Settings on the Awake page.
    @Published var showingAwakeSettings = false

    var needsPermissionCard: Bool {
        registry.current.needsSnapshot && !registry.captureAvailable
    }

    /// Speed: 0 = slow (the whole close), 1 = fast (the last 20°).
    var speed: Double {
        get { 1 - (settings.bandDegrees - AppSettings.bandRange.lowerBound) / (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
        set { settings.bandDegrees = AppSettings.bandRange.upperBound - newValue * (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
    }

    /// Where the effect really starts, in degrees above shut: the requested band
    /// after the calibration caps it under this lid's rest angle.
    var effectiveStartDegrees: Double {
        let range = sensor.calibration.animationRange(bandDegrees: settings.bandDegrees)
        return range.upperBound - range.lowerBound
    }

    func select(_ id: String) {
        guard let transition = registry.transition(id: id) else {
            Log.app.error("select: unknown style \(id, privacy: .public)")
            return
        }
        registry.select(id: id)
        settings.transitionID = id
        Log.app.info("style selected: \(id, privacy: .public)")
        // Every style is the untouched desktop at Open, so a pick would look like
        // nothing happened. Play the whole round, close and open, as if Play had
        // been pressed. Under Reduce Motion, glide to the recognisable frame instead.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preview.glide(to: transition.thumbnailProgress)
        } else {
            preview.playRound()
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
