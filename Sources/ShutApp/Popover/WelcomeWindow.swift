import AppKit
import LidSensor
import SwiftUI
import Tuner

/// First launch: one screen, one decision. Permissions are explained later, only
/// if a style actually needs them.
@MainActor
final class WelcomeWindow {
    private var window: NSWindow?
    var onVisibilityChanged: ((Bool) -> Void)?

    func show(capability: HingeCapability, onEnable: @escaping () -> Void) {
        let content = WelcomeView(capability: capability) { [weak self] in
            onEnable()
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: content)
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.setContentSize(NSSize(width: 420, height: 320))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChanged?(false) }
        }
        onVisibilityChanged?(true)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WelcomeView: View {
    let capability: HingeCapability
    let enable: () -> Void
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            LogoMark(size: 88)
            Text("Choose how your Mac closes.")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.textRoot)
            Text(capability.explanation)
                .font(.system(size: 12))
                .foregroundStyle(theme.textLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
            ActionRow("Enable", action: enable)
                .frame(width: 180)
                .padding(.bottom, 24)
        }
        .frame(width: 420, height: 320)
        .background(theme.panel)
        .tunerThemed()
    }
}
