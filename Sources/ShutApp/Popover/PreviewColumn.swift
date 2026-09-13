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
            ZStack {
                PreviewMetalView(model: preview)
                if !preview.hasSnapshot {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 164)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // A well cut into the glass: the picture sits below the surface.
            .glassSurface(.inset, radius: 14)

            VStack(spacing: 4) {
                FillSliderRow("Lid", value: $preview.progress, in: 0...1, step: 0.005, decimals: 2,
                              help: "Drag to move the lid by hand.", showsValue: false, height: 28, labelWidth: 30)
                HStack {
                    Text("Open"); Spacer(); Text("Shut")
                }
                .font(TunerTheme.captionSmall).tracking(TunerTheme.captionSmallTracking)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 2)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Selected")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.registry.current.displayName).font(TunerTheme.font(15, weight: .semibold)).tracking(-0.2).foregroundStyle(theme.textRoot)
                    if let badge = model.registry.current.badge {
                        Text(badge)
                            .font(TunerTheme.captionSmall).tracking(TunerTheme.captionSmallTracking)
                            .foregroundStyle(theme.textLabel)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(theme.surfaceActive))
                    }
                }
                Text(model.registry.current.summary).font(TunerTheme.font(11.5)).foregroundStyle(theme.textLabel)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
            .id(model.registry.current.id)
            .transition(.blurFade)
            .tunerAnimation(TunerTheme.easeOut(0.18), value: model.registry.current.id)

            Spacer(minLength: 10)

            PrimaryButton("Play on screen") { model.play() }
                .help("Runs the effect full screen, exactly as closing the lid would.")
        }
    }
}
