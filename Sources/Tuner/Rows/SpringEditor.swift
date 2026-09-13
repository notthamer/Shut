import SwiftUI

/// A spring as a curve plus two ways to describe it.
///
/// **Time**: Duration (how long until it visibly settles) and Bounce. **Physics**:
/// Stiffness and Damping. Both write the same `response` / `dampingFraction`
/// pair the app's `Spring` integrates: stiffness k = (2π / response)²,
/// damping c = 2 ζ √k. Switching mode never changes the motion, only the words.
public struct SpringEditor: View {
    let label: String
    @Binding var response: Double
    @Binding var damping: Double
    let responseRange: ClosedRange<Double>
    let dampingRange: ClosedRange<Double>

    @Environment(\.tunerTheme) private var theme
    @AppStorage private var physics: Bool

    public init(_ label: String, response: Binding<Double>, damping: Binding<Double>,
                responseRange: ClosedRange<Double> = 0.1...1.5, dampingRange: ClosedRange<Double> = 0.3...1.0) {
        self.label = label
        _response = response
        _damping = damping
        self.responseRange = responseRange
        self.dampingRange = dampingRange
        _physics = AppStorage(wrappedValue: false, "tuner.spring.physics.\(label)")
    }

    private var stiffness: Binding<Double> {
        Binding(get: { pow(2 * .pi / max(response, 0.01), 2) },
                set: { response = min(max(2 * .pi / sqrt(max($0, 1)), responseRange.lowerBound), responseRange.upperBound) })
    }
    private var dampingCoefficient: Binding<Double> {
        Binding(get: { 2 * damping * sqrt(pow(2 * .pi / max(response, 0.01), 2)) },
                set: { c in
                    let k = pow(2 * .pi / max(response, 0.01), 2)
                    damping = min(max(c / (2 * sqrt(k)), dampingRange.lowerBound), dampingRange.upperBound)
                })
    }
    private var bounce: Binding<Double> {
        Binding(get: { 1 - damping }, set: { damping = min(max(1 - $0, dampingRange.lowerBound), dampingRange.upperBound) })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Text(label).font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                Spacer()
                Text(String(format: "settles in %.2f s", settleTime))
                    .font(TunerTheme.caption).foregroundStyle(theme.textTertiary).monospacedDigit()
            }
            .padding(.horizontal, 2)

            SpringPlot(response: response, damping: damping)
                .frame(height: 140)

            SegmentedRow("Type", options: ["Time", "Physics"],
                         selection: Binding(get: { physics ? 1 : 0 }, set: { physics = $0 == 1 }))

            if physics {
                FillSliderRow("Stiffness", value: stiffness, in: 1...1000, step: 10, decimals: 0,
                              help: "Higher snaps back faster.")
                FillSliderRow("Damping", value: dampingCoefficient, in: 1...100, step: 1, decimals: 0,
                              help: "Higher settles sooner with less bounce.")
            } else {
                FillSliderRow("Duration", value: $response, in: responseRange, step: 0.01, decimals: 2, unit: "s",
                              help: "About how long until the motion visibly settles.")
                FillSliderRow("Bounce", value: bounce, in: 0...(1 - dampingRange.lowerBound), step: 0.01, decimals: 2,
                              help: "0 is critically damped; more overshoots past the target.")
            }
        }
    }

    /// Time to come within 0.5 % of the target.
    private var settleTime: Double {
        let k = pow(2 * .pi / max(response, 0.01), 2)
        let zeta = min(max(damping, 0.05), 1)
        let decay = zeta * sqrt(k)
        return min(max(log(200) / decay, 0.05), 10)
    }
}

struct SpringPlot: View {
    let response: Double
    let damping: Double
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let samples = SpringCurve.trajectory(response: response, damping: damping, duration: 2.0, samples: 101)
            // Normalise to the curve's own extent, drawn in the middle 60 % of the box.
            let lo = min(samples.min() ?? 0, 0), hi = max(samples.max() ?? 1, 1)
            func point(_ i: Int) -> CGPoint {
                let x = size.width * CGFloat(i) / CGFloat(samples.count - 1)
                let n = (samples[i] - lo) / max(hi - lo, 1e-6)
                let y = size.height - (CGFloat(n) * size.height * 0.6 + size.height * 0.2)
                return CGPoint(x: x, y: y)
            }
            for i in 1..<3 {
                var v = Path(); v.move(to: CGPoint(x: size.width * CGFloat(i) / 3, y: 0)); v.addLine(to: CGPoint(x: size.width * CGFloat(i) / 3, y: size.height))
                var h = Path(); h.move(to: CGPoint(x: 0, y: size.height * CGFloat(i) / 3)); h.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(i) / 3))
                context.stroke(v, with: .color(theme.hairline), lineWidth: 1)
                context.stroke(h, with: .color(theme.hairline), lineWidth: 1)
            }
            let targetY = size.height - (CGFloat((0 - lo) / max(hi - lo, 1e-6)) * size.height * 0.6 + size.height * 0.2)
            var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: targetY)); baseline.addLine(to: CGPoint(x: size.width, y: targetY))
            context.stroke(baseline, with: .color(theme.inkTertiary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            var path = Path(); path.move(to: point(0))
            for i in 1..<samples.count { path.addLine(to: point(i)) }
            context.stroke(path, with: .color(theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .surface(.well)
    }
}
