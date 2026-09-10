import AppKit
import Combine
import LidSensor
import TransitionKit

/// Drives the preview area: a private renderer with its own desktop snapshot,
/// a scrubbable progress, and playback that mimics a lid close or a pour-out.
/// It is deliberately separate from the live overlay's renderer so tuning never
/// touches a transition that is actually playing.
@MainActor
public final class PreviewModel: ObservableObject {
    @Published public var progress: Double = 0 { didSet { if !isPlaying { render() } } }
    @Published public var followLid = false { didSet { followLidChanged() } }
    @Published public private(set) var isCapturing = false
    @Published public private(set) var hasSnapshot = false
    @Published public private(set) var isPlaying = false
    @Published public private(set) var frameTimeMs: Double = 0
    @Published public private(set) var errorText: String?

    public let renderer: TransitionRenderer
    public let registry: TransitionRegistry
    private let settings: AppSettings
    private let sensor: LidSensorMonitor
    private var driver: ProgressDriver
    private var playTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var frameTimes: [Double] = []

    /// Set by the SwiftUI representable when the Metal view exists.
    weak var metalView: MetalTransitionView?

    /// Optional spring parameters for "Play pour-out", read from the current
    /// transition's params JSON (Notch Drain has them; Fade and Frost don't).
    public var pourOutSpring: (response: Double, damping: Double, overshoot: Double) = (0.55, 0.72, 0.06)

    public init(registry: TransitionRegistry, settings: AppSettings, sensor: LidSensorMonitor) throws {
        renderer = try TransitionRenderer()
        self.registry = registry
        self.settings = settings
        self.sensor = sensor
        driver = ProgressDriver(startAngle: settings.startAngle, endAngle: settings.endAngle)

        registry.$current.sink { [weak self] _ in self?.render() }.store(in: &cancellables)
        sensor.$angle.receive(on: DispatchQueue.main).sink { [weak self] angle in
            guard let self, self.followLid, let angle else { return }
            self.driver.startAngle = self.settings.startAngle
            self.driver.endAngle = self.settings.endAngle
            self.progress = self.driver.rawProgress(angle: angle)
        }.store(in: &cancellables)
    }

    public var context: RenderContext {
        let geometry = NotchDetector.geometry(for: BuiltInDisplay.screen)
        return RenderContext(snapshotSize: renderer.snapshotSize,
                             sinkPoint: geometry.sinkPoint,
                             notchSize: geometry.notchSize,
                             usesVirtualNotch: geometry.isVirtual,
                             reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Grabs a fresh desktop snapshot (excluding our own windows).
    public func capture() {
        guard !isCapturing else { return }
        guard ScreenRecordingPermission.isGranted else {
            errorText = "Screen Recording permission is required for the preview."
            return
        }
        isCapturing = true
        errorText = nil
        Task { [weak self] in
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self else { return }
                try self.renderer.setSnapshot(image)
                self.hasSnapshot = true
                self.isCapturing = false
                self.render()
            } catch {
                self?.errorText = "Capture failed: \(error.localizedDescription)"
                self?.isCapturing = false
            }
        }
    }

    /// Parameters changed in Tuner: redraw at the current progress.
    public func paramsChanged() {
        render()
    }

    public func render() {
        guard let view = metalView else { return }
        view.transition = registry.current
        view.context = context
        view.progress = progress
        let start = CACurrentMediaTime()
        view.render()
        recordFrameTime((CACurrentMediaTime() - start) * 1000)
    }

    private func recordFrameTime(_ ms: Double) {
        frameTimes.append(ms)
        if frameTimes.count > 30 { frameTimes.removeFirst() }
        frameTimeMs = frameTimes.reduce(0, +) / Double(frameTimes.count)
    }

    // MARK: Playback

    /// Plays a close from 0 to 1 through the transition's own progress curve,
    /// at roughly the speed of a real lid close.
    public func playClose(duration: Double = 0.7) {
        followLid = false
        driver.reset()
        driver.curve = curveFromParams()
        driver.commitThreshold = 1
        var elapsed = 0.0
        run { [weak self] dt in
            guard let self else { return false }
            elapsed += dt
            let raw = min(elapsed / duration, 1)
            self.progress = self.driver.curve.value(at: raw)
            return raw < 1
        }
    }

    /// Plays a pour-out: spring from 1 back to 0 with overshoot into negative
    /// progress, exactly as the unlock flow does.
    public func playPourOut() {
        followLid = false
        driver.reset()
        driver.set(progress: 1)
        let spring = pourOutSpring
        driver.animate(to: -0.0, response: spring.response, damping: spring.damping)
        // Overshoot is expressed by letting the spring target sit slightly below
        // zero for the first part of the motion, then settle at zero.
        var settledAtZero = false
        run { [weak self] dt in
            guard let self else { return false }
            let p = self.driver.step(dt: dt, angle: nil)
            self.progress = max(p, -spring.overshoot)
            if !settledAtZero, p < 0.02 { settledAtZero = true }
            return !self.driver.isSpringSettled
        }
    }

    public func stop() {
        playTimer?.invalidate()
        playTimer = nil
        isPlaying = false
    }

    private func run(_ tick: @escaping (Double) -> Bool) {
        stop()
        isPlaying = true
        var last = CACurrentMediaTime()
        playTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let now = CACurrentMediaTime()
                let dt = min(now - last, 0.05)
                last = now
                let keepGoing = tick(dt)
                self.render()
                if !keepGoing { self.stop(); self.render() }
            }
        }
        RunLoop.main.add(playTimer!, forMode: .common)
    }

    private func followLidChanged() {
        if followLid { stop() }
    }

    private func curveFromParams() -> TunerBezier {
        guard let data = registry.current.paramsJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let curve = object["progressCurve"] as? [String: Double],
              let x1 = curve["x1"], let y1 = curve["y1"], let x2 = curve["x2"], let y2 = curve["y2"] else {
            return .linear
        }
        return TunerBezier(x1, y1, x2, y2)
    }
}

import Tuner
