import AppKit
import CoreGraphics

/// Something that can say "stay awake": one per kind of reason. Sources report on
/// the main thread and only when their answer changed.
@MainActor
public protocol HoldSource: AnyObject {
    var reasons: [HoldReason] { get }
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}

/// "I say so": for an hour, four, or until stopped.
@MainActor
public final class ManualHold: HoldSource {
    public private(set) var reasons: [HoldReason] = []
    public var onChange: (() -> Void)?

    public init() {}
    public func start() {}
    public func stop() { end() }

    /// `duration` nil holds until `end()`.
    public func begin(for duration: TimeInterval?, now: Date = Date()) {
        reasons = [HoldReason(id: "manual", kind: .manual, title: "You", since: now,
                              until: duration.map { now.addingTimeInterval($0) })]
        onChange?()
    }

    public func end() {
        guard !reasons.isEmpty else { return }
        reasons = []
        onChange?()
    }

    /// Drops a hold whose time is up. The arbiter calls this at the deadline.
    public func prune(now: Date = Date()) {
        if let until = reasons.first?.until, until <= now { end() }
    }
}

/// "A display is connected". macOS keeps a shut MacBook awake for an external
/// display only on a charger with a keyboard and mouse attached; this reason lifts
/// both conditions.
@MainActor
public final class DisplayConnected: HoldSource {
    public private(set) var reasons: [HoldReason] = []
    public var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if !reasons.isEmpty { reasons = []; onChange?() }
    }

    private func refresh() {
        let names = Self.externalDisplayNames()
        guard names != reasons.map(\.title) else { return }
        let existing = Dictionary(uniqueKeysWithValues: reasons.map { ($0.title, $0.since) })
        reasons = names.map { HoldReason(id: "display:\($0)", kind: .display, title: $0, since: existing[$0] ?? Date()) }
        onChange?()
    }

    static func externalDisplayNames() -> [String] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDisplayIsBuiltin(number.uint32Value) == 0 else { return nil }
            return screen.localizedName
        }
    }
}

/// "These apps are open": apps the user picked, by bundle identifier. Launches and
/// quits arrive as workspace notifications.
@MainActor
public final class AppsOpen: HoldSource {
    public private(set) var reasons: [HoldReason] = []
    public var onChange: (() -> Void)?
    public var bundleIDs: Set<String> { didSet { if bundleIDs != oldValue, !observers.isEmpty { refresh() } } }
    private var observers: [NSObjectProtocol] = []

    public init(bundleIDs: Set<String> = []) { self.bundleIDs = bundleIDs }

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    public func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        if !reasons.isEmpty { reasons = []; onChange?() }
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(bundleIDs.contains) ?? false
        }
        let existing = Dictionary(reasons.map { ($0.id, $0.since) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let next: [HoldReason] = running.compactMap { app in
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let key = "app:\(id)"
            return HoldReason(id: key, kind: .appOpen, title: app.localizedName ?? id,
                              since: existing[key] ?? app.launchDate ?? Date())
        }.sorted { $0.title < $1.title }
        guard next != reasons else { return }
        reasons = next
        onChange?()
    }
}
