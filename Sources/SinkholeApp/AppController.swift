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
        case drained     // asleep or just woken: overlay is solid black, no snapshot
        case pouring     // unlocked: fresh snapshot springing from p = 1 back to 0
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
    private var armedAt: Date = .distantPast
    private var permissionCheckedAt: Date = .distantPast
    private var permissionGranted = false
    private var hasWarnedAboutPermission = false
    private var shownAt: Date?
    private var lastAngle: Double?

    // Pour-out (PRD 5.7)
    private let unlock = UnlockObserver()
    private var screensAsleep = false
    private var blackSince: Date?
    private var safetyTimer: Timer?
    private var pourOutWorkItem: DispatchWorkItem?
    /// PRD 5.7 safety rule: black overlay visible while awake and unlocked for
    /// longer than this is force-hidden, whatever state we think we're in.
    private let blackScreenLimit: TimeInterval = 1.5

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
        workspace.addObserver(self, selector: #selector(screensSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)

        unlock.onUnlock = { [weak self] in self?.sessionUnlocked() }
        unlock.onLock = { [weak self] in self?.blackSince = nil }

        // The safety timer runs for the life of the app. It's a 4 Hz check of a
        // few booleans, so it costs nothing, and it is the last line of defence
        // against a black screen.
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.safetyCheck() }
        }
    }

    // MARK: - Sensor

    private func handle(angle: Double) {
        lastAngle = angle
        guard settings.isEnabled else { return }
        let start = settings.startAngle

        switch state {
        case .idle:
            // Re-check the permission at most every 2 s, so a missing grant logs
            // once instead of at the sensor's 120 Hz.
            if Date().timeIntervalSince(permissionCheckedAt) > 2 {
                permissionCheckedAt = Date()
                let granted = ScreenRecordingPermission.isGranted
                if !granted, !hasWarnedAboutPermission {
                    hasWarnedAboutPermission = true
                    Log.capture.warning("Screen Recording not granted; lid transitions disabled until relaunch")
                }
                permissionGranted = granted
            }
            if permissionGranted, angle < start + armMargin { arm() }

        case .armed:
            if angle > start + armMargin + hysteresis {
                disarm()
            } else if angle <= start {
                beginClose()
            } else if Date().timeIntervalSince(lastCaptureDate) > 1.0,
                      Date().timeIntervalSince(armedAt) < 6.0, abs(sensor.velocity) < 2 {
                // Lid is resting near the start angle: keep the snapshot fresh for a
                // few seconds so a close doesn't show stale content. After that we
                // stop, so a lid parked at 85° costs nothing.
                capture()
            } else if Date().timeIntervalSince(lastCaptureDate) > 6.0, sensor.velocity < -5 {
                // Parked for a while and now closing: grab one fresh frame. If the
                // lid beats it to the start angle the previous snapshot is used.
                capture()
            }

        case .closing:
            if angle > start + hysteresis { beginReverse() }

        case .reversing:
            if angle <= start { resumeClose() }

        case .drained, .pouring:
            break
        }
    }

    // MARK: - Transitions between states

    private func arm() {
        state = .armed
        armedAt = Date()
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
            permissionGranted = false
            state = .idle
            return
        }
        lastCaptureDate = Date()
        captureTask = Task { [weak self] in
            let started = Date()
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self, !Task.isCancelled else { return }
                self.captureTask = nil
                // Never swap the snapshot under a transition that's already playing.
                guard self.state == .armed else { return }
                try self.renderer.setSnapshot(image)
                Log.capture.info("snapshot ready in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
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
        overlay?.metalView.isBlackedOut = false
        blackSince = nil
        pourOutWorkItem?.cancel()
        pourOutWorkItem = nil
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

        var p = driver.step(dt: dt, angle: lastAngle)
        if state == .pouring {
            // The spring may dip below zero; the transition's overshoot parameter
            // caps how far, which the shader turns into the splash.
            p = max(p, -pourOutOvershoot)
        }
        progress = p
        overlay.metalView.progress = p
        overlay.metalView.context.time = Float(Date().timeIntervalSince(shownAt ?? Date()))
        overlay.metalView.render()

        if state == .reversing, driver.isSpringSettled {
            teardown(reason: "lid reopened")
            // Lid is open but may still be near the start angle; re-arm cheaply.
            if let angle = lastAngle, angle < settings.startAngle + armMargin { arm() }
        } else if state == .pouring, driver.isSpringSettled {
            teardown(reason: "pour-out complete")
        }
    }

    private var pourOutOvershoot: Double = 0.06

    // MARK: - Power and pour-out (PRD 5.7)

    @objc private func willSleep(_ note: Notification) {
        Log.app.info("sleep: \(note.name.rawValue)")
        enterDrained()
    }

    @objc private func screensSlept(_ note: Notification) {
        Log.app.info("screens slept")
        screensAsleep = true
        enterDrained()
    }

    @objc private func didWake(_ note: Notification) {
        Log.app.info("wake: \(note.name.rawValue)")
        wakeUp()
    }

    @objc private func screensWoke(_ note: Notification) {
        Log.app.info("screens woke")
        screensAsleep = false
        wakeUp()
    }

    /// Step 1: release the snapshot and go solid black. The overlay stays ordered
    /// in through sleep so the desktop is never visible between wake and pour-out.
    private func enterDrained() {
        guard settings.isEnabled, state != .drained else { return }
        displayLink?.stop()
        captureTask?.cancel()
        captureTask = nil
        pourOutWorkItem?.cancel()
        renderer.clearSnapshot()

        guard let screen = BuiltInDisplay.screen else { state = .idle; return }
        if overlay == nil {
            overlay = OverlayWindow(screen: screen, renderer: renderer, transition: registry.effectiveForLid,
                                    context: makeContext(screen: screen))
        }
        overlay?.metalView.isBlackedOut = true
        overlay?.metalView.render()
        overlay?.show(on: screen)
        if shownAt == nil { onTransitionVisibilityChanged?(true) }
        shownAt = Date()
        blackSince = nil
        state = .drained
        Log.overlay.info("drained: black overlay in place")
    }

    /// Step 2/3: on wake, either wait for the unlock notification or, with no
    /// password, pour out straight away.
    private func wakeUp() {
        guard state == .drained else { return }
        unlock.refresh()
        overlay?.metalView.render()  // repaint black after the display comes back
        if unlock.isLocked {
            Log.unlock.info("awake and locked; waiting for unlock")
        } else {
            Log.unlock.info("awake and unlocked; pouring out now")
            sessionUnlocked()
        }
    }

    private func sessionUnlocked() {
        guard state == .drained, !screensAsleep else { return }
        let delay = registry.effectiveForLid.doubleParam("pourOutDelayMs", default: 0) / 1000
        pourOutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginPourOut() }
        pourOutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Step 3/4: fresh snapshot (the overlay is excluded, so it sees the desktop
    /// underneath), then spring from p = 1 to 0.
    private func beginPourOut() {
        guard state == .drained, let overlay, let screen = BuiltInDisplay.screen else { return }
        guard ScreenRecordingPermission.isGranted else {
            teardown(reason: "pour-out without screen recording permission")
            return
        }
        blackSince = Date()  // the safety clock starts here: unlocked, awake, black
        let transition = registry.effectiveForLid
        captureTask = Task { [weak self] in
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self, !Task.isCancelled, self.state == .drained else { return }
                try self.renderer.setSnapshot(image)
                self.captureTask = nil

                overlay.metalView.transition = transition
                overlay.metalView.context = self.makeContext(screen: screen)
                overlay.metalView.isBlackedOut = false
                self.pourOutOvershoot = transition.doubleParam("overshoot", default: 0.06)
                self.driver.reset()
                self.driver.set(progress: 1)
                self.driver.animate(to: 0,
                                    response: transition.doubleParam("pourOutResponse", default: 0.55),
                                    damping: transition.doubleParam("pourOutDamping", default: 0.72))
                self.state = .pouring
                self.blackSince = nil
                self.shownAt = Date()
                Log.overlay.info("pour-out started (\(transition.id))")

                if self.displayLink == nil { self.displayLink = DisplayLinkDriver(screen: screen) }
                self.displayLink?.onFrame = { [weak self] dt in self?.frame(dt: dt) }
                self.displayLink?.start()
            } catch {
                Log.capture.error("pour-out capture failed: \(error.localizedDescription); hiding")
                self?.teardown(reason: "pour-out capture failed")
            }
        }
    }

    /// PRD 5.7 safety rule, evaluated 4× a second regardless of state.
    private func safetyCheck() {
        guard let overlay, overlay.isVisible, overlay.metalView.isBlackedOut else { blackSince = nil; return }
        let awakeAndUnlocked = !screensAsleep && !unlock.isLocked
        guard awakeAndUnlocked else { blackSince = nil; return }
        if blackSince == nil { blackSince = Date(); return }
        if Date().timeIntervalSince(blackSince!) > blackScreenLimit {
            Log.overlay.error("SAFETY: black overlay visible \(self.blackScreenLimit)s while awake+unlocked in state \(self.state.rawValue); force hiding")
            teardown(reason: "black screen safety")
        }
    }

    // MARK: - Helpers

    func makeContext(screen: NSScreen) -> RenderContext {
        let geometry = NotchDetector.geometry(for: screen)
        return RenderContext(
            snapshotSize: renderer.snapshotSize,
            sinkPoint: geometry.sinkPoint,
            notchSize: geometry.notchSize,
            usesVirtualNotch: geometry.isVirtual,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            scale: Float(screen.backingScaleFactor)
        )
    }

    private func curveFor(_ transition: AnyTransition) -> TunerBezier {
        transition.bezierParam("progressCurve")
    }

    private func commitThresholdFor(_ transition: AnyTransition) -> Double {
        transition.doubleParam("commitThreshold", default: 1)
    }
}

import Tuner
