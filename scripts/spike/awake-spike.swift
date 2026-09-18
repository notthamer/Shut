// Throwaway spike for the Stay awake feature (deleted before release).
//
// Answers one question on a real MacBook: does the unprivileged IOPMrootDomain
// call (selector 12, kPMSetClamshellSleepState) keep the Mac awake with the lid
// shut, on battery, with no display attached, and does it survive the charger
// being plugged in?
//
//   swiftc -O scripts/spike/awake-spike.swift -o /tmp/awake-spike
//   /tmp/awake-spike status
//   /tmp/awake-spike hold [--minutes 20] [--no-reapply] [--no-assertion]
//   /tmp/awake-spike clear
//   /tmp/awake-spike watch
//
// Everything is logged to ~/shut-awake-spike.log and fsynced, so the log
// survives a sleep. A gap between heartbeats means the Mac slept.
import AppKit
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import notify

// MARK: - Logging

let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("shut-awake-spike.log")
let logHandle: FileHandle? = {
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
    }
    let h = try? FileHandle(forWritingTo: logURL)
    h?.seekToEndOfFile()
    return h
}()
let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func log(_ message: String) {
    let line = "\(stamp.string(from: Date())) \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    logHandle?.write(Data(line.utf8))
    try? logHandle?.synchronize()
}

// MARK: - Root domain

let kPMSetClamshellSleepState: UInt32 = 12      // IOKit/pwr_mgt/IOPMLibDefs.h
let kClamshellStateChange: UInt32 = 0xE003_4100 // iokit_family_msg(sub_iokit_powermanagement, 0x100)

func rootDomain() -> io_service_t {
    IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
}

func rootProperty(_ key: String) -> Any? {
    let service = rootDomain()
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

var connection: io_connect_t = 0

@discardableResult
func setClamshellSleepDisabled(_ disabled: Bool) -> Bool {
    if connection == 0 {
        let service = rootDomain()
        guard service != 0 else { log("ERROR no IOPMrootDomain"); return false }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { log("ERROR IOServiceOpen \(String(kr, radix: 16))"); return false }
    }
    var input: UInt64 = disabled ? 1 : 0
    let kr = IOConnectCallScalarMethod(connection, kPMSetClamshellSleepState, &input, 1, nil, nil)
    log("selector12(\(disabled ? 1 : 0)) -> \(kr == KERN_SUCCESS ? "ok" : "FAILED 0x" + String(kr, radix: 16))")
    return kr == KERN_SUCCESS
}

// MARK: - Power, thermal

func power() -> (onAC: Bool, percent: Int?) {
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
    for source in list {
        guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
        let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
            return (onAC, cur * 100 / max)
        }
        return (onAC, nil)
    }
    return (true, nil)
}

func thermalName() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
}

func snapshot() -> String {
    let p = power()
    let lid = rootProperty("AppleClamshellState") as? Bool
    let causes = rootProperty("AppleClamshellCausesSleep") as? Bool
    let sleepDisabled = rootProperty("SleepDisabled") as? Bool
    let displays = NSScreen.screens.count
    return "lidClosed=\(lid.map(String.init) ?? "?") clamshellCausesSleep=\(causes.map(String.init) ?? "?") SleepDisabled=\(sleepDisabled.map(String.init) ?? "?") ac=\(p.onAC) battery=\(p.percent.map(String.init) ?? "?")% thermal=\(thermalName()) screens=\(displays)"
}

// MARK: - Assertions by process, attributed to the owning app

func processInfo(_ pid: pid_t) -> (name: String, ppid: pid_t)? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let name = withUnsafePointer(to: &info.kp_proc.p_comm) {
        String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
    return (name, info.kp_eproc.e_ppid)
}

/// Walks up the parents until a regular app is found: caffeinate -> claude -> zsh -> Cursor.
func owner(of pid: pid_t) -> String {
    var chain: [String] = []
    var current = pid
    for _ in 0..<12 {
        guard current > 1, let info = processInfo(current) else { break }
        chain.append(info.name)
        if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
            return "\(app.localizedName ?? info.name) [\(chain.joined(separator: " <- "))]"
        }
        current = info.ppid
    }
    return "(no app) [\(chain.joined(separator: " <- "))]"
}

func assertionLines() -> [String] {
    var ref: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess, let dict = ref?.takeRetainedValue() as NSDictionary? else {
        return ["(could not read assertions)"]
    }
    var lines: [String] = []
    for (key, value) in dict {
        guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [[String: Any]] else { continue }
        for a in list {
            let type = a[kIOPMAssertionTypeKey] as? String ?? "?"
            let name = a[kIOPMAssertionNameKey] as? String ?? "?"
            lines.append("  pid \(pid) \(type) \"\(name)\" owner=\(owner(of: pid))")
        }
    }
    return lines.sorted()
}

// MARK: - Commands

func usage() -> Never {
    print("usage: awake-spike status | hold [--minutes N] [--no-reapply] [--no-assertion] | clear | watch")
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

func flagValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch command {
case "status":
    log("STATUS \(snapshot())")
    assertionLines().forEach { log($0) }
    exit(0)

case "clear":
    setClamshellSleepDisabled(false)
    log("CLEARED \(snapshot())")
    exit(0)

case "watch":
    // Which notify keys fire when another process takes or drops an assertion?
    var lastLines = assertionLines()
    log("WATCH start")
    lastLines.forEach { log($0) }
    // Finding 2026-09-18: the public key only fires when the system-wide aggregate
    // changes, and the private IOPMAssertionNotify opt-in is not something to build on.
    // The app reads assertions at the moments that matter instead (hinge starts closing,
    // popover open, slow timer while holding).
    var tokens: [Int32] = []
    for key in ["com.apple.system.powermanagement.assertions",
                "com.apple.system.powermanagement.assertions.anychange",
                "com.apple.system.powermanagement.assertions.timeout"] {
        var token: Int32 = 0
        let status = notify_register_dispatch(key, &token, DispatchQueue.main) { _ in
            let now = assertionLines()
            log("NOTIFY \(key) changed=\(now != lastLines)")
            if now != lastLines {
                Set(now).subtracting(lastLines).forEach { log("  +\($0)") }
                Set(lastLines).subtracting(now).forEach { log("  -\($0)") }
                lastLines = now
            }
        }
        log("registered \(key) status=\(status)")
        tokens.append(token)
    }
    RunLoop.main.run()

case "hold":
    let minutes = Double(flagValue("--minutes") ?? "20") ?? 20
    let reapply = !args.contains("--no-reapply")
    let takeAssertion = !args.contains("--no-assertion")
    let batteryFloor = 15

    log("HOLD start minutes=\(minutes) reapply=\(reapply) assertion=\(takeAssertion) \(snapshot())")
    guard setClamshellSleepDisabled(true) else { exit(1) }

    var assertionID: IOPMAssertionID = 0
    if takeAssertion {
        let kr = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "Shut awake spike" as CFString, &assertionID)
        log("assertion PreventUserIdleSystemSleep -> \(kr == kIOReturnSuccess ? "ok" : "FAILED")")
    }

    func finish(_ reason: String) -> Never {
        log("HOLD end reason=\(reason)")
        setClamshellSleepDisabled(false)
        if assertionID != 0 { IOPMAssertionRelease(assertionID) }
        log("final \(snapshot())")
        exit(0)
    }

    // Signals: always undo the bit.
    var signalSources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { finish("signal \(sig)") }
        source.resume()
        signalSources.append(source)
    }

    // Heartbeat: wall clock against uptime. Uptime stops during sleep, wall clock doesn't.
    let started = Date()
    var lastWall = Date()
    var lastUptime = ProcessInfo.processInfo.systemUptime
    var sleeps = 0
    let heartbeat = DispatchSource.makeTimerSource(queue: .main)
    heartbeat.schedule(deadline: .now() + 5, repeating: 5)
    heartbeat.setEventHandler {
        let wall = Date(), uptime = ProcessInfo.processInfo.systemUptime
        let lost = wall.timeIntervalSince(lastWall) - (uptime - lastUptime)
        if lost > 2 {
            sleeps += 1
            log("SLEPT for \(Int(lost)) s (sleep #\(sleeps))")
        }
        lastWall = wall; lastUptime = uptime
        log("beat \(snapshot()) sleeps=\(sleeps)")
        let p = power()
        if !p.onAC, let pct = p.percent, pct <= batteryFloor { finish("battery floor \(pct)%") }
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue { finish("thermal \(thermalName())") }
        if wall.timeIntervalSince(started) > minutes * 60 { finish("time up, sleeps=\(sleeps)") }
    }
    heartbeat.resume()

    // Power source changes: the charger race.
    let psSource = IOPSNotificationCreateRunLoopSource({ _ in
        log("EVENT power source changed \(snapshot())")
        if !CommandLine.arguments.contains("--no-reapply") { setClamshellSleepDisabled(true) }
    }, nil).takeRetainedValue()
    CFRunLoopAddSource(CFRunLoopGetMain(), psSource, .defaultMode)

    // Clamshell state changes from the root domain.
    let port = IONotificationPortCreate(kIOMainPortDefault)
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
    var notifier: io_object_t = 0
    let service = rootDomain()
    IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { _, _, type, argument in
        guard type == kClamshellStateChange else { return }
        let bits = UInt(bitPattern: argument)
        log("EVENT clamshell closed=\(bits & 1 != 0) willSleep=\(bits & 2 != 0)")
        if !CommandLine.arguments.contains("--no-reapply"), bits & 1 != 0 { setClamshellSleepDisabled(true) }
    }, nil, &notifier)

    // What the app would see.
    let workspace = NSWorkspace.shared.notificationCenter
    for (name, label) in [(NSWorkspace.willSleepNotification, "willSleep"),
                          (NSWorkspace.didWakeNotification, "didWake"),
                          (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
                          (NSWorkspace.screensDidWakeNotification, "screensDidWake"),
                          (NSWorkspace.sessionDidResignActiveNotification, "sessionDidResignActive"),
                          (NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive")] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
            log("EVENT NSWorkspace.\(label) \(snapshot())")
            if label == "didWake", reapply { setClamshellSleepDisabled(true) }
        }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
        log("EVENT screen parameters changed screens=\(NSScreen.screens.count)")
    }
    let distributed = DistributedNotificationCenter.default()
    for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
        distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in log("EVENT \(name)") }
    }

    log("armed. Close the lid now. Ctrl-C (or wait \(minutes) min) to end. Log: \(logURL.path)")
    RunLoop.main.run()

default:
    usage()
}
