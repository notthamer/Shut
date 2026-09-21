import AppKit
import LidSensor
import SwiftUI
import Tuner

/// First launch: a short walk on the dark stage. What Shut is, a style to pick (and watch),
/// Stay awake to turn on or leave, and where the app lives. Each step is one idea, and the
/// two that matter are things to do, not things to read. Permissions are explained later,
/// only if a style actually needs them.
@MainActor
final class WelcomeWindow {
    private var window: NSWindow?
    var onVisibilityChanged: ((Bool) -> Void)?

    func show(capability: HingeCapability, model: PopoverModel, onEnable: @escaping () -> Void) {
        let content = WelcomeView(capability: capability, model: model) { [weak self] in
            onEnable()
            self?.window?.close()
        }
        model.preview.capture()   // the drawn desktop until Screen Recording is granted; never asks
        let windowSize = WelcomeView.size
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

/// The steps of the first run. A Mac without a lid has no Stay awake, so no step for it.
enum WelcomeStep: Int, CaseIterable {
    case hello, style, awake, done

    static func steps(hasLid: Bool) -> [WelcomeStep] { hasLid ? allCases : [.hello, .style, .done] }

    /// The words of the last step: what was chosen, said back.
    static func summary(style: String, hasLid: Bool, awakeOn: Bool) -> [String] {
        var lines = ["Your Mac closes with \(style)."]
        if hasLid { lines.append(awakeOn ? "It stays awake while something is working." : "Stay awake is off. It is one click away.") }
        return lines
    }
}

struct WelcomeView: View {
    let capability: HingeCapability
    @ObservedObject var model: PopoverModel
    let enable: () -> Void
    @State var step: WelcomeStep = .hello
    /// Seen once, so this is the one screen that spends the delight budget: a staggered fade.
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = NSSize(width: 660, height: 520)
    private var steps: [WelcomeStep] { WelcomeStep.steps(hasLid: model.stayAwake.hasLid) }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var isLast: Bool { index == steps.count - 1 }
    private var awakeOn: Bool { model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented }

    init(capability: HingeCapability, model: PopoverModel, step: WelcomeStep = .hello, enable: @escaping () -> Void) {
        self.capability = capability; self.model = model; self.enable = enable
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case .hello: hello
                case .style: style
                case .awake: awake
                case .done: done
                }
            }
            .id(step).transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { appeared = true }
        .environment(\.colorScheme, .dark)
        .tunerAnimation(TunerTheme.ease, value: step)
    }

    private func go(_ delta: Int) {
        let next = index + delta
        guard steps.indices.contains(next) else { if delta > 0 { enable() }; return }
        step = steps[next]
        // Show, don't tell: the chosen style plays as its step arrives.
        if step == .style, !reduceMotion { model.preview.playRound() }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: 20) {
            MarkGlyph(size: 64).modifier(Entrance(appeared: appeared, delay: 0))
            Text("Shut.")
                .font(TunerTheme.display(40)).tracking(-1.2).foregroundStyle(TunerTheme.paperWhite)
                .modifier(Entrance(appeared: appeared, delay: 0.05))
            VStack(spacing: 8) {
                Text("Ways to close your Mac.")
                    .font(TunerTheme.font(15)).foregroundStyle(TunerTheme.paperWhite.opacity(0.85))
                Text(capability.explanation)
                    .font(TunerTheme.bodySmall).foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
                    .multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 320)
            }
            .modifier(Entrance(appeared: appeared, delay: 0.1))
        }
    }

    private var style: some View {
        // The words and the screen they are about side by side; under them every style at a
        // width where its name fits.
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom, spacing: 24) {
                heading(number: "01", eyebrow: "How it closes", title: "Pick how your\nMac closes.",
                        detail: "Click one to watch it.\nYou can change it any time.")
                Spacer(minLength: 0)
                PreviewWindow(preview: model.preview, compact: false).frame(width: 240)
            }
            StyleGallery(model: model)
        }
        .padding(.horizontal, 36)
    }

    private var awake: some View {
        VStack(alignment: .leading, spacing: 18) {
            AwakeEyes(mood: awakeOn ? .awake : .asleep, pixel: 4, tint: awakeOn ? TunerTheme.limeWash : .white.opacity(0.7), dreams: true)
                .tunerAnimation(TunerTheme.ease, value: awakeOn)
            heading(number: "02", eyebrow: "Stay awake", title: "Keep working with the lid shut.",
                    detail: "Your Mac stays awake only while something is working, a display is connected, or you say so. It goes to sleep by itself when that ends, when the battery gets low, or if it gets hot.")
            Text("Do not put a working Mac in a bag.")
                .font(TunerTheme.font(14, weight: .medium)).foregroundStyle(TunerTheme.saffron)
            HStack(spacing: 14) {
                if awakeOn {
                    PrimaryButton("It is on", tone: .lime, onDark: false) { model.stayAwake.settings.isOn = false } icon: {
                        AwakeEyes(mood: .awake, pixel: 1, tint: .black, animated: false)
                    }
                    Text("Click again to leave it off.").font(TunerTheme.bodySmall).foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
                } else {
                    PrimaryButton("Turn it on", onDark: true) {
                        if model.stayAwake.needsConsent { model.stayAwake.consent() } else { model.stayAwake.settings.isOn = true }
                    }
                    Text("Or leave it off. It is on its own page when you want it.")
                        .font(TunerTheme.bodySmall).foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private var done: some View {
        VStack(spacing: 18) {
            MarkGlyph(size: 40)
            Text("You are set.").font(TunerTheme.display(34)).tracking(-1).foregroundStyle(TunerTheme.paperWhite)
            VStack(spacing: 6) {
                ForEach(WelcomeStep.summary(style: model.registry.current.displayName, hasLid: model.stayAwake.hasLid, awakeOn: awakeOn), id: \.self) {
                    Text($0).font(TunerTheme.font(15)).foregroundStyle(TunerTheme.paperWhite.opacity(0.85))
                }
            }
            HStack(spacing: 6) {
                MarkGlyph(size: 12, tint: TunerTheme.paperWhite.opacity(0.55))
                Text("Shut lives in your menu bar.")
                    .font(TunerTheme.bodySmall).foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
            }
            .padding(.top, 6)
        }
    }

    private func heading(number: String, eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number)  \(eyebrow.uppercased())")
                .font(TunerTheme.mono(11)).tracking(2).foregroundStyle(TunerTheme.paperWhite.opacity(0.55))
            Text(title).font(TunerTheme.display(30)).tracking(-0.8).foregroundStyle(TunerTheme.paperWhite)
            Text(detail).font(TunerTheme.font(14)).foregroundStyle(TunerTheme.paperWhite.opacity(0.78)).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer: back, where you are, on

    private var footer: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(steps, id: \.self) { s in
                    Circle().fill(TunerTheme.paperWhite.opacity(s == step ? 0.9 : 0.25)).frame(width: 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Step \(index + 1) of \(steps.count)")
            HStack {
                if index > 0 {
                    Button("Back") { go(-1) }
                        .buttonStyle(.plain).font(TunerTheme.body).foregroundStyle(TunerTheme.paperWhite.opacity(0.6))
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Spacer()
                PrimaryButton(isLast ? "Start" : "Continue", onDark: true) { go(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 36).padding(.bottom, 28).padding(.top, 8)
        .modifier(Entrance(appeared: appeared, delay: 0.15))
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
