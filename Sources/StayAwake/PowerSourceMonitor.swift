import Foundation
import IOKit.ps

/// Charger, battery, heat and Low Power Mode, delivered on change. Everything here
/// is a system notification; nothing polls.
@MainActor
public final class PowerSourceMonitor {
    public private(set) var conditions = PowerConditions()
    /// Called on the main thread whenever `conditions` changed. Also called on every
    /// power-source event even when nothing we track changed, because `powerd`
    /// rewrites the lid bit on those and the arbiter re-applies it.
    public var onChange: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        guard runLoopSource == nil else { return }
        conditions = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh(always: true) }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(always: false) }
            })
        }
    }

    public func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func refresh(always: Bool) {
        let now = Self.read()
        guard always || now != conditions else { return }
        conditions = now
        onChange?()
    }

    public static func read() -> PowerConditions {
        var result = PowerConditions(thermal: thermal(ProcessInfo.processInfo.thermalState),
                                     lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            result.onCharger = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                result.batteryPercent = current * 100 / max
            }
        }
        return result
    }

    private static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }
}
