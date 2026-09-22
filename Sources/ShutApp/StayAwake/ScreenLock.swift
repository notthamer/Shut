import Foundation

/// Locks the screen when the lid shuts on a held Mac. A Mac that never slept is
/// otherwise unlocked for whoever opens it next.
///
/// macOS has no public call for "lock now". `SACLockScreenImmediate` in the private
/// login framework is what the Apple menu's Lock Screen ends up using; it is looked
/// up at run time so a macOS that drops it costs us the feature, not a crash. It is
/// asynchronous and can fail without saying so, hence the read-back and the retries.
@MainActor
enum ScreenLock {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let function: LockFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    static var isAvailable: Bool { function != nil }

    /// Locks, checks, and tries again a few times. `completion` reports whether the
    /// session really is locked at the end.
    static func lock(attempt: Int = 1, completion: @escaping (Bool) -> Void = { _ in }) {
        if UnlockObserver.sessionIsLocked() { completion(true); return }
        guard let function else {
            Log.awake.error("lock when shut: SACLockScreenImmediate is not available on this macOS")
            completion(false)
            return
        }
        _ = function()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if UnlockObserver.sessionIsLocked() {
                completion(true)
            } else if attempt < 4 {
                lock(attempt: attempt + 1, completion: completion)
            } else {
                Log.awake.error("lock when shut: the session did not lock after \(attempt) attempts")
                completion(false)
            }
        }
    }
}
