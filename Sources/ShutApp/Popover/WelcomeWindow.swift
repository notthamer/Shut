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

    /// Seen once, so this is the one screen that spends the delight budget: a
    /// 40 ms stagger, each piece rising 6 pt as it fades in.
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            LogoMark(size: 88)
                .modifier(Entrance(appeared: appeared, delay: 0))
            Text("Choose how your Mac closes.")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(theme.textRoot)
                .modifier(Entrance(appeared: appeared, delay: 0.04))
            Text(capability.explanation)
                .font(.system(size: 12))
                .foregroundStyle(theme.textLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .modifier(Entrance(appeared: appeared, delay: 0.08))
            Spacer()
            PrimaryButton("Enable", action: enable)
                .frame(width: 180)
                .padding(.bottom, 24)
                .modifier(Entrance(appeared: appeared, delay: 0.12))
        }
        .frame(width: 420, height: 320)
        .background(theme.panel)
        .onAppear { appeared = true }
        .tunerThemed()
    }
}

/// Fade plus a small rise on the strong ease-out. Under Reduce Motion only the
/// fade remains (the modifier resolves to the short reduced fade).
private struct Entrance: ViewModifier {
    let appeared: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduce ? 0 : 6)
            .tunerAnimation(TunerTheme.easeOut(0.32).delay(delay), value: appeared)
    }
}
