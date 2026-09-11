import AppKit
import SwiftUI
import TransitionKit

/// Onboarding for the one permission Shut needs. Shown at launch until
/// Screen Recording is granted, and from the menu bar at any time.
///
/// macOS only shows its own prompt once per app identity, and it only honours a
/// new grant after the app relaunches, so this window polls the permission and
/// offers a one-click relaunch instead of leaving the user to guess.
@MainActor
final class PermissionWindowController {
    private var window: NSWindow?
    private let model = PermissionModel()

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView(model: model))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Shut"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 460, height: 360))
            w.center()
            window = w
        }
        model.startPolling()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        model.stopPolling()
        window?.close()
    }
}

@MainActor
final class PermissionModel: ObservableObject {
    @Published var granted = ScreenRecordingPermission.isGranted
    @Published var askedSystem = false
    private var timer: Timer?

    var launchedFromXcode: Bool {
        ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    }

    func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.granted = ScreenRecordingPermission.isGranted }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Triggers the system prompt (registers the app in the Screen Recording list)
    /// and opens the pane, since the prompt itself appears only once per identity.
    func requestAndOpenSettings() {
        askedSystem = true
        ScreenRecordingPermission.request()
        ScreenRecordingPermission.openSystemSettings()
    }

    /// TCC applies a new Screen Recording grant only to a fresh process.
    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        if Bundle.main.bundleIdentifier != nil, bundleURL.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let exe = Bundle.main.executableURL {
            // Bare SwiftPM binary (swift run): spawn a copy and quit.
            let process = Process()
            process.executableURL = exe
            try? process.run()
            NSApp.terminate(nil)
        }
    }
}

struct PermissionView: View {
    @ObservedObject var model: PermissionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.granted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                    .font(.system(size: 34))
                    .foregroundStyle(model.granted ? .green : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.granted ? "Screen Recording is granted" : "Shut needs Screen Recording")
                        .font(.title2.bold())
                    Text(model.granted ? "Relaunch so macOS applies it to this process."
                                       : "To freeze your desktop as the lid closes, Shut takes one snapshot of the screen. It stays in GPU memory and is never saved.")
                        .foregroundStyle(.secondary)
                }
            }

            if !model.granted {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Click **Open System Settings** below.")
                    step(2, "Turn on **Shut** under Screen & System Audio Recording. If you see several Shut entries, enable the newest one.")
                    step(3, "Come back here and click **Relaunch** when it turns green.")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

                if model.launchedFromXcode {
                    Label("Launched from Xcode. With “Sign to Run Locally” the app's identity changes on every build, so macOS forgets the grant each time. Choose your Personal Team under Signing & Capabilities to keep it.", systemImage: "hammer")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Spacer()
                if model.granted {
                    Button("Relaunch Shut") { model.relaunch() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") { model.requestAndOpenSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            Text(try! AttributedString(markdown: text))
        }
    }
}
