import AppKit
import Combine
import LidSensor
import TransitionKit

/// The lid-close state machine. Owns the overlay and decides, from the sensor
/// and power notifications, when to capture, show, animate, reverse, and tear
/// down. Everything here runs on the main actor.
@MainActor
public final class AppController: ObservableObject {
    public enum State: String {
        case idle        // lid open, nothing on screen
        case armed       // lid approaching start angle; snapshot captured or in flight
        case closing     // overlay visible, progress follows the lid
        case reversing   // lid reopened; spring back to 0 then tear down
        case asleep      // display slept; overlay hidden, snapshot released
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var progress: Double = 0

    public let settings: AppSettings
    public let sensor: LidSensorMonitor
    public let registry: TransitionRegistry
    public let renderer: TransitionRenderer

    private var overlay: OverlayWindow?
    private var displayLink: DisplayLinkDriver?
    private var driver: ProgressDriver
    private var cancellables = Set<AnyCancellable>()
    private var captureTask: Task<Void, Never>?
    private var lastCaptureDate: Date = .distantPast
    private var shownAt: Date?
    private var lastAngle: Double?

    /// How far above the start angle we arm and capture. Wide enough that the
    /// snapshot is ready before the overlay is needed even on a fast close.
    private let armMargin = 12.0
    /// PRD 5.5: reopen past start + 5° reverses and tears down.
    private let hysteresis = 5.0
    /// PRD 7: no sensor sample for this long during a close hides the overlay.
    private let watchdogInterval: TimeInterval = 0.5

    /// Set by the Tuner host so the panel can hide while a real transition plays.
    public var onTransitionVisibilityChanged: ((Bool) -> Void)?

    public init(settings: AppSettings, sensor: LidSensorMonitor, registry: TransitionRegistry, renderer: TransitionRenderer) {
        self.settings = settings
        self.sensor = sensor
        self.registry = registry
        self.renderer = renderer
        self.driver = ProgressDriver(startAngle: settings.startAngle, endAngle: settings.endAngle)

        sensor.$angle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] angle in
                guard let self, let angle else { return }
                self.handle(angle: angle)
            }
            .store(in: &cancellables)

        settings.$startAngle.combineLatest(settings.$endAngle)
            .sink { [weak self] start, end in
                self?.driver.startAngle = start
                self?.driver.endAngle = end
            }
            .store(in: &cancellables)

        settings.$isEnabled
            .sink { [weak self] enabled in if !enabled { self?.teardown(reason: "disabled") } }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    // MARK: - Sensor

    private func handle(angle: Double) {
        lastAngle = angle
        guard settings.isEnabled else { return }
        let start = settings.startAngle

        switch state {
        case .idle:
            if angle < start + armMargin { arm() }

        case .armed:
            if angle > start + armMargin + hysteresis {
                disarm()
            } else if angle <= start {
                beginClose()
            } else if Date().timeIntervalSince(lastCaptureDate) > 1.0, abs(sensor.velocity) < 2 {
                // Lid is resting near the start angle: keep the snapshot fresh so
                // a later close doesn't show stale content.
                capture()
            }

        case .closing:
            if angle > start + hysteresis { beginReverse() }

        case .reversing:
            if angle <= start { resumeClose() }

        case .asleep:
            break
        }
    }

    // MARK: - Transitions between states

    private func arm() {
        state = .armed
        capture()
    }

    private func disarm() {
        captureTask?.cancel()
        captureTask = nil
        renderer.clearSnapshot()
        state = .idle
    }

    private func capture() {
        guard captureTask == nil else { return }
        guard ScreenRecordingPermission.isGranted else {
            Log.capture.warning("Screen Recording not granted; cannot arm")
            state = .idle
            return
        }
        lastCaptureDate = Date()
        captureTask = Task { [weak self] in
            let started = Date()
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self, !Task.isCancelled else { return }
                try self.renderer.setSnapshot(image)
                Log.capture.info("snapshot ready in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                self.captureTask = nil
                // If the lid crossed the start angle while we were capturing, go now.
                if self.state == .armed, let angle = self.lastAngle, angle <= self.settings.startAngle {
                    self.beginClose()
                }
            } catch {
                Log.capture.error("capture failed: \(error.localizedDescription)")
                self?.captureTask = nil
            }
        }
    }

    private func beginClose() {
        guard renderer.snapshot != nil else { return }  // capture still in flight; retried on arrival
        guard let screen = BuiltInDisplay.screen else { return }

        let transition = registry.effectiveForLid
        let context = makeContext(screen: screen)
        driver.reset()
        driver.curve = curveFor(transition)
        driver.commitThreshold = commitThresholdFor(transition)

        if overlay == nil {
            overlay = OverlayWindow(screen: screen, renderer: renderer, transition: transition, context: context)
        }
        overlay?.metalView.transition = transition
        overlay?.metalView.context = context
        overlay?.metalView.progress = 0
        overlay?.metalView.render()
        overlay?.show(on: screen)
        shownAt = Date()
        state = .closing
        onTransitionVisibilityChanged?(true)
        Log.overlay.info("overlay shown (\(transition.id))")

        if displayLink == nil { displayLink = DisplayLinkDriver(screen: screen) }
        displayLink?.onFrame = { [weak self] dt in self?.frame(dt: dt) }
        displayLink?.start()
    }

    private func beginReverse() {
        state = .reversing
        driver.animate(to: 0, response: 0.3, damping: 1.0)
    }

    private func resumeClose() {
        state = .closing
        driver.follow()
    }

    /// Hide everything and drop the snapshot. Safe to call from any state.
    func teardown(reason: String) {
        displayLink?.stop()
        overlay?.hide()
        captureTask?.cancel()
        captureTask = nil
        renderer.clearSnapshot()
        if state != .idle { Log.overlay.info("teardown: \(reason)") }
        if shownAt != nil { onTransitionVisibilityChanged?(false) }
        shownAt = nil
        progress = 0
        state = .idle
    }

    // MARK: - Per frame

    private func frame(dt: Double) {
        guard let overlay else { return }

        // Watchdog: a stalled sensor during a close must never leave a frozen frame.
        if state == .closing, let last = sensor.lastSampleDate, Date().timeIntervalSince(last) > watchdogInterval {
            Log.lid.error("sensor watchdog fired; hiding overlay")
            teardown(reason: "sensor watchdog")
            return
        }

        let p = driver.step(dt: dt, angle: lastAngle)
        progress = p
        overlay.metalView.progress = p
        overlay.metalView.context.time = Float(Date().timeIntervalSince(shownAt ?? Date()))
        overlay.metalView.render()

        if state == .reversing, driver.isSpringSettled {
            teardown(reason: "lid reopened")
            // Lid is open but may still be near the start angle; re-arm cheaply.
            if let angle = lastAngle, angle < settings.startAngle + armMargin { arm() }
        }
    }

    // MARK: - Power

    @objc private func willSleep(_ note: Notification) {
        Log.app.info("sleep: \(note.name.rawValue)")
        teardown(reason: "sleep")
        state = .asleep
    }

    @objc private func didWake(_ note: Notification) {
        Log.app.info("wake: \(note.name.rawValue)")
        if state == .asleep { state = .idle }
    }

    // MARK: - Helpers

    func makeContext(screen: NSScreen) -> RenderContext {
        let geometry = NotchDetector.geometry(for: screen)
        return RenderContext(
            snapshotSize: renderer.snapshotSize,
            sinkPoint: geometry.sinkPoint,
            notchSize: geometry.notchSize,
            usesVirtualNotch: geometry.isVirtual,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    /// Transitions expose their progress curve through their params JSON; the
    /// driver reads it so the lid mapping honours the Tuner setting.
    private func curveFor(_ transition: AnyTransition) -> Tuner.TunerBezier {
        guard let data = transition.paramsJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let curve = object["progressCurve"] as? [String: Double],
              let x1 = curve["x1"], let y1 = curve["y1"], let x2 = curve["x2"], let y2 = curve["y2"] else {
            return .linear
        }
        return TunerBezier(x1, y1, x2, y2)
    }

    private func commitThresholdFor(_ transition: AnyTransition) -> Double {
        guard let data = transition.paramsJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let threshold = object["commitThreshold"] as? Double else { return 1 }
        return threshold
    }
}

import Tuner
