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
            // The preview as a product window: a white frame with traffic lights,
            // the one element allowed the three-layer drop shadow.
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach([Color(red: 1, green: 0.38, blue: 0.35), Color(red: 1, green: 0.74, blue: 0.2), Color(red: 0.3, green: 0.8, blue: 0.35)], id: \.self) { c in
                        Circle().fill(c).frame(width: 8, height: 8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                ZStack {
                    PreviewMetalView(model: preview)
                    if !preview.hasSnapshot {
                        ProgressView().controlSize(.small)
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

            VStack(spacing: 4) {
                FillSliderRow("Lid", value: $preview.progress, in: 0...1, step: 0.005, decimals: 2,
                              help: "Drag to move the lid by hand.", showsValue: false, height: 28, labelWidth: 30)
                HStack {
                    Text("Open"); Spacer(); Text("Shut")
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

            Spacer(minLength: 10)

            PrimaryButton("Play on screen") { model.play() }
                .help("Runs the effect full screen, exactly as closing the lid would.")
        }
    }
}
