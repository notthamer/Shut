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
    var quit: () -> Void = { NSApp.terminate(nil) }
    var allowScreenRecording: () -> Void = {}
    var relaunch: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var launchAtLogin: () -> Bool = { false }
    /// The featured dials for a style, drawn with Tuner rows.
    var featuredDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    var resetStyle: (String) -> Void = { _ in }

    @Published var stateDescription = "idle"
    @Published var thumbnailGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, registry: TransitionRegistry, preview: PreviewModel, sensor: LidSensorMonitor,
         thumbnails: TransitionThumbnailRenderer?) {
        self.settings = settings
        self.registry = registry
        self.preview = preview
        self.sensor = sensor
        self.thumbnails = thumbnails
        registry.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sensor.$capability.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var statusLine: String {
        if !settings.isEnabled { return "Paused" }
        if registry.isSubstituting { return "\(registry.current.displayName) needs Screen Recording" }
        switch sensor.capability {
        case .continuousAngle: return "Following the lid"
        case .lidStateOnly: return "Plays when the lid closes"
        case .unsupported: return "Preview only: no lid sensor on this Mac"
        }
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
        registry.select(id: id)
        settings.transitionID = id
        preview.render()
    }

    func thumbnail(for transition: TransitionKit.AnyTransition) -> CGImage? {
        thumbnails?.image(for: transition)
    }

    func invalidateThumbnail(id: String) {
        thumbnails?.invalidate(id: id)
        thumbnailGeneration += 1
    }
}
