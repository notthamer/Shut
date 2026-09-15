import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Screen Recording permission helpers. The only permission Shut needs.
public enum ScreenRecordingPermission {
    public static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (only works once per app identity; after that the
    /// user has to flip the switch in System Settings).
    @discardableResult
    public static func request() -> Bool { CGRequestScreenCaptureAccess() }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

/// Built-in display lookup shared by capture and overlay placement.
public enum BuiltInDisplay {
    /// The MacBook's own panel, or nil when it is not in the screen list: a
    /// desktop Mac, or a MacBook running shut in clamshell mode on an external
    /// display. Deliberately no fallback to `NSScreen.main`: the overlay and the
    /// capture belong to the lid's display and nothing else, and a black overlay
    /// on someone's external monitor is the one thing this app must never do.
    public static var screen: NSScreen? {
        NSScreen.screens.first { CGDisplayIsBuiltin(displayID(of: $0)) != 0 }
    }

    /// Screens other than the built-in one.
    public static var externalCount: Int {
        NSScreen.screens.filter { CGDisplayIsBuiltin(displayID(of: $0)) == 0 }.count
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// One-shot capture of the built-in display via ScreenCaptureKit.
///
/// The returned CGImage is handed straight to the renderer and never persisted.
public enum ScreenCapturer {
    public enum CaptureError: Error { case noBuiltInDisplay, noImage }

    /// Captures the built-in display, excluding every window that belongs to this
    /// process (overlay, preview, Tuner). Runs off the main thread.
    public static func captureBuiltInDisplay() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let builtInID = BuiltInDisplay.screen.map(BuiltInDisplay.displayID(of:))
        guard let display = content.displays.first(where: { $0.displayID == builtInID }) ?? content.displays.first else {
            throw CaptureError.noBuiltInDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let scale = BuiltInDisplay.screen?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? CaptureError.noImage) }
            }
        }
    }
}
