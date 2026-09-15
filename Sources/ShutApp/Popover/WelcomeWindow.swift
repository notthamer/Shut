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
        // The dark stage: Void Black, the wordmark in Paper White, one button.
        let windowSize = NSSize(width: 480, height: 380)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .darkAqua)   // the one dark surface: light traffic lights
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        let stage = VoidBackdrop(frame: NSRect(origin: .zero, size: windowSize))
        let hosting = NSHostingView(rootView: content)
        hosting.frame = stage.bounds
        hosting.autoresizingMask = [.width, .height]
        stage.addSubview(hosting)
        w.contentView = stage
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
        VStack(spacing: 20) {
            Spacer()
            MarkGlyph(size: 64)
                .modifier(Entrance(appeared: appeared, delay: 0))
            Text("Shut.")
                .font(TunerTheme.display(40)).tracking(-1.2)
                .foregroundStyle(TunerTheme.paperWhite)
                .modifier(Entrance(appeared: appeared, delay: 0.05))
            VStack(spacing: 8) {
                Text("Ways to close your Mac.")
                    .font(TunerTheme.font(15))
                    .foregroundStyle(TunerTheme.paperWhite.opacity(0.85))
                Text(capability.explanation)
                    .font(TunerTheme.bodySmall)
                    .foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 320)
            }
            .modifier(Entrance(appeared: appeared, delay: 0.1))
            Spacer()
            PrimaryButton("Enable", action: enable)
                .frame(width: 180)
                .padding(.bottom, 28)
                .modifier(Entrance(appeared: appeared, delay: 0.15))
        }
        .frame(width: 480, height: 380)
        .onAppear { appeared = true }
        .environment(\.colorScheme, .dark)
    }
}

/// Void Black: the stage the welcome opens on.
final class VoidBackdrop: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.008, green: 0.008, blue: 0.016, alpha: 1).cgColor
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

/// A staggered fade. Nothing moves.
private struct Entrance: ViewModifier {
    let appeared: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .tunerAnimation(TunerTheme.easeOut(0.3).delay(delay), value: appeared)
    }
}
