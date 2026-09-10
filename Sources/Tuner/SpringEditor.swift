import SwiftUI

/// Response and damping sliders with a live plot of the resulting motion.
struct SpringEditorView<P>: View {
    @Binding var values: P
    let spec: SpringSpec<P>

    private var response: Double { spec.getResponse(values) }
    private var damping: Double { spec.getDamping(values) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(spec.label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f s · %.2f", response, damping))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            SpringPlot(response: response, damping: damping)
                .frame(height: 64)
            HStack(spacing: 8) {
                Text("Response").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Slider(value: Binding(get: { response }, set: { spec.setResponse(&values, $0) }),
                       in: spec.responseRange).controlSize(.small)
            }
            HStack(spacing: 8) {
                Text("Damping").font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Slider(value: Binding(get: { damping }, set: { spec.setDamping(&values, $0) }),
                       in: spec.dampingRange).controlSize(.small)
            }
        }
    }
}

struct SpringPlot: View {
    let response: Double
    let damping: Double

    var body: some View {
        Canvas { context, size in
            let samples = SpringCurve.trajectory(response: response, damping: damping)
            // Plot 1 → 0 with room for overshoot below zero.
            let top = 1.15, bottom = -0.35
            func point(_ i: Int) -> CGPoint {
                let x = size.width * CGFloat(i) / CGFloat(samples.count - 1)
                let y = size.height * CGFloat((top - samples[i]) / (top - bottom))
                return CGPoint(x: x, y: y)
            }
            let zeroY = size.height * CGFloat(top / (top - bottom))
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: zeroY))
            baseline.addLine(to: CGPoint(x: size.width, y: zeroY))
            context.stroke(baseline, with: .color(.secondary.opacity(0.3)), lineWidth: 1)

            var path = Path()
            path.move(to: point(0))
            for i in 1..<samples.count { path.addLine(to: point(i)) }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}
