import AppKit
import Combine
import LidSensor
import TransitionKit
import Tuner

/// The lid state machine. Owns the overlay and decides, from the hinge and power
/// notifications, when to capture, show, animate and tear down. Main actor only.
///
/// Progress convention everywhere: 0 = open, 1 = shut.
@MainActor
public final class AppController: ObservableObject {
    public enum State: String {
        case idle        // lid open, nothing on screen
        case armed       // lid moving down; snapshot captured or in flight
        case closing     // overlay visible; progress follows the hinge (both ways) or a timeline
        case drained     // asleep or just woken: overlay is solid black, no snapshot
        case pouring     // unlocked: fresh snapshot springing from 1 back to 0
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var progress: Double = 0

    public let settings: AppSettings
    public let sensor: LidSensorMonitor
    public let registry: TransitionRegistry
    public let renderer: TransitionRenderer

    private var overlay: OverlayWindow?
    private var displayLink: DisplayLinkDriver?
    private var driver = ProgressDriver()
    private var cancellables = Set<AnyCancellable>()
    private var captureTask: Task<Void, Never>?
    private var lastCaptureDate: Date = .distantPast
    private var armedAt: Date = .distantPast
    private var shownAt: Date?
    private var hinge: HingeState?
    private var permissionCheckedAt: Date = .distantPast
    private var hasWarnedAboutPermission = false

    // Velocity for the styles' motion blur, from the rendered progress so it is
    // meaningful in spring and timed modes too. Smoothed over ~50 ms so the
    // sensor's degree steps don't flicker the blur.
    private var progressVelocity = 0.0
    private var lastFrameProgress = 0.0

    // Pour-out (PRD 5.7)
    private let unlock = UnlockObserver()
    private var screensAsleep = false
    private var blackSince: Date?
    private var safetyTimer: Timer?
    private var pourOutWorkItem: DispatchWorkItem?
    private var pourOutOvershoot = 0.06
    private let blackScreenLimit: TimeInterval = 1.5

    /// Progress at which the overlay appears; Bendable engages at 0.3 % closure.
    private let showAt = 0.012
    /// Progress below which a reopened lid tears the overlay down.
    private let hideBelow = 0.004
    /// Arm (and capture) as soon as the lid starts coming down.
    private let armAt = 0.003
    /// No sensor sample for this long during a close hides the overlay.
    private let watchdogInterval: TimeInterval = 0.5

    /// Set by the Tuner host so the panel can hide while a real transition plays.
    public var onTransitionVisibilityChanged: ((Bool) -> Void)?
    public var followLag: Double = 0.03

    public init(settings: AppSettings, sensor: LidSensorMonitor, registry: TransitionRegistry, renderer: TransitionRenderer) {
        self.settings = settings
        self.sensor = sensor
        self.registry = registry
        self.renderer = renderer

        sensor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, let state else { return }
                self.handle(state: state)
            }
            .store(in: &cancellables)

        sensor.onLidEvent = { [weak self] isOpen in self?.handleLidEvent(isOpen: isOpen) }

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

        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.safetyCheck() }
        }
    }

    // MARK: - Hinge (continuous sensor)

    private func handle(state hinge: HingeState) {
        self.hinge = hinge
        guard settings.isEnabled, sensor.capability == .continuousAngle else { return }
        refreshPermission()
        let p = hinge.progress

        switch state {
        case .idle:
            if p > armAt, hinge.direction != .opening { arm() }

        case .armed:
            if p <= hideBelow / 2 && hinge.direction != .closing {
                disarm()
            } else if p >= showAt {
                beginClose()
            } else if Date().timeIntervalSince(lastCaptureDate) > 1.0,
                      Date().timeIntervalSince(armedAt) < 6.0, hinge.direction == .still {
                // Resting just below open: keep the snapshot fresh for a few seconds.
                capture()
            }

        case .closing:
            // Follow mode already plays backwards when the lid comes up; once it is
            // back at the top, clear the overlay.
            if driver.mode == .follow, p <= hideBelow, driver.progress < 0.01 {
                teardown(reason: "lid reopened")
            }

        case .drained, .pouring:
            break
        }
    }

    // MARK: - Lid events (no sensor)

    private func handleLidEvent(isOpen: Bool) {
        guard settings.isEnabled, sensor.capability == .lidStateOnly else { return }
        if !isOpen {
            switch state {
            case .idle, .armed:
                arm()
                beginTimedClose()
            default: break
            }
        } else if state == .closing {
            teardown(reason: "lid opened")
        }
    }

    private func beginTimedClose() {
        state = .armed
        // The overlay appears as soon as the snapshot lands (see capture completion),
        // or immediately for styles that need none.
        if !registry.effectiveForLid.needsSnapshot { beginClose(timed: true) }
    }

    // MARK: - Permission (polled, never on the sensor path)

    private func refreshPermission() {
        guard Date().timeIntervalSince(permissionCheckedAt) > 2 else { return }
        permissionCheckedAt = Date()
        let granted = ScreenRecordingPermission.isGranted
        registry.captureAvailable = granted
        if !granted, registry.current.needsSnapshot, !hasWarnedAboutPermission {
            hasWarnedAboutPermission = true
            Log.capture.warning("Screen Recording not granted; \(self.registry.current.id, privacy: .public) plays as Fade until relaunch")
        }
    }

    // MARK: - Transitions between states

    private func arm() {
        state = .armed
        armedAt = Date()
        if registry.effectiveForLid.needsSnapshot { capture() }
    }

    private func disarm() {
        captureTask?.cancel()
        captureTask = nil
        renderer.clearSnapshot()
        state = .idle
    }

    private func capture() {
        guard captureTask == nil, ScreenRecordingPermission.isGranted else { return }
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
                if self.sensor.capability == .lidStateOnly {
                    self.beginClose(timed: true)
                } else if let p = self.hinge?.progress, p >= self.showAt {
                    self.beginClose()
                }
            } catch {
                Log.capture.error("capture failed: \(error.localizedDescription, privacy: .public)")
                self?.captureTask = nil
            }
        }
    }

    private func beginClose(timed: Bool = false) {
        let transition = registry.effectiveForLid
        guard !transition.needsSnapshot || renderer.snapshot != nil else { return }  // capture in flight
        guard let screen = BuiltInDisplay.screen else { return }

        let context = makeContext(screen: screen)
        driver.reset()
        driver.curve = transition.bezierParam("progressCurve")
        driver.commitThreshold = transition.doubleParam("commitThreshold", default: 1)
        driver.followLag = followLag
        if timed {
            driver.timed(to: 1, duration: settings.timedCloseDuration)
        } else if let p = hinge?.progress {
            driver.set(progress: driver.curve.value(at: p))
        }
        progressVelocity = 0
        lastFrameProgress = driver.progress

        if overlay == nil {
            overlay = OverlayWindow(screen: screen, renderer: renderer, transition: transition, context: context)
        }
        overlay?.setTransparent(transition.isTransparent)
        overlay?.metalView.transition = transition
        overlay?.metalView.context = context
        overlay?.metalView.progress = driver.progress
        overlay?.metalView.render()
        overlay?.show(on: screen)
        shownAt = Date()
        state = .closing
        onTransitionVisibilityChanged?(true)
        if registry.isSubstituting {
            Log.overlay.info("overlay shown (\(transition.id, privacy: .public), substituting for \(self.registry.current.id, privacy: .public))")
        } else {
            Log.overlay.info("overlay shown (\(transition.id, privacy: .public))")
        }

        if displayLink == nil { displayLink = DisplayLinkDriver(screen: screen) }
        displayLink?.onFrame = { [weak self] dt in self?.frame(dt: dt) }
        displayLink?.start()
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
        if state != .idle { Log.overlay.info("teardown: \(reason, privacy: .public)") }
        if shownAt != nil { onTransitionVisibilityChanged?(false) }
        shownAt = nil
        progress = 0
        state = .idle
    }

    // MARK: - Per frame

    private func frame(dt: Double) {
        guard let overlay else { return }

        if state == .closing, sensor.capability == .continuousAngle {
            let gap = sensor.timeSinceLastSample
            if gap > watchdogInterval, gap.isFinite {
                Log.lid.error("sensor watchdog: no sample for \(Int(gap * 1000)) ms; hiding overlay")
                teardown(reason: "sensor watchdog")
                return
            }
        }

        var p = driver.step(dt: dt, hinge: hinge?.progress)
        if state == .pouring { p = max(p, -pourOutOvershoot) }

        let raw = (p - lastFrameProgress) / max(dt, 0.001)
        progressVelocity += (raw - progressVelocity) * min(1, dt / 0.05)
        lastFrameProgress = p

        progress = p
        overlay.metalView.progress = p
        overlay.metalView.context.time = Float(Date().timeIntervalSince(shownAt ?? Date()))
        overlay.metalView.context.velocity = Float(progressVelocity)
        overlay.metalView.render()

        if state == .pouring, driver.isSettled {
            teardown(reason: "pour-out complete")
        } else if state == .closing, driver.mode == .timed, driver.isSettled, sensor.capability == .lidStateOnly {
            // Fully shut on a timeline; hold black until sleep or reopen.
            displayLink?.stop()
        }
    }

    // MARK: - Power and pour-out (PRD 5.7)

    @objc private func willSleep(_ note: Notification) {
        Log.app.info("sleep: \(note.name.rawValue, privacy: .public)")
        enterDrained()
    }

    @objc private func screensSlept(_ note: Notification) {
        Log.app.info("screens slept at lid angle \(self.hinge?.angle.map { String(format: "%.0f", $0) } ?? "?", privacy: .public)°")
        screensAsleep = true
        enterDrained()
    }

    @objc private func didWake(_ note: Notification) {
        Log.app.info("wake: \(note.name.rawValue, privacy: .public)")
        // The sensor's SPU endpoint doesn't survive sleep.
        sensor.reconnect()
        wakeUp()
    }

    @objc private func screensWoke(_ note: Notification) {
        Log.app.info("screens woke")
        screensAsleep = false
        wakeUp()
    }

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
        overlay?.setTransparent(false)
        overlay?.metalView.isBlackedOut = true
        overlay?.metalView.render()
        overlay?.show(on: screen)
        if shownAt == nil { onTransitionVisibilityChanged?(true) }
        shownAt = Date()
        blackSince = nil
        state = .drained
        Log.overlay.info("drained: black overlay in place")
    }

    private func wakeUp() {
        guard state == .drained else { return }
        unlock.refresh()
        overlay?.metalView.render()
        if unlock.isLocked {
            Log.unlock.info("awake and locked; waiting for unlock")
        } else {
            Log.unlock.info("awake and unlocked; pouring out now")
            sessionUnlocked()
        }
    }

    private func sessionUnlocked() {
        guard state == .drained, !screensAsleep else { return }
        guard settings.animateOpening else { teardown(reason: "opening animation off"); return }
        let delay = registry.effectiveForLid.doubleParam("pourOutDelayMs", default: 0) / 1000
        pourOutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginPourOut() }
        pourOutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Fresh snapshot (the overlay is excluded, so it sees the desktop underneath),
    /// then spring from 1 back to 0. Mask styles need no snapshot and start at once.
    private func beginPourOut() {
        guard state == .drained, let overlay, let screen = BuiltInDisplay.screen else { return }
        let transition = registry.effectiveForLid
        if !transition.needsSnapshot {
            startPourOut(transition: transition, overlay: overlay, screen: screen)
            return
        }
        guard ScreenRecordingPermission.isGranted else {
            teardown(reason: "pour-out without screen recording permission")
            return
        }
        blackSince = Date()
        captureTask = Task { [weak self] in
            do {
                let image = try await ScreenCapturer.captureBuiltInDisplay()
                guard let self, !Task.isCancelled, self.state == .drained else { return }
                try self.renderer.setSnapshot(image)
                self.captureTask = nil
                self.startPourOut(transition: transition, overlay: overlay, screen: screen)
            } catch {
                Log.capture.error("pour-out capture failed: \(error.localizedDescription, privacy: .public); hiding")
                self?.teardown(reason: "pour-out capture failed")
            }
        }
    }

    private func startPourOut(transition: AnyTransition, overlay: OverlayWindow, screen: NSScreen) {
        overlay.metalView.transition = transition
        overlay.metalView.context = makeContext(screen: screen)
        overlay.setTransparent(transition.isTransparent)
        overlay.metalView.isBlackedOut = false
        pourOutOvershoot = transition.doubleParam("overshoot", default: 0.06)
        driver.reset()
        driver.set(progress: 1)
        driver.animate(to: 0,
                       response: transition.doubleParam("pourOutResponse", default: 0.55),
                       damping: transition.doubleParam("pourOutDamping", default: 0.72))
        progressVelocity = 0
        lastFrameProgress = 1
        state = .pouring
        blackSince = nil
        shownAt = Date()
        Log.overlay.info("pour-out started (\(transition.id, privacy: .public))")

        if displayLink == nil { displayLink = DisplayLinkDriver(screen: screen) }
        displayLink?.onFrame = { [weak self] dt in self?.frame(dt: dt) }
        displayLink?.start()
    }

    /// PRD 5.7 safety rule, evaluated 4× a second regardless of state.
    private func safetyCheck() {
        guard let overlay, overlay.isVisible, overlay.metalView.isBlackedOut else { blackSince = nil; return }
        guard !screensAsleep, !unlock.isLocked else { blackSince = nil; return }
        if blackSince == nil { blackSince = Date(); return }
        if Date().timeIntervalSince(blackSince!) > blackScreenLimit {
            Log.overlay.error("SAFETY: black overlay visible \(self.blackScreenLimit)s while awake+unlocked in state \(self.state.rawValue, privacy: .public); force hiding")
            teardown(reason: "black screen safety")
        }
    }

    // MARK: - Demo playback (popover "Play")

    /// Plays the current style full screen: close over `duration`, then open.
    public func playDemo(duration: Double = 1.2) {
        guard state == .idle || state == .armed, settings.isEnabled else { return }
        let transition = registry.effectiveForLid
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            self.beginClose(timed: true)
            self.driver.timed(to: 1, duration: duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) { [weak self] in
                guard let self, self.state == .closing else { return }
                self.driver.timed(to: 0, duration: duration)
                self.displayLink?.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
                    guard let self, self.state == .closing else { return }
                    self.teardown(reason: "demo complete")
                }
            }
        }
        if transition.needsSnapshot {
            state = .armed
            guard ScreenRecordingPermission.isGranted else { state = .idle; return }
            captureTask = Task { [weak self] in
                do {
                    let image = try await ScreenCapturer.captureBuiltInDisplay()
                    guard let self, self.state == .armed else { return }
                    try self.renderer.setSnapshot(image)
                    self.captureTask = nil
                    run()
                } catch { self?.teardown(reason: "demo capture failed") }
            }
        } else {
            state = .armed
            run()
        }
    }

    // MARK: - Helpers

    func makeContext(screen: NSScreen) -> RenderContext {
        let geometry = NotchDetector.geometry(for: screen)
        let range = sensor.animationRange
        return RenderContext(
            snapshotSize: renderer.snapshotSize,
            sinkPoint: geometry.sinkPoint,
            notchSize: geometry.notchSize,
            usesVirtualNotch: geometry.isVirtual,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            scale: Float(screen.backingScaleFactor),
            velocity: Float(progressVelocity),
            hingeTravelDegrees: Float(max(range.upperBound - range.lowerBound, 10))
        )
    }
}
