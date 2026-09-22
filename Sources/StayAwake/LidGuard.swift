import Foundation
import os

/// What stands between a force-killed Shut and a Mac that no longer sleeps when shut.
///
/// The kernel's lid bit outlives the process that set it. A quit, an update and a crash
/// followed by a relaunch all put it back (`HoldArbiter.shutDown`, `ArmedMarker`). The one
/// case left was Shut killed outright while holding and never opened again: lid sleep
/// stayed off until the next reboot.
///
/// So while a hold is armed, Shut keeps a second copy of its own executable running as a
/// guard. The guard does one thing: it sleeps in the kernel until Shut's process exits, then
/// restores lid sleep, removes the marker and exits. No root, no helper to install, no CPU
/// while it waits, and it exists only while a hold does. When a hold ends the ordinary way,
/// Shut restores the lid itself and tells the guard to go (SIGTERM, which it does not catch).
public enum LidGuard {
    /// `Shut --lid-guard <pid>`
    public static let argument = "--lid-guard"

    /// The guard process's whole life. Never returns.
    public static func run(arguments: [String]) -> Never {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count,
              let parent = pid_t(arguments[index + 1]), parent > 1 else { exit(64) }
        watch(parent) {
            let log = Logger(subsystem: "app.shut", category: "awake")
            let restored = LidHold().setLidSleepDisabled(false)
            ArmedMarker().remove()
            log.notice("lid guard: Shut (pid \(parent)) is gone while holding; lid sleep \(restored ? "restored" : "could NOT be restored", privacy: .public)")
        }
        exit(0)
    }

    /// Blocks until `pid` has exited, then runs `restore`. Apart so the tests can watch a
    /// process that is not Shut and restore nothing real.
    static func watch(_ pid: pid_t, restore: () -> Void) {
        waitForExit(of: pid)
        restore()
    }

    /// A kqueue process event: the thread sleeps in the kernel, nothing polls. A pid that is
    /// already gone returns at once (there is nothing to wait for, and everything to restore).
    static func waitForExit(of pid: pid_t) {
        let queue = kqueue()
        guard queue >= 0 else { return pollUntilGone(pid) }
        defer { close(queue) }
        var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                            fflags: UInt32(NOTE_EXIT), data: 0, udata: nil)
        if kevent(queue, &change, 1, nil, 0, nil) == -1 {
            if errno == ESRCH { return }          // exited before we could ask
            return pollUntilGone(pid)
        }
        var event = kevent()
        while kevent(queue, nil, 0, &event, 1, nil) == -1, errno == EINTR {}
    }

    /// Only if kqueue is refused, which it never has been: once a second, for a process
    /// that exists only while a hold does.
    private static func pollUntilGone(_ pid: pid_t) {
        while kill(pid, 0) == 0 || errno == EPERM { sleep(1) }
    }
}

/// The app's side: starts a guard when a hold is armed, dismisses it when the hold ends.
final class LidGuardKeeper {
    private let executable: URL
    private var process: Process?

    init(executable: URL) { self.executable = executable }

    func start(log: (String) -> Void) {
        guard process?.isRunning != true else { return }
        let guardProcess = Process()
        guardProcess.executableURL = executable
        guardProcess.arguments = [LidGuard.argument, String(getpid())]
        guardProcess.standardInput = FileHandle.nullDevice
        guardProcess.standardOutput = FileHandle.nullDevice
        guardProcess.standardError = FileHandle.nullDevice
        do { try guardProcess.run(); process = guardProcess } catch {
            // Without a guard the hold still works; only the force-kill case is uncovered.
            log("lid guard did not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    deinit { process?.terminate() }
}
