import AppKit
import Foundation

/// TCC applies a new Screen Recording grant only to a fresh process.
enum Relaunch {
    static func now() {
        let bundleURL = Bundle.main.bundleURL
        if Bundle.main.bundleIdentifier != nil, bundleURL.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let exe = Bundle.main.executableURL {
            let process = Process()
            process.executableURL = exe
            try? process.run()
            NSApp.terminate(nil)
        }
    }
}
