import SwiftUI
import TransitionKit
import Tuner

/// Aspect ratio of the built-in display, so the preview matches the real screen.
enum BuiltInDisplayAspect {
    static var ratio: CGFloat {
        guard let f = BuiltInDisplay.screen?.frame, f.height > 0 else { return 16.0 / 10.0 }
        return f.width / f.height
    }
}

/// Hosts the Metal preview view inside SwiftUI.
struct PreviewMetalView: NSViewRepresentable {
    @ObservedObject var model: PreviewModel

    func makeNSView(context: Context) -> PreviewHostView {
        let view = MetalTransitionView(renderer: model.renderer, transition: model.registry.current, context: model.context)
        model.metalView = view
        return PreviewHostView(metal: view) { [weak model] metal in
            guard let model, model.metalView !== metal else { return }
            model.metalView = metal
            model.render()
        }
    }

    func updateNSView(_ host: PreviewHostView, context: Context) {
        model.render()
    }
}

/// The popover and the main window both show the preview from one
/// `PreviewModel`, which draws into a single Metal view at a time. Whichever
/// host's window is key claims the model, so the preview the user is looking
/// at is the one that moves.
final class PreviewHostView: NSView {
    let metal: MetalTransitionView
    private let claim: (MetalTransitionView) -> Void
    private var keyObserver: NSObjectProtocol?

    init(metal: MetalTransitionView, claim: @escaping (MetalTransitionView) -> Void) {
        self.metal = metal
        self.claim = claim
        super.init(frame: .zero)
        metal.frame = bounds
        metal.autoresizingMask = [.width, .height]
        addSubview(metal)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        claim(metal)
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.claim(self.metal) }
        }
    }
}

/// The preview area: the snapshot with transport controls, drawn with Tuner's
/// rows so it belongs to the same visual system. Used inside Tuner and, from the
/// popover, on its own.
struct PreviewArea: View {
    @ObservedObject var model: PreviewModel
    @ObservedObject var registry: TransitionRegistry
    var aspect: CGFloat
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: TunerTheme.rowGap) {
            ZStack {
                PreviewMetalView(model: model)
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border))
                if !model.hasSnapshot {
                    VStack(spacing: 8) {
                        if model.isCapturing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(model.errorText ?? "No snapshot yet").font(TunerTheme.caption).foregroundStyle(theme.textLabel)
                            ActionRow("Capture desktop") { model.capture() }.frame(width: 160)
                        }
                    }
                }
            }
            .padding(.bottom, 4)

            FillSliderRow("Progress", value: $model.progress, in: -0.15...1, step: 0.005, decimals: 2,
                          help: "Scrub the effect by hand. Below 0 is the pour-out overshoot.")
                .disabled(model.followLid)
                .opacity(model.followLid ? 0.5 : 1)

            HStack(spacing: TunerTheme.rowGap) {
                ActionRow("Play close") { model.playClose() }
                ActionRow("Play open") { model.playPourOut() }
            }
            ToggleRow("Follow lid", isOn: $model.followLid, help: "Drive the preview from the real hinge.")
            HStack {
                Text(String(format: "%.2f ms per frame", model.frameTimeMs))
                    .font(TunerTheme.caption).foregroundStyle(theme.textTertiary).monospacedDigit()
                Spacer()
                if let error = model.errorText, model.hasSnapshot {
                    Text(error).font(TunerTheme.caption).foregroundStyle(theme.danger)
                }
                PanelIconButtonProxy { model.capture() }
            }
            .padding(.horizontal, 2)
        }
        .tunerThemed()
    }
}

/// Small camera glyph to re-capture the desktop.
private struct PanelIconButtonProxy: View {
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    var body: some View {
        Image(systemName: "camera")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(hover ? theme.textRoot : theme.textLabel)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
            .help("Re-capture the desktop")
    }
}
