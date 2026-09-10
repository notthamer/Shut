import CoreGraphics
import Foundation

/// Tracks whether the login session is locked.
///
/// Relies on two undocumented distributed notifications, `com.apple.screenIsLocked`
/// and `com.apple.screenIsUnlocked`, which have been stable since 10.x but are not
/// API. Every event is logged so a failure on a new macOS is easy to spot, and
/// `sessionIsLocked()` provides a second opinion from CGSession at wake time.
@MainActor
final class UnlockObserver {
    private(set) var isLocked: Bool
    var onUnlock: (() -> Void)?
    var onLock: (() -> Void)?

    static let lockedName = Notification.Name("com.apple.screenIsLocked")
    static let unlockedName = Notification.Name("com.apple.screenIsUnlocked")

    init() {
        isLocked = Self.sessionIsLocked()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(locked), name: Self.lockedName, object: nil)
        center.addObserver(self, selector: #selector(unlocked), name: Self.unlockedName, object: nil)
        Log.unlock.info("unlock observer online; locked = \(self.isLocked)")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Polls CGSession. `CGSSessionScreenIsLocked` is present only while locked.
    static func sessionIsLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// Re-reads CGSession, for use right after wake when a notification may have
    /// been missed while asleep.
    func refresh() {
        isLocked = Self.sessionIsLocked()
        Log.unlock.info("refresh: locked = \(self.isLocked)")
    }

    @objc private func locked() {
        Log.unlock.info("screenIsLocked")
        isLocked = true
        onLock?()
    }

    @objc private func unlocked() {
        Log.unlock.info("screenIsUnlocked")
        isLocked = false
        onUnlock?()
    }
}
