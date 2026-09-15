import AppKit

/// The version of a running copy of Shut, for deciding which of two copies
/// should keep running. Marketing version first, build number as the tiebreak.
struct InstanceVersion: Equatable {
    let short: String
    let build: String

    static var current: InstanceVersion {
        InstanceVersion(info: Bundle.main.infoDictionary ?? [:])
    }

    init(of app: NSRunningApplication) {
        self.init(info: app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary } ?? [:])
    }

    init(info: [String: Any]) {
        short = info["CFBundleShortVersionString"] as? String ?? "0"
        build = info["CFBundleVersion"] as? String ?? "0"
    }

    init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    /// True under the debugger (Xcode's Run). `P_TRACED` on our own kinfo_proc.
    static var isBeingDebugged: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// Strictly newer. Equal versions are not newer, so a second launch of the
    /// same version defers to the copy already running.
    func isNewer(than other: InstanceVersion) -> Bool {
        switch Self.compare(short, other.short) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return Self.compare(build, other.build) == .orderedDescending
        }
    }

    /// Numeric, component by component: 0.10.0 is newer than 0.9.1.
    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
