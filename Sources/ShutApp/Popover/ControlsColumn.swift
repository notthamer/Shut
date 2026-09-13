import SwiftUI
import TransitionKit
import Tuner

/// Right column: gallery, Speed, the style's featured dials, Animate opening,
/// and the permission card when the chosen style can't run yet.
struct ControlsColumn: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: true) {
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
                    .transition(.blurFade)
            }
            .padding(14)
            // A style change swaps the dials: a blur-bridged fade so the outgoing
            // and incoming rows read as one block changing, not two overlapping.
            .tunerAnimation(TunerTheme.easeOut(0.18), value: model.registry.current.id)
            .tunerAnimation(TunerTheme.spring, value: model.needsPermissionCard)
        }
    }
}

struct StyleGallery: View {
    @ObservedObject var model: PopoverModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(model.registry.all, id: \.id) { transition in
                StyleCard(transition: transition,
                          image: model.thumbnail(for: transition),
                          version: model.thumbnailVersion(for: transition.id),
                          isSelected: transition.id == model.registry.current.id,
                          needsPermission: transition.needsSnapshot && !model.registry.captureAvailable,
                          select: { model.select(transition.id) })
            }
        }
    }
}

struct StyleCard: View {
    let transition: TransitionKit.AnyTransition
    let image: CGImage?
    /// Bumps when this card's thumbnail was re-rendered; the image crossfades.
    let version: Int
    let isSelected: Bool
    let needsPermission: Bool
    let select: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    static let radius: CGFloat = 14

    var body: some View {
        Button(action: select) { card }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .focusEffectDisabled()
            .onHover { hover = $0 }
            .accessibilityLabel(transition.displayName)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .id(version)
                        .transition(.opacity)
                } else {
                    theme.surfaceActive
                }
            }
            .frame(height: 44)
            .clipped()
            .tunerAnimation(TunerTheme.easeOut(0.16), value: version)
            HStack(spacing: 4) {
                Text(transition.displayName)
                    .font(TunerTheme.cardTitle)
                    .tracking(TunerTheme.cardTitleTracking)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? theme.textRoot : theme.textLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundStyle(theme.textRoot)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
        .background(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(hover && !isSelected ? theme.raisedHover : .clear))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .glassSurface(isSelected ? .tinted(theme.tintAmber) : .raised, radius: Self.radius)
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(TunerTheme.inkBase.opacity(isSelected ? 0.35 : 0), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .scaleEffect(hover && !isSelected ? 1.02 : 1)
        .tunerAnimation(TunerTheme.quick, value: hover)
        .tunerMotion(TunerTheme.quick, value: hover)
        .tunerAnimation(TunerTheme.quick, value: isSelected)
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
                Text(String(format: "starts %.0f° above shut", model.settings.bandDegrees)).monospacedDigit(); Spacer()
                Text("Fast")
            }
            .font(TunerTheme.captionSmall).tracking(TunerTheme.captionSmallTracking)
            .foregroundStyle(theme.textTertiary)
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
                Circle().fill(TunerTheme.saffron).frame(width: 7, height: 7)
                Text("\(model.registry.current.displayName) is showing as a plain fade").font(TunerTheme.font(11, weight: .semibold)).foregroundStyle(theme.textRoot)
            }
            Text("It needs Screen Recording to take one still of your desktop as the lid moves. Nothing is saved. macOS checks the permission when the app starts, so restart it after allowing.")
                .font(TunerTheme.font(11)).foregroundStyle(theme.textLabel).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: TunerTheme.rowGap) {
                ActionRow("Allow…") { model.allowScreenRecording() }
                ActionRow("Restart") { model.relaunch() }
            }
        }
        .padding(12)
        .glassSurface(.tinted(theme.tintAmber), radius: TunerTheme.cardRadius)
    }
}
