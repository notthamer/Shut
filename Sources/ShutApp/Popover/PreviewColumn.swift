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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.border))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [theme.innerHighlight, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)
                    .mask(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            VStack(spacing: 3) {
                FillSliderRow("", value: $preview.progress, in: 0...1, step: 0.005, decimals: 2,
                              help: "Drag to move the lid by hand.")
                    .frame(height: 24)
                HStack {
                    Text("Open"); Spacer(); Text("Shut")
                }
                .font(.system(size: 9.5)).foregroundStyle(theme.textTertiary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Selected")
                Text(model.registry.current.displayName).font(.system(size: 14, weight: .semibold)).tracking(-0.2).foregroundStyle(theme.textRoot)
                Text(model.registry.current.summary).font(.system(size: 11)).foregroundStyle(theme.textLabel)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
            .id(model.registry.current.id)
            .transition(.opacity)
            .tunerAnimation(TunerTheme.quick, value: model.registry.current.id)

            Spacer(minLength: 10)

            PrimaryButton("Play on screen") { model.play() }
                .help("Runs the effect full screen, exactly as closing the lid would.")
        }
    }
}
