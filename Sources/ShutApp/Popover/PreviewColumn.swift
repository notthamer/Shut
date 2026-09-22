import SwiftUI
import Tuner

/// Left column: the live preview, a scrubber, the style's name and summary, and its timing.
struct PreviewColumn: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var preview: PreviewModel
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel) {
        self.model = model
        preview = model.preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreviewWindow(preview: preview)

            VStack(spacing: 4) {
                FillSliderRow("Lid", value: $preview.progress, in: 0...1, step: 0.005, decimals: 2,
                              help: "Drag to move the lid by hand.", showsValue: false, height: 28, labelWidth: 36)
                HStack {
                    Text("Open")
                    Spacer()
                    // Replays close and open here, in the preview.
                    Button { preview.playRound() } label: {
                        Text(preview.isPlaying ? "Playing…" : "Play")
                            .foregroundStyle(theme.inkLabel)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help("Play the close and the opening in the preview.")
                    Spacer()
                    Text("Shut")
                }
                .font(TunerTheme.bodySmall)
                .foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 2)
            }
            .padding(.top, 16)

            // The name is its own heading; an eyebrow saying "Selected" over it only cost a row.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.registry.current.displayName)
                        .font(TunerTheme.heading).tracking(TunerTheme.headingTracking).foregroundStyle(theme.ink)
                    if let badge = model.registry.current.badge {
                        Text(badge)
                            .font(TunerTheme.bodySmall)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .surface(.pill)
                    }
                }
                Text(model.registry.current.summary).font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                    .lineSpacing(4)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)
            .id(model.registry.current.id)
            .transition(.blurFade)
            .tunerAnimation(TunerTheme.ease, value: model.registry.current.id)

            Spacer(minLength: 14)

            // Timing belongs to the preview: Speed is how much of the close the effect
            // uses, and letting go of it replays the close right above.
            VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
                Eyebrow("Timing").padding(.bottom, 2)
                SpeedRow(model: model, labelWidth: 48)
                ToggleRow("Animate opening",
                          isOn: Binding(get: { model.settings.animateOpening }, set: { model.settings.animateOpening = $0 }),
                          help: "Play the style backwards when the lid opens or the Mac unlocks.")
            }
        }
    }
}

/// The preview as a product window: a white frame with traffic lights, the one
/// element allowed the three-layer drop shadow. The Awake page sets a caption into
/// it, so the user sees the close exactly as it will look.
struct PreviewWindow: View {
    @ObservedObject var preview: PreviewModel
    var caption: AwakeText.Caption? = nil
    /// A small illustration (the Stay awake page) instead of the page's centrepiece.
    var compact = false

    var body: some View {
        let dot: CGFloat = compact ? 5 : 8
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.38, blue: 0.35), Color(red: 1, green: 0.74, blue: 0.2), Color(red: 0.3, green: 0.8, blue: 0.35)], id: \.self) { c in
                    Circle().fill(c).frame(width: dot, height: dot)
                }
                Spacer()
            }
            .padding(.horizontal, compact ? 7 : 10)
            .frame(height: compact ? 15 : 24)
            ZStack(alignment: .bottomLeading) {
                PreviewMetalView(model: preview)
                if !preview.hasSnapshot {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let caption {
                    ClosingCaption(caption: caption, progress: preview.progress, scale: compact ? 0.17 : 0.36)
                }
            }
            .frame(height: compact ? 78 : 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
            .padding([.horizontal, .bottom], compact ? 4 : 6)
        }
        .surface(.card, radius: compact ? 8 : TunerTheme.cardRadius)
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(compact ? 0.08 : 0.12), radius: compact ? 6 : 12, y: compact ? 4 : 8)
        .shadow(color: .black.opacity(compact ? 0 : 0.14), radius: 24, y: 16)
    }
}

/// The one line set into the closing transition: "Staying awake · Cursor is
/// working". Low on the panel, where a closing lid is still readable. It fades
/// in as the effect begins and never moves.
struct ClosingCaption: View {
    let caption: AwakeText.Caption
    /// 0 = open, 1 = shut.
    let progress: Double
    /// 1 on the real display; smaller inside the preview.
    var scale: CGFloat = 1

    var body: some View {
        let parts = caption.text.components(separatedBy: " · ")
        VStack(alignment: .leading, spacing: 2 * scale) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .font(TunerTheme.display(index == 0 ? 44 * scale : 30 * scale))
                    .tracking(-0.8 * scale)
                    .foregroundStyle(index == 0 ? (caption.warning ? TunerTheme.saffron : .white) : .white.opacity(0.86))
            }
            if let hint = caption.hint {
                Text(hint).font(TunerTheme.font(17 * scale)).foregroundStyle(.white.opacity(0.8)).padding(.top, 6 * scale)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 10 * scale, y: 2 * scale)
        .padding(.leading, 33 * scale).padding(.bottom, 28 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // The same dark gradient the real overlay lays under its caption.
        .background(alignment: .bottom) {
            GeometryReader { proxy in
                LinearGradient(stops: ClosingCaptionView.scrimStops.map { .init(color: .black.opacity($0.alpha), location: $0.location) },
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.size.height * ClosingCaptionView.scrimHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .opacity(min(max((progress - 0.04) / 0.18, 0), 1))
        .allowsHitTesting(false)
        .accessibilityLabel([caption.text, caption.hint ?? ""].filter { !$0.isEmpty }.joined(separator: ". "))
    }
}
