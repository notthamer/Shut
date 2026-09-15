import Foundation
import IOKit
import IOKit.hid

/// Errors from talking to the lid angle sensor.
public enum LidSensorError: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case reportFailed(IOReturn)
    case badReport([UInt8])

    public var description: String {
        switch self {
        case .notFound:
            return "No lid angle sensor found on this Mac."
        case .openFailed(let code):
            return "Could not open the lid angle sensor (IOReturn \(code))."
        case .reportFailed(let code):
            return "Could not read from the lid angle sensor (IOReturn \(code))."
        case .badReport(let bytes):
            return "Unexpected sensor report: \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))"
        }
    }
}

/// How the sensor identifies itself on the HID bus.
///
/// Apple's lid angle sensor shows up as a HID device on the Sensor usage page
/// (0x20) with the "Orientation" usage (0x8A). The vendor and product IDs are the
/// same across every MacBook we know of that has the sensor.
public struct LidSensorIdentity {
    public static let vendorID = 0x05AC
    public static let productID = 0x8104
    public static let usagePage = 0x0020
    public static let usage = 0x008A
}

/// Raw access to the lid angle sensor over IOKit HID.
///
/// This class does one thing: read a feature report and decode it into degrees.
/// Smoothing, velocity, and polling live in `LidSensorMonitor` so this stays
/// trivially testable and obviously correct.
public final class LidAngleDevice {
    private let manager: IOHIDManager
    private let device: IOHIDDevice

    /// The feature report we read. Layout (unverified across all models, so the CLI
    /// exposes `--debug` to print the raw bytes):
    ///   byte 0     report ID (1)
    ///   bytes 1-2  angle in degrees, little-endian UInt16
    public static let reportID: CFIndex = 1
    public static let reportLength = 8

    /// Returns `nil` if no sensor is present. Throws only for unexpected failures.
    public static func open() throws -> LidAngleDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: LidSensorIdentity.vendorID,
            kIOHIDProductIDKey: LidSensorIdentity.productID,
            kIOHIDPrimaryUsagePageKey: LidSensorIdentity.usagePage,
            kIOHIDPrimaryUsageKey: LidSensorIdentity.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw LidSensorError.openFailed(openResult) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        let deviceOpen = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceOpen == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw LidSensorError.openFailed(deviceOpen)
        }
        return LidAngleDevice(manager: manager, device: device)
    }

    private init(manager: IOHIDManager, device: IOHIDDevice) {
        self.manager = manager
        self.device = device
    }

    deinit {
        stopDoorbell()
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Doorbell

    private var doorbellQueue: DispatchQueue?
    private var doorbellBuffer = [UInt8](repeating: 0, count: 8)
    private var onDoorbell: (() -> Void)?

    /// The sensor pushes an input report whenever the angle changes by a whole
    /// degree (plus a slow heartbeat). We don't read the angle from it, the
    /// feature report is the reliable source; it's only a bell that says "look
    /// now", which lets the poll thread park while the lid is still.
    public func startDoorbell(on queue: DispatchQueue, _ handler: @escaping () -> Void) {
        guard doorbellQueue == nil else { return }
        doorbellQueue = queue
        onDoorbell = handler
        IOHIDDeviceSetDispatchQueue(device, queue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        doorbellBuffer.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceRegisterInputReportCallback(device, buffer.baseAddress!, buffer.count, { context, _, _, _, _, _, _ in
                guard let context else { return }
                Unmanaged<LidAngleDevice>.fromOpaque(context).takeUnretainedValue().onDoorbell?()
            }, context)
        }
        IOHIDDeviceActivate(device)
    }

    private func stopDoorbell() {
        guard doorbellQueue != nil else { return }
        IOHIDDeviceCancel(device)
        onDoorbell = nil
        doorbellQueue = nil
    }

    /// Reads the raw feature report bytes. Useful for `--debug` and for verifying the
    /// layout on Macs we haven't seen.
    public func readRawReport() throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: Self.reportLength)
        var length = CFIndex(Self.reportLength)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, Self.reportID, pointer.baseAddress!, &length)
        }
        guard result == kIOReturnSuccess else { throw LidSensorError.reportFailed(result) }
        return Array(buffer.prefix(Int(length)))
    }

    /// Reads and decodes the current lid angle in degrees.
    public func readAngle() throws -> Double {
        let bytes = try readRawReport()
        guard let angle = Self.decodeAngle(bytes) else { throw LidSensorError.badReport(bytes) }
        return angle
    }

    /// Pure decoder, separated out so it can be unit-tested without hardware.
    /// Returns `nil` if the report is too short to contain an angle.
    public static func decodeAngle(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3 else { return nil }
        let raw = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        return Double(raw)
    }
}
