import SwiftUI
import Tuner

/// The face of Lid sound, as the eyes are Stay awake's: three bars. Still at rest; while a
/// sound plays they move, on a loop that is a pure function of time, so only a glyph that
/// moves has a clock, and only while it is on screen. Reduce Motion stills it.
struct LidSoundGlyph: View {
    let playing: Bool
    let height: CGFloat
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resting heights, as fractions of `height`: a shape, not a level meter at zero.
    static let rest: [CGFloat] = [0.4, 1, 0.6]

    /// The bars at a moment in time: three slow waves out of step, never all down at once.
    static func heights(at t: TimeInterval) -> [CGFloat] {
        [0.55 + 0.4 * CGFloat(sin(t * 5.1)), 0.65 + 0.35 * CGFloat(sin(t * 6.7 + 1.3)), 0.5 + 0.4 * CGFloat(sin(t * 4.3 + 2.4))]
            .map { max(0.15, min(1, $0)) }
    }

    var body: some View {
        if playing, !reduceMotion {
            TimelineView(.animation) { context in
                bars(Self.heights(at: context.date.timeIntervalSinceReferenceDate))
            }
        } else {
            bars(Self.rest)
        }
    }

    private func bars(_ fractions: [CGFloat]) -> some View {
        let width = height / 4
        return HStack(alignment: .center, spacing: width * 0.75) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                Capsule().fill(tint).frame(width: width, height: max(width, height * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
