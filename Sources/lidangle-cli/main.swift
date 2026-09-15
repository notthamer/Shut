import Darwin
import Foundation
import LidSensor

// lidangle-cli: probe the MacBook lid angle sensor.
//
//   lidangle-cli                 live angle on one updating line
//   lidangle-cli --report        compatibility report formatted for a GitHub issue
//   lidangle-cli --log FILE.csv  append timestamp,angle per sample
//   lidangle-cli --debug         print raw feature report bytes with every sample
//
// No third-party argument parser: the surface is tiny and readability wins.

enum Mode {
    case live, report, log(String), debug, calibration
}

func parseArguments(_ args: [String]) -> Mode? {
    var iterator = args.dropFirst().makeIterator()
    var mode = Mode.live
    while let arg = iterator.next() {
        switch arg {
        case "--report": mode = .report
        case "--debug": mode = .debug
        case "--calibration": mode = .calibration
        case "--log":
            guard let path = iterator.next() else {
                print("--log needs a file path, e.g. --log angles.csv")
                return nil
            }
            mode = .log(path)
        case "-h", "--help":
            return nil
        default:
            print("Unknown option: \(arg)")
            return nil
        }
    }
    return mode
}

func printUsage() {
    print("""
    lidangle-cli — read the MacBook lid angle sensor

      lidangle-cli                 live angle on one updating line
      lidangle-cli --report        compatibility report for a GitHub issue
      lidangle-cli --log FILE.csv  append timestamp,angle per sample
      lidangle-cli --debug         show raw report bytes with every sample
      lidangle-cli --calibration   sample 5 s and print the learned closed/open angles
    """)
}

func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(cString: buffer)
}

func noSensorMessage() {
    print("""
    No lid angle sensor found on this Mac.

    The sensor is present on most Apple silicon MacBooks. If you believe your
    machine has one, run `lidangle-cli --report` and open an issue with the output.
    """)
}

func formatLine(_ sample: LidSample) -> String {
    String(format: "angle %6.1f°   velocity %7.1f°/s   progress %.2f   rate %3.0f Hz",
           sample.angle, sample.degreesPerSecond, sample.progress, sample.pollRateHz)
}

// MARK: - Modes

func runLive(debug: Bool) {
    let monitor = LidSensorMonitor()
    var device: LidAngleDevice?
    if debug { device = try? LidAngleDevice.open() }

    monitor.onSample = { sample in
        if debug, let device, let bytes = try? device.readRawReport() {
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("\(formatLine(sample))   raw [\(hex)]")
        } else {
            print("\r\(formatLine(sample))   ", terminator: "")
            fflush(stdout)
        }
    }
    guard monitor.start() == .continuousAngle else { noSensorMessage(); return }
    print("Reading lid angle. Press Ctrl-C to stop.")
    RunLoop.main.run()
}

func runCalibration() {
    let monitor = LidSensorMonitor(defaults: nil)
    guard monitor.start() == .continuousAngle else { noSensorMessage(); return }
    print("Sampling for 5 seconds...")
    RunLoop.main.run(until: Date().addingTimeInterval(5))
    let c = monitor.calibration
    let band = monitor.animationRange
    print(String(format: "closed %.1f°   open (resting) %.1f°   effect band %.1f°…%.1f°", c.closedAngle, c.openAngle, band.lowerBound, band.upperBound))
    print("The app learns these as you use it; the CLI starts from defaults each run.")
    monitor.stop()
}

func runReport() {
    let model = sysctlString("hw.model")
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let monitor = LidSensorMonitor(defaults: nil)
    let capability = monitor.start()
    let found = capability == .continuousAngle

    var samples: [LidSample] = []
    let lock = NSLock()
    monitor.onSample = { sample in
        lock.lock(); samples.append(sample); lock.unlock()
    }

    if found {
        print("Sampling for 5 seconds. Move the lid a little if you can...")
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        monitor.stop()
    }

    let angles = samples.map(\.rawAngle)
    let minAngle = angles.min().map { String(format: "%.0f°", $0) } ?? "-"
    let maxAngle = angles.max().map { String(format: "%.0f°", $0) } ?? "-"
    let rawBytes: String = {
        guard found, let device = try? LidAngleDevice.open(), let bytes = try? device.readRawReport() else { return "n/a" }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }()

    print("""

    ### Lid angle sensor report

    | | |
    |---|---|
    | Model | `\(model)` |
    | macOS | \(os) |
    | Sensor found | \(found ? "yes" : "no") |
    | Capability | \(capability.rawValue) |
    | Lid state (IOPMrootDomain) | \(LidStateProvider.currentClamshellState().map { $0 ? "closed" : "open" } ?? "unavailable") |
    | Samples in 5 s | \(samples.count) |
    | Angle range | \(minAngle) to \(maxAngle) |
    | Raw report | `\(rawBytes)` |

    <details><summary>First samples</summary>

    ```
    \(samples.prefix(30).map { String(format: "%.3f,%.1f", $0.timestamp, $0.rawAngle) }.joined(separator: "\n"))
    ```
    </details>
    """)
}

func runLog(path: String) {
    let url = URL(fileURLWithPath: path)
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: "timestamp,angle\n".data(using: .utf8))
    }
    guard let handle = try? FileHandle(forWritingTo: url) else {
        print("Could not open \(path) for writing."); return
    }
    handle.seekToEndOfFile()

    let monitor = LidSensorMonitor()
    monitor.onSample = { sample in
        let line = String(format: "%.3f,%.1f\n", sample.timestamp, sample.rawAngle)
        handle.write(line.data(using: .utf8)!)
        try? handle.synchronize()  // flush immediately so a lid-close sleep can't lose the tail
        print("\r\(formatLine(sample))   ", terminator: "")
        fflush(stdout)
    }
    guard monitor.start() == .continuousAngle else { noSensorMessage(); return }
    print("Logging to \(path). Close the lid slowly until the screen turns off, then Ctrl-C.")
    RunLoop.main.run()
}

// MARK: - Entry

guard let mode = parseArguments(CommandLine.arguments) else {
    printUsage()
    exit(0)
}

signal(SIGINT) { _ in
    print("")
    exit(0)
}

switch mode {
case .live: runLive(debug: false)
case .debug: runLive(debug: true)
case .report: runReport()
case .log(let path): runLog(path: path)
case .calibration: runCalibration()
}
