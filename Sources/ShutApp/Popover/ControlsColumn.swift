import SwiftUI
import TransitionKit
import Tuner

/// Right column: gallery, the permission card when the chosen style can't run yet, the
/// style's dials, presets. Timing lives under the preview, which is what it changes.
struct ControlsColumn: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: TunerTheme.sectionGap) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Style", number: "01")
                    StyleGallery(model: model)
                }

                if model.needsPermissionCard {
                    PermissionCard(model: model)
                        .transition(.opacity)
                }

                FeelSection(model: model)
                    .id(model.registry.current.id)
                    .transition(.blurFade)

                ShareSection(model: model)
                    .id("share-" + model.registry.current.id)
                    .transition(.blurFade)
            }
            .padding(16)
            // A style change swaps the dials: a blur-bridged fade so the outgoing
            // and incoming rows read as one block changing, not two overlapping.
            .tunerAnimation(TunerTheme.ease, value: model.registry.current.id)
            .tunerAnimation(TunerTheme.ease, value: model.needsPermissionCard)
        }
        .fadesAtTheFold()
    }
}

extension View {
    /// A scrolling column ends in a short fade, so a row cut by the bottom edge reads as
    /// "there is more" instead of as a mistake. A mask, because the panel is glass: there
    /// is no paper colour to paint over it.
    func fadesAtTheFold() -> some View {
        mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.975),
                                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
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
    static let radius: CGFloat = TunerTheme.cardRadius

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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding([.horizontal, .top], 4)
            .tunerAnimation(TunerTheme.ease, value: version)
            HStack(spacing: 4) {
                Text(transition.displayName)
                    .font(isSelected ? TunerTheme.bodyMedium : TunerTheme.body)
                    .foregroundStyle(isSelected ? theme.ink : theme.inkLabel)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        // Lime wash when chosen, Paper White otherwise, Linen on hover; a
        // one-point border does the depth, no shadow, nothing scales.
        .surface(isSelected ? .wash(TunerTheme.wash(for: transition.id)) : .card, radius: Self.radius)
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(hover && !isSelected ? theme.linen.opacity(0.6) : .clear).allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(isSelected ? theme.borderStrong : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .tunerAnimation(TunerTheme.ease, value: hover)
        .tunerAnimation(TunerTheme.ease, value: isSelected)
    }
}

struct SpeedRow: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    /// Same as the row's label column, so the end labels sit under the track.
    var labelWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: 0) {
            FillSliderRow("Speed", value: Binding(get: { model.speed }, set: { model.speed = $0 }),
                          in: 0...1, step: 0.01, decimals: 2, unit: "",
                          help: "How much of the lid's travel the effect uses: the number is where the effect starts, in degrees above shut. Fast plays in the last few degrees; slow spreads it over the whole close. The number stops a few degrees under wherever your lid rests.",
                          labelWidth: labelWidth,
                          valueText: { _ in String(format: "%.0f°", model.effectiveStartDegrees) },
                          onEditingEnded: { model.preview.playRound() })
            // "Slow" under the left end of the track, "Fast" under the right end,
            // so each word reads as the end of the dial it names.
            HStack {
                Text("Slow"); Spacer(); Text("Fast")
            }
            .padding(.leading, labelWidth + 12)
            .padding(.trailing, FillSliderRow.valueWidth + 12)
            .font(TunerTheme.bodySmall)
            .foregroundStyle(theme.inkTertiary)
        }
    }
}

/// The style's main dials, then every other dial behind "All dials", so the
/// whole style is tunable on this page without opening anything else.
struct FeelSection: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Eyebrow("Adjust \(model.registry.current.displayName)", number: "02")
                Spacer()
                QuietButton(showAll ? "Main dials" : "All dials") { showAll.toggle() }
                QuietButton("Reset") { model.resetStyle(model.registry.current.id) }
            }
            .padding(.bottom, 2)
            model.featuredDials(model.registry.current.id)
            if showAll {
                model.moreDials(model.registry.current.id)
                    .padding(.top, 6)
                    .transition(.blurFade)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: showAll)
    }
}

/// Presets for the style: pick one, name the current dials, copy or export the
/// JSON, paste or import someone else's.
struct ShareSection: View {
    @ObservedObject var model: PopoverModel
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Eyebrow("Presets", number: "03")
                Spacer()
                QuietButton(expanded ? "Done" : "Share…") { expanded.toggle() }
                    .help("Copy or export this preset, or paste and import one.")
            }
            .padding(.bottom, 2)
            model.shareView(model.registry.current.id, $expanded)
        }
    }
}

/// A style that needs a still of the desktop plays as a plain fade until Screen Recording
/// is allowed. Not an emergency, so not a Saffron block: a card with a Saffron dot, one
/// sentence, and one next step at a time. macOS only honours the permission after a
/// restart, so once "Allow…" has been used the step becomes the restart.
struct PermissionCard: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let asked = model.askedForScreenRecording
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(TunerTheme.saffron).overlay(Circle().strokeBorder(theme.ink.opacity(0.5), lineWidth: 1))
                    .frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.registry.current.displayName) is showing as a plain fade")
                        .font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    Text(asked ? "Allowed it? macOS applies the permission when Shut restarts."
                               : "It needs Screen Recording for one still of your desktop. Nothing is saved.")
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 14) {
                if asked {
                    PrimaryButton("Restart Shut") { model.relaunch() }
                    QuietButton("Open Settings again") { model.allowScreenRecording() }
                } else {
                    PrimaryButton("Allow…") { model.askedForScreenRecording = true; model.allowScreenRecording() }
                }
            }
            .padding(.leading, 15)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(.card, radius: TunerTheme.cardRadius)
        .tunerAnimation(TunerTheme.ease, value: asked)
    }
}
