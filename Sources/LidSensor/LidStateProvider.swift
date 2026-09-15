import Foundation
import IOKit
import IOKit.pwr_mgt

/// Fallback for Macs without a lid angle sensor. Ported code
/// (MIT, © 2026 Anti Ltd).
///
/// `IOPMrootDomain` publishes `AppleClamshellState` and posts
/// `kIOPMMessageClamshellStateChange` as a general-interest notification on every
/// lid edge: open/closed transitions with no polling, which is the most the
/// platform exposes without the sensor.
public final class LidStateProvider {
    /// `kIOPMMessageClamshellStateChange` is a macro, unavailable to Swift. It
    /// expands to `iokit_family_msg(sub_iokit_powermanagement, 0x100)`.
    private static let clamshellStateChanged: UInt32 = {
        let systemIOKit: UInt32 = 0x38 << 26
        let subsystemPowerManagement: UInt32 = 13 << 14
        return systemIOKit | subsystemPowerManagement | 0x100
    }()

    private var notifyPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var rootDomain: io_service_t = 0
    private var handler: ((Bool) -> Void)?
    private let queue = DispatchQueue(label: "app.shut.lidstate", qos: .userInteractive)

    public init() {}

    public static func isAvailable() -> Bool { currentClamshellState() != nil }

    /// True when the lid is shut. nil on machines with no lid at all.
    public static func currentClamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return readClamshellState(from: service)
    }

    private static func readClamshellState(from service: io_service_t) -> Bool? {
        guard let property = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return (property as? NSNumber)?.boolValue
    }

    /// Starts delivering `lidIsOpen` on lid edges (and once immediately).
    public func start(_ handler: @escaping (Bool) -> Void) -> Bool {
        guard notifyPort == nil else { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0, Self.readClamshellState(from: service) != nil else {
            if service != 0 { IOObjectRelease(service) }
            return false
        }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { IOObjectRelease(service); return false }
        self.handler = handler
        rootDomain = service
        notifyPort = port
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { context, _, messageType, _ in
            guard let context else { return }
            let provider = Unmanaged<LidStateProvider>.fromOpaque(context).takeUnretainedValue()
            provider.handleInterestMessage(messageType)
        }, context, &notification)
        guard result == kIOReturnSuccess else { stop(); return false }
        IONotificationPortSetDispatchQueue(port, queue)
        emitCurrentState()
        return true
    }

    public func stop() {
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if let notifyPort { IONotificationPortDestroy(notifyPort); self.notifyPort = nil }
        if rootDomain != 0 { IOObjectRelease(rootDomain); rootDomain = 0 }
        handler = nil
    }

    deinit { stop() }

    private func handleInterestMessage(_ messageType: UInt32) {
        guard messageType == Self.clamshellStateChanged else { return }
        emitCurrentState()
    }

    private func emitCurrentState() {
        guard let handler, rootDomain != 0, let closed = Self.readClamshellState(from: rootDomain) else { return }
        handler(!closed)
    }
}
