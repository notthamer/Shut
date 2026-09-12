import Combine
import Foundation

/// One reading, after filtering. Delivered on the sampling queue via `onSample`.
public struct LidSample: Sendable {
    public let timestamp: TimeInterval
    public let rawAngle: Double
    public let angle: Double
    /// Degrees per second, positive = opening (for humans and the CLI).
    public let degreesPerSecond: Double
    public let progress: Double
    public let pollRateHz: Double
}

/// Owns the hinge: probes what this Mac can report, polls the sensor adaptively,
/// runs the normalizer, and publishes `HingeState` on the main thread.
///
/// Capability tiers:
/// - `.continuousAngle`: the HID sensor; 10 Hz idle, 120 Hz while moving.
/// - `.lidStateOnly`: `IOPMrootDomain` clamshell edges; `onLidEvent` fires and the
///   app plays the effect on a timeline.
/// - `.unsupported`: no built-in lid; preview only.
public final class LidSensorMonitor: ObservableObject {
    public static let idleRateHz: Double = 10
    public static let activeRateHz: Double = 120

    @Published public private(set) var capability: HingeCapability = .unsupported
    @Published public private(set) var state: HingeState?
    /// Filtered angle in degrees (nil without a sensor).
    @Published public private(set) var angle: Double?
    /// Degrees per second, positive = opening. Kept for the menu readout and CLI.
    @Published public private(set) var degreesPerSecond: Double = 0
    @Published public private(set) var lastSampleDate: Date?
    @Published public private(set) var pollRateHz: Double = LidSensorMonitor.idleRateHz
    @Published public private(set) var calibration: HingeCalibration = .default

    /// True when a continuous sensor is online.
    public var isAvailable: Bool { capability == .continuousAngle }

    /// Every sample, on the sampling queue. Cheap consumers (CSV logger, CLI).
    public var onSample: ((LidSample) -> Void)?
    /// `.lidStateOnly` edges, on the main thread: true = opened, false = closed.
    public var onLidEvent: ((Bool) -> Void)?

    /// 0 = follow hard, 1 = steadiest. Default 0.25.
    public var smoothing: Double {
        get { queue.sync { normalizer.smoothing } }
        set { queue.sync { normalizer.smoothing = newValue } }
    }
    /// Degrees above closed the effect spans (Speed). Default 45.
    public var bandDegrees: Double {
        get { queue.sync { normalizer.bandDegrees } }
        set { queue.sync { normalizer.bandDegrees = newValue } }
    }
    /// The band the effect actually runs over after the resting angle has had its say.
    public var animationRange: ClosedRange<Double> { queue.sync { normalizer.animationRange } }

    private let queue = DispatchQueue(label: "app.shut.lidsensor", qos: .userInteractive)
    private let sampleClockLock = NSLock()
    private var lastSampleTimestamp: TimeInterval = 0

    /// Seconds since the sensor last produced a reading, read straight from the
    /// sampling thread. The published `lastSampleDate` goes through the main
    /// queue and can look stale whenever the main thread stalls; a watchdog must
    /// use this instead.
    public var timeSinceLastSample: TimeInterval {
        sampleClockLock.lock(); defer { sampleClockLock.unlock() }
        guard lastSampleTimestamp > 0 else { return .infinity }
        return Date().timeIntervalSince1970 - lastSampleTimestamp
    }

    private func stampSample(_ now: TimeInterval) {
        sampleClockLock.lock(); lastSampleTimestamp = now; sampleClockLock.unlock()
    }
    private var device: LidAngleDevice?
    private var lidState: LidStateProvider?
    private var timer: DispatchSourceTimer?
    private var normalizer: HingeNormalizer
    private var currentRate = LidSensorMonitor.idleRateHz
    private var lastMovement: TimeInterval = 0
    private var lastRawAngle: Double?
    private let settleTime: TimeInterval = 1.0
    private let defaults: UserDefaults?
    private let calibrationKey = "hingeCalibration"
    private var lastPersistedCalibration: HingeCalibration
    private var lastPersistCheck: TimeInterval = 0

    /// - Parameter defaults: where the learned calibration is stored (nil = not persisted).
    public init(smoothing: Double = 0.25, bandDegrees: Double = HingeCalibration.defaultBandDegrees,
                defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        var initial = HingeCalibration.default
        if let data = defaults?.data(forKey: calibrationKey),
           let saved = try? JSONDecoder().decode(HingeCalibration.self, from: data), saved.isUsable {
            initial = saved
        }
        normalizer = HingeNormalizer(calibration: initial, smoothing: smoothing)
        normalizer.bandDegrees = bandDegrees
        lastPersistedCalibration = initial
        calibration = initial
    }

    deinit { stop() }

    /// Probes in order of quality. Returns the capability found.
    @discardableResult
    public func start() -> HingeCapability {
        let found: HingeCapability = queue.sync {
            if timer != nil || lidState != nil { return capability }
            if let d = try? LidAngleDevice.open(), (try? d.readAngle()) != nil {
                device = d
                scheduleTimer(rateHz: Self.idleRateHz)
                return .continuousAngle
            }
            if LidStateProvider.isAvailable() {
                let provider = LidStateProvider()
                let started = provider.start { [weak self] isOpen in
                    guard let self else { return }
                    let now = Date().timeIntervalSince1970
                    self.stampSample(now)
                    let state = self.queue.sync { self.normalizer.normalize(HingeSample(angle: nil, lidIsOpen: isOpen, timestamp: now)) }
                    DispatchQueue.main.async {
                        self.state = state
                        self.lastSampleDate = Date()
                        self.onLidEvent?(isOpen)
                    }
                }
                if started { lidState = provider; return .lidStateOnly }
            }
            return .unsupported
        }
        DispatchQueue.main.async { self.capability = found }
        return found
    }

    public func stop() {
        queue.sync {
            timer?.cancel(); timer = nil
            device = nil
            lidState?.stop(); lidState = nil
            normalizer.reset()
        }
    }

    /// The SPU sensor endpoint dies across sleep; call on wake.
    public func reconnect() {
        stop()
        start()
    }

    /// Forgets the learned open/closed angles.
    public func relearn() {
        queue.sync {
            normalizer.calibration = .default
            lastPersistedCalibration = .default
        }
        defaults?.removeObject(forKey: calibrationKey)
        DispatchQueue.main.async { self.calibration = .default }
    }

    /// One synchronous raw reading, for the CLI's report.
    public func readOnce() -> Double? { queue.sync { try? device?.readAngle() } }

    // MARK: - Sampling

    private func scheduleTimer(rateHz: Double) {
        timer?.cancel()
        currentRate = rateHz
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1.0 / rateHz, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
        DispatchQueue.main.async { self.pollRateHz = rateHz }
    }

    private func tick() {
        guard let device, let raw = try? device.readAngle() else { return }
        let now = Date().timeIntervalSince1970
        stampSample(now)

        if let last = lastRawAngle, last != raw { lastMovement = now }
        lastRawAngle = raw
        guard let state = normalizer.normalize(HingeSample(angle: raw, lidIsOpen: raw > 1, timestamp: now)) else { return }
        let dps = -state.velocity * max(normalizer.animationRange.upperBound - normalizer.animationRange.lowerBound, 1)
        if abs(dps) > 2 { lastMovement = now }

        let wantedRate = (now - lastMovement) < settleTime ? Self.activeRateHz : Self.idleRateHz
        if wantedRate != currentRate { scheduleTimer(rateHz: wantedRate) }

        onSample?(LidSample(timestamp: now, rawAngle: raw, angle: state.angle ?? raw,
                            degreesPerSecond: dps, progress: state.progress, pollRateHz: currentRate))
        persistCalibrationIfDrifted(now: now)

        let calibrationNow = normalizer.calibration
        DispatchQueue.main.async {
            self.state = state
            self.angle = state.angle
            self.degreesPerSecond = dps
            self.lastSampleDate = Date(timeIntervalSince1970: now)
            if self.calibration != calibrationNow { self.calibration = calibrationNow }
        }
    }

    /// Writes the learned range at most every few seconds, and only once an end
    /// has moved by more than a degree.
    private func persistCalibrationIfDrifted(now: TimeInterval) {
        guard now - lastPersistCheck > 5 else { return }
        lastPersistCheck = now
        let current = normalizer.calibration
        guard abs(current.closedAngle - lastPersistedCalibration.closedAngle) > 1
                || abs(current.openAngle - lastPersistedCalibration.openAngle) > 1 else { return }
        lastPersistedCalibration = current
        if let data = try? JSONEncoder().encode(current) { defaults?.set(data, forKey: calibrationKey) }
    }
}
