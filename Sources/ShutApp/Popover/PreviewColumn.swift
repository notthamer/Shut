import SwiftUI
import Tuner

/// Left column: the live preview, a scrubber, the style's name and summary, Play.
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

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Selected")
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
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, TunerTheme.sectionGap)
            .id(model.registry.current.id)
            .transition(.blurFade)
            .tunerAnimation(TunerTheme.ease, value: model.registry.current.id)

            Spacer(minLength: 0)
        }
    }
}

/// The preview as a product window: a white frame with traffic lights, the one
/// element allowed the three-layer drop shadow. The Awake page sets a caption into
/// it, so the user sees the close exactly as it will look.
struct PreviewWindow: View {
    @ObservedObject var preview: PreviewModel
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.38, blue: 0.35), Color(red: 1, green: 0.74, blue: 0.2), Color(red: 0.3, green: 0.8, blue: 0.35)], id: \.self) { c in
                    Circle().fill(c).frame(width: 8, height: 8)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            ZStack(alignment: .bottomLeading) {
                PreviewMetalView(model: preview)
                if !preview.hasSnapshot {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let caption {
                    ClosingCaption(text: caption, progress: preview.progress, scale: 0.36)
                        .padding(.leading, 12).padding(.bottom, 10)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding([.horizontal, .bottom], 6)
        }
        .surface(.card, radius: TunerTheme.cardRadius)
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
        .shadow(color: .black.opacity(0.14), radius: 24, y: 16)
    }
}

/// The one line set into the closing transition: "Staying awake · Cursor is
/// working". Low on the panel, where a closing lid is still readable. It fades
/// in as the effect begins and never moves.
struct ClosingCaption: View {
    let text: String
    /// 0 = open, 1 = shut.
    let progress: Double
    /// 1 on the real display; smaller inside the preview.
    var scale: CGFloat = 1

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        VStack(alignment: .leading, spacing: 2 * scale) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                    .font(TunerTheme.display(index == 0 ? 44 * scale : 30 * scale))
                    .tracking(-0.8 * scale)
                    .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.82))
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 10 * scale, y: 2 * scale)
        .opacity(min(max((progress - 0.04) / 0.18, 0), 1))
        .allowsHitTesting(false)
        .accessibilityLabel(text)
    }
}
