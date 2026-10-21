import SwiftUI
import Tuner

/// The face of Lid sound, as the eyes are Stay awake's: three bars. Off, they are still.
/// On, they breathe, slowly; while a sound plays they move to it. On the page they lean
/// toward the pointer when it comes near, and a click on them plays the sound. Every
/// movement is a pure function of time (`heights(at:)`), so only a glyph that moves has a
/// clock, only while it is on screen, and Reduce Motion stills it. Thirty frames a second,
/// breathing or playing: at fifteen the breath was seen to step.
struct LidSoundGlyph: View {
    let playing: Bool
    let height: CGFloat
    let tint: Color
    /// On but quiet: the slow breath. Off: still.
    var breathes = false
    /// The bars lean toward the pointer. For the big glyph on the page; the small one in a
    /// tab is too small to be leaned at.
    var follows = false
    /// A click on the glyph, when it does something (the page: hear the sound).
    var onTap: (() -> Void)? = nil
    /// How far around the bars "near" reaches, in points.
    static let reach: CGFloat = 44
    @State private var hover: Hover?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var scale

    /// Where the pointer is across the glyph, -1 (left) to 1 (right), and since when, so the
    /// lean eases in over a moment instead of jumping.
    struct Hover: Equatable {
        var x: CGFloat
        var since: TimeInterval
    }

    /// Resting heights, as fractions of `height`: a shape, not a level meter at zero.
    static let rest: [CGFloat] = [0.4, 1, 0.6]
    /// The bars' places across the glyph, for the lean.
    static let places: [CGFloat] = [-1, 0, 1]

    /// The bars at a moment in time. Playing: three waves out of step, never all down at
    /// once. Breathing: the resting shape, rising and falling a little over about six
    /// seconds. A pointer near lifts the bar under it and lets the others dip, eased in
    /// over 0.2 s from `hover.since`.
    static func heights(at t: TimeInterval, playing: Bool, breathing: Bool, hover: Hover? = nil) -> [CGFloat] {
        var heights: [CGFloat]
        if playing {
            heights = [0.55 + 0.4 * CGFloat(sin(t * 5.1)), 0.65 + 0.35 * CGFloat(sin(t * 6.7 + 1.3)), 0.5 + 0.4 * CGFloat(sin(t * 4.3 + 2.4))]
        } else if breathing {
            heights = rest.enumerated().map { i, h in h + 0.06 * CGFloat(sin(t * 1.05 + Double(i) * 0.9)) }
        } else {
            heights = rest
        }
        if let hover {
            let blend = CGFloat(min(1, max(0, (t - hover.since) / 0.2)))
            heights = zip(heights, places).map { h, place in
                let near = max(0, 1 - abs(place - hover.x) * 0.9)
                return h + blend * (0.3 * near - 0.06)
            }
        }
        return heights.map { max(0.15, min(1, $0)) }
    }

    private var moves: Bool { !reduceMotion && (playing || breathes || hover != nil) }

    var body: some View {
        Group {
            if moves {
                TimelineView(.periodic(from: .now, by: 1 / 30)) { context in
                    bars(Self.heights(at: context.date.timeIntervalSinceReferenceDate, playing: playing, breathing: breathes, hover: hover))
                }
            } else {
                bars(Self.rest)
            }
        }
        .frame(width: width * 3 + spacing * 2, height: height)
        .overlay {
            if follows, !reduceMotion {
                // A wider, invisible ring around the bars tracks the pointer; it changes no layout.
                let ringWidth = width * 3 + spacing * 2 + 2 * Self.reach, ringHeight = height + 2 * Self.reach
                Color.clear.frame(width: ringWidth, height: ringHeight).contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point):
                            let x = max(-1, min(1, (point.x - ringWidth / 2) / (width * 1.5 + spacing)))
                            if let current = hover { hover = Hover(x: x, since: current.since) }
                            else { hover = Hover(x: x, since: Date().timeIntervalSinceReferenceDate) }
                        case .ended:
                            hover = nil
                        }
                    }
                    .onTapGesture { onTap?() }
            }
        }
        .accessibilityHidden(onTap == nil)   // the sentence beside it says the same thing
        .accessibilityLabel("Hear the sound")
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .help(onTap == nil ? "" : "Hear the sound the next close would play.")
    }

    private var width: CGFloat { snapped(height / 4) }
    private var spacing: CGFloat { snapped(width * 0.75) }

    /// A length on the device pixel grid. A capsule whose ends fall between pixels is drawn
    /// with a blurred edge, and as the bars breathe that blur moves, which reads as rough;
    /// on the grid every frame has the same crisp edge.
    private func snapped(_ points: CGFloat) -> CGFloat { (points * scale).rounded() / scale }

    private func bars(_ fractions: [CGFloat]) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                Capsule().fill(tint).frame(width: width, height: snapped(max(width, height * fraction)))
            }
        }
        .frame(height: height)
    }
}
