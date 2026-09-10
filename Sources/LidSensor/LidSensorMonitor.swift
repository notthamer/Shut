import Combine
import Foundation

/// One reading from the sensor, after smoothing.
public struct LidSample: Sendable {
    public let timestamp: TimeInterval   // seconds since boot-independent reference (Date)
    public let rawAngle: Double
    public let angle: Double
    public let velocity: Double          // degrees per second, positive = opening
    public let pollRateHz: Double
}

/// Polls the lid sensor and publishes smoothed angle and velocity.
///
/// Polling is adaptive: 10 Hz while the lid is still (near-zero idle cost), and up
/// to 120 Hz as soon as the angle starts changing so the transition tracks the lid
/// without perceptible lag. Sampling happens on a private queue; published values
/// are always delivered on the main thread.
public final class LidSensorMonitor: ObservableObject {
    public static let idleRateHz: Double = 10
    public static let activeRateHz: Double = 120

    @Published public private(set) var angle: Double?
    @Published public private(set) var velocity: Double = 0
    @Published public private(set) var isAvailable = false
    @Published public private(set) var lastSampleDate: Date?
    @Published public private(set) var pollRateHz: Double = LidSensorMonitor.idleRateHz

    /// Called on the sampling queue for every sample. Cheap consumers (CSV logger,
    /// CLI display) use this rather than Combine.
    public var onSample: ((LidSample) -> Void)?

    public var smoothing: Smoothing {
        get { queue.sync { smoother.smoothing } }
        set { queue.sync { smoother.smoothing = newValue } }
    }

    private let queue = DispatchQueue(label: "com.sinkhole.lidsensor", qos: .userInteractive)
    private var device: LidAngleDevice?
    private var timer: DispatchSourceTimer?
    private var smoother: AngleSmoother
    private var currentRate: Double = LidSensorMonitor.idleRateHz
    private var lastMovement: TimeInterval = 0
    private var lastRawAngle: Double?

    /// How long the angle must be still before dropping back to the idle rate.
    private let settleTime: TimeInterval = 1.0
    /// Velocity below which we consider the lid still.
    private let stillThreshold: Double = 2.0

    public init(smoothing: Smoothing = .medium) {
        self.smoother = AngleSmoother(smoothing: smoothing)
    }

    deinit { stop() }

    /// Opens the sensor and starts polling. Returns `false` if there's no sensor.
    @discardableResult
    public func start() -> Bool {
        return queue.sync {
            if timer != nil { return device != nil }
            do {
                device = try LidAngleDevice.open()
            } catch {
                device = nil
            }
            let available = device != nil
            DispatchQueue.main.async { self.isAvailable = available }
            guard available else { return false }
            scheduleTimer(rateHz: LidSensorMonitor.idleRateHz)
            return true
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            device = nil
            smoother.reset()
        }
    }

    /// Reads a single sample synchronously (used by the CLI report mode).
    public func readOnce() -> Double? {
        return queue.sync { try? device?.readAngle() }
    }

    // MARK: - Sampling

    private func scheduleTimer(rateHz: Double) {
        timer?.cancel()
        currentRate = rateHz
        let source = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1.0 / rateHz
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
        DispatchQueue.main.async { self.pollRateHz = rateHz }
    }

    private func tick() {
        guard let device else { return }
        guard let raw = try? device.readAngle() else { return }
        let now = Date().timeIntervalSince1970
        let smoothed = smoother.add(rawAngle: raw, at: now)
        let velocity = smoother.velocity

        // Detect movement from the raw value too, so the very first degree of
        // motion bumps the poll rate before the smoothed velocity catches up.
        if let last = lastRawAngle, last != raw { lastMovement = now }
        if abs(velocity) > stillThreshold { lastMovement = now }
        lastRawAngle = raw

        let shouldBeActive = (now - lastMovement) < settleTime
        let wantedRate = shouldBeActive ? LidSensorMonitor.activeRateHz : LidSensorMonitor.idleRateHz
        if wantedRate != currentRate { scheduleTimer(rateHz: wantedRate) }

        let sample = LidSample(timestamp: now, rawAngle: raw, angle: smoothed,
                               velocity: velocity, pollRateHz: currentRate)
        onSample?(sample)
        DispatchQueue.main.async {
            self.angle = smoothed
            self.velocity = velocity
            self.lastSampleDate = Date(timeIntervalSince1970: now)
        }
    }
}
