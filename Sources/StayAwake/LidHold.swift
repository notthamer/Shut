import Foundation
import IOKit
import IOKit.pwr_mgt

/// What the arbiter needs from the system, so tests can stand in for the kernel.
public protocol LidHolding: AnyObject {
    /// Disables or restores lid-close sleep. Returns false when the system refused.
    @discardableResult func setLidSleepDisabled(_ disabled: Bool) -> Bool
    /// Holds or drops an idle-sleep assertion, so the Mac does not doze off by
    /// itself before, or after, the lid shuts.
    func setIdleSleepPrevented(_ prevented: Bool)
}

/// The real thing.
///
/// Power assertions (what `caffeinate` takes) stop idle sleep only; the lid is a
/// separate path inside `IOPMrootDomain`. Its user client has one call that turns
/// lid-close sleep off, `kPMSetClamshellSleepState`, and the kernel applies no
/// privilege or entitlement check to it, so this needs no root and no helper.
/// Measured on a MacBook Pro (Mac14,9, macOS 26.5): lid shut, on battery, no
/// display attached, awake throughout.
///
/// Three properties of that call shape everything around this class:
/// - The kernel keeps one bit for every userspace caller. `powerd` rewrites it on
///   power-source changes, so `HoldArbiter` re-applies it on those events.
/// - Clearing the bit with the lid shut makes the Mac sleep at once. "The work
///   finished" and "now go to sleep" are therefore the same call.
/// - The bit outlives the process (though never a reboot: it is not written to
///   disk). `ArmedMarker` exists so a crash cannot leave a Mac that never sleeps.
public final class LidHold: LidHolding {
    /// From `IOKit/pwr_mgt/IOPMLibDefs.h`; a macro, so not visible to Swift.
    private static let setClamshellSleepState: UInt32 = 12

    private var connection: io_connect_t = 0
    private var assertion: IOPMAssertionID = 0
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void = { _ in }) { self.log = log }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    @discardableResult
    public func setLidSleepDisabled(_ disabled: Bool) -> Bool {
        guard openIfNeeded() else { return false }
        var input: UInt64 = disabled ? 1 : 0
        let result = IOConnectCallScalarMethod(connection, Self.setClamshellSleepState, &input, 1, nil, nil)
        if result != KERN_SUCCESS {
            // A refused call must never be silent: the Mac would sleep mid-hold with no trace of why.
            log("lid sleep \(disabled ? "disable" : "restore") refused: 0x\(String(result, radix: 16))")
        }
        return result == KERN_SUCCESS
    }

    public func setIdleSleepPrevented(_ prevented: Bool) {
        if prevented, assertion == 0 {
            let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Shut is keeping the Mac awake" as CFString, &assertion)
            if result != kIOReturnSuccess {
                assertion = 0
                log("idle sleep assertion refused: 0x\(String(result, radix: 16))")
            }
        } else if !prevented, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }

    private func openIfNeeded() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { log("no IOPMrootDomain"); return false }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            connection = 0
            log("IOPMrootDomain open refused: 0x\(String(result, radix: 16))")
            return false
        }
        return true
    }
}

/// A file that exists exactly while Shut has lid-close sleep disabled. If the app
/// dies, the next launch finds it and restores the lid. Without it a crash would
/// leave the Mac awake in a bag until the next reboot.
public struct ArmedMarker {
    public let url: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shut", isDirectory: true)
        url = base.appendingPathComponent("awake-armed")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func write() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8).write(to: url, options: .atomic)
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }

    /// At launch: if the last run left the lid held, restore it. Only ever undoes
    /// what Shut did, because the kernel bit is shared with other keep-awake apps.
    @discardableResult
    public func recover(using hold: LidHolding) -> Bool {
        guard exists else { return false }
        hold.setLidSleepDisabled(false)
        remove()
        return true
    }
}
