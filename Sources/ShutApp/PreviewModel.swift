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
    /// The picture behind mask styles (Shutter, Fade), which draw with alpha
    /// over whatever is beneath them: on the lid that is the live desktop, in
    /// the preview it has to be the snapshot itself.
    @Published public private(set) var snapshotImage: CGImage?
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
    /// Called with every real desktop capture (never the placeholder).
    var onRealSnapshot: ((CGImage) -> Void)?
    private var previewVelocity = 0.0
    private var lastRenderedProgress = 0.0

    /// Spring parameters for "Play pour-out", read from the current transition's
    /// params (Sinkhole has them; Fade and Frost fall back to the defaults).
    public var pourOutSpring: (response: Double, damping: Double, overshoot: Double) {
        let t = registry.current
        return (t.doubleParam("pourOutResponse", default: 0.55),
                t.doubleParam("pourOutDamping", default: 0.72),
                t.doubleParam("overshoot", default: 0.06))
    }

    public init(registry: TransitionRegistry, settings: AppSettings, sensor: LidSensorMonitor) throws {
        renderer = try TransitionRenderer()
        self.registry = registry
        self.settings = settings
        self.sensor = sensor
        driver = ProgressDriver()

        registry.$current.sink { [weak self] _ in self?.render() }.store(in: &cancellables)
        sensor.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self, self.followLid, let state else { return }
            self.progress = state.progress
        }.store(in: &cancellables)
    }

    public var context: RenderContext {
        let geometry = NotchDetector.geometry(for: BuiltInDisplay.screen)
        let range = sensor.animationRange
        return RenderContext(snapshotSize: renderer.snapshotSize,
                             sinkPoint: geometry.sinkPoint,
                             notchSize: geometry.notchSize,
                             usesVirtualNotch: geometry.isVirtual,
                             reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                             scale: Float(BuiltInDisplay.screen?.backingScaleFactor ?? 2),
                             velocity: Float(previewVelocity),
                             hingeTravelDegrees: Float(max(range.upperBound - range.lowerBound, 10)))
    }

    /// True while the preview shows the drawn stand-in rather than the real desktop.
    @Published public private(set) var usesPlaceholder = false

    /// Grabs a fresh desktop snapshot (excluding our own windows), or falls back to
    /// the drawn placeholder so the preview always shows something.
    public func capture() {
        guard !isCapturing else { return }
        guard ScreenRecordingPermission.isGranted else {
            if let placeholder = PlaceholderDesktop.image(), (try? renderer.setSnapshot(placeholder)) != nil {
                snapshotImage = placeholder
                hasSnapshot = true
                usesPlaceholder = true
                errorText = nil
                render()
            }
            return
        }
        isCapturing = true
        errorText = nil
        Task { [weak self] in
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self else { return }
                try self.renderer.setSnapshot(image)
                self.snapshotImage = image
                self.hasSnapshot = true
                self.usesPlaceholder = false
                self.isCapturing = false
                self.render()
                self.onRealSnapshot?(image)
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
        view.isTransparent = registry.current.isTransparent
        view.context = context
        view.progress = progress
        lastRenderedProgress = progress
        let start = CACurrentMediaTime()
        view.render()
        recordFrameTime((CACurrentMediaTime() - start) * 1000)
    }

    private var frameTimePublishScheduled = false

    /// Never publishes synchronously: `render()` runs inside SwiftUI's view update
    /// (from `updateNSView`), and publishing there re-triggers the update forever.
    private func recordFrameTime(_ ms: Double) {
        frameTimes.append(ms)
        if frameTimes.count > 30 { frameTimes.removeFirst() }
        guard !frameTimePublishScheduled else { return }
        frameTimePublishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.frameTimePublishScheduled = false
            let mean = self.frameTimes.reduce(0, +) / Double(max(self.frameTimes.count, 1))
            if abs(mean - self.frameTimeMs) > 0.02 { self.frameTimeMs = mean }
        }
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
            let next = self.driver.curve.value(at: raw)
            self.previewVelocity += ((next - self.progress) / max(dt, 0.001) - self.previewVelocity) * min(1, dt / 0.05)
            self.progress = next
            return raw < 1
        }
    }

    /// Plays a pour-out: spring from 1 back to 0, dipping below zero by at most
    /// the overshoot parameter, exactly as the unlock flow does.
    public func playPourOut() {
        followLid = false
        driver.reset()
        driver.set(progress: 1)
        let spring = pourOutSpring
        driver.animate(to: 0, response: spring.response, damping: spring.damping)
        run { [weak self] dt in
            guard let self else { return false }
            let p = self.driver.step(dt: dt, hinge: nil)
            let next = max(p, -spring.overshoot)
            self.previewVelocity += ((next - self.progress) / max(dt, 0.001) - self.previewVelocity) * min(1, dt / 0.05)
            self.progress = next
            return !self.driver.isSettled
        }
    }

    /// Eases the scrubber to a progress over `duration` on the strong ease-out,
    /// so a style change is visible even when the lid rests at Open.
    public func glide(to target: Double, duration: Double = 0.4) {
        followLid = false
        let start = progress
        guard abs(target - start) > 0.001 else { render(); return }
        var elapsed = 0.0
        run { [weak self] dt in
            guard let self else { return false }
            elapsed += dt
            let t = min(elapsed / duration, 1)
            let eased = 1 - pow(1 - t, 3)
            self.progress = start + (target - start) * eased
            return t < 1
        }
    }

    public func stop() {
        playTimer?.invalidate()
        playTimer = nil
        isPlaying = false
        previewVelocity = 0
    }

    /// Close, then open: the whole round, in the preview.
    public func playRound() {
        playClose(duration: 0.9)
        onFinished = { [weak self] in
            self?.onFinished = nil
            self?.playPourOut()
        }
    }

    private var onFinished: (() -> Void)?

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
                if !keepGoing {
                    self.stop(); self.render()
                    let next = self.onFinished
                    next?()
                }
            }
        }
        playTimer?.tolerance = 0.002
        RunLoop.main.add(playTimer!, forMode: .common)
    }

    private func followLidChanged() {
        if followLid { stop() }
    }

    private func curveFromParams() -> TunerBezier {
        registry.current.bezierParam("progressCurve")
    }
}

import Tuner
