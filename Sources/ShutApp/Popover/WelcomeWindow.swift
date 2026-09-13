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
        // The card is a pane of glass; the window behind it paints a soft
        // gradient so the glass has something to blur even over a plain desktop.
        let windowSize = NSSize(width: 480, height: 380)
        let margin: CGFloat = 24
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.appearance = TunerTheme.appearance
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        let backdrop = GradientBackdrop(frame: NSRect(origin: .zero, size: windowSize))
        let card = PanelChrome(frame: NSRect(x: margin, y: margin, width: windowSize.width - 2 * margin, height: windowSize.height - 2 * margin))
        card.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: content)
        card.install(hosting)
        backdrop.addSubview(card)
        w.contentView = backdrop
        w.center()
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
                .font(TunerTheme.font(22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.textRoot)
                .modifier(Entrance(appeared: appeared, delay: 0.04))
            Text(capability.explanation)
                .font(TunerTheme.font(12.5))
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
        .frame(width: 432, height: 332)
        .onAppear { appeared = true }
        .tunerThemed()
    }
}

/// Sky, lilac and white: the soft light the welcome glass floats in.
final class GradientBackdrop: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 1).cgColor,
            NSColor(red: 0.90, green: 0.86, blue: 0.98, alpha: 1).cgColor,
            NSColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        gradient.frame = bounds
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(gradient)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
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
