import SwiftUI
import TransitionKit
import Tuner

/// Right column: gallery, Speed, the style's featured dials, Animate opening,
/// and the permission card when the chosen style can't run yet.
struct ControlsColumn: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Style")
                    StyleGallery(model: model)
                }

                if model.needsPermissionCard {
                    PermissionCard(model: model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
                    Eyebrow("Timing").padding(.bottom, 2)
                    SpeedRow(model: model)
                    ToggleRow("Animate opening",
                              isOn: Binding(get: { model.settings.animateOpening }, set: { model.settings.animateOpening = $0 }),
                              help: "Play the style backwards when the lid opens or the Mac unlocks.")
                }

                FeelSection(model: model)
                    .id(model.registry.current.id)
                    .transition(.opacity)
            }
            .padding(14)
            .tunerAnimation(TunerTheme.spring, value: model.registry.current.id)
            .tunerAnimation(TunerTheme.spring, value: model.needsPermissionCard)
        }
        // A soft fade at the bottom says "there's more" without a scrollbar.
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
            }
        )
    }
}

struct StyleGallery: View {
    @ObservedObject var model: PopoverModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(model.registry.all, id: \.id) { transition in
                StyleCard(transition: transition,
                          image: model.thumbnail(for: transition),
                          isSelected: transition.id == model.registry.current.id,
                          needsPermission: transition.needsSnapshot && !model.registry.captureAvailable)
                    .onTapGesture { model.select(transition.id) }
            }
        }
        .id(model.thumbnailGeneration)
    }
}

struct StyleCard: View {
    let transition: TransitionKit.AnyTransition
    let image: CGImage?
    let isSelected: Bool
    let needsPermission: Bool
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    theme.surfaceActive
                }
            }
            .frame(height: 46)
            .clipped()
            HStack(spacing: 4) {
                Text(transition.displayName)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textRoot : theme.textLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if needsPermission {
                    Image(systemName: "record.circle").font(.system(size: 8)).foregroundStyle(theme.textTertiary)
                        .help("Needs Screen Recording")
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(theme.textRoot)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? theme.surfaceActive : (hover ? theme.surfaceHover : theme.surface)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(isSelected ? theme.textTertiary : theme.border, lineWidth: 1))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [theme.innerHighlight, .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 10)
                .mask(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(lineWidth: 1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(hover ? 0.25 : 0), radius: 8, y: 4)
        .scaleEffect(hover && !isSelected ? 1.02 : 1)
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.quick, value: hover)
        .tunerAnimation(TunerTheme.quick, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transition.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct SpeedRow: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 3) {
            FillSliderRow("Speed", value: Binding(get: { model.speed }, set: { model.speed = $0 }),
                          in: 0...1, step: 0.01, decimals: 2, unit: "",
                          help: "How much of the lid's travel the effect uses. Fast plays in the last few degrees; slow spreads it over most of the close.",
                          showsValue: false)
            HStack {
                Text("Slow"); Spacer()
                Text(String(format: "starts %.0f° above shut", model.settings.bandDegrees)); Spacer()
                Text("Fast")
            }
            .font(.system(size: 9.5)).foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 2)
        }
    }
}

struct FeelSection: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Eyebrow("Adjust \(model.registry.current.displayName)")
                Spacer()
                QuietButton("Reset") { model.resetStyle(model.registry.current.id) }
            }
            .padding(.bottom, 2)
            model.featuredDials(model.registry.current.id)
        }
    }
}

struct PermissionCard: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(.orange).frame(width: 7, height: 7)
                Text("\(model.registry.current.displayName) is showing as a plain fade").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.textRoot)
            }
            Text("It needs Screen Recording to take one still of your desktop as the lid moves. Nothing is saved. macOS checks the permission when the app starts, so restart it after allowing.")
                .font(.system(size: 10.5)).foregroundStyle(theme.textLabel).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TunerTheme.rowGap) {
                ActionRow("Allow…") { model.allowScreenRecording() }
                ActionRow("Restart") { model.relaunch() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border))
    }
}
