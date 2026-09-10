import SwiftUI

/// A cubic-bezier easing editor: drag the two handles, or type the numbers.
struct BezierEditorView<P>: View {
    @Binding var values: P
    let spec: BezierSpec<P>

    private var curve: Binding<TunerBezier> {
        Binding(get: { spec.get(values) }, set: { spec.set(&values, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(spec.label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Linear") { curve.wrappedValue = .linear }
                    Button("Ease in") { curve.wrappedValue = .easeIn }
                    Button("Ease out") { curve.wrappedValue = .easeOut }
                    Button("Ease in-out") { curve.wrappedValue = .easeInOut }
                } label: { Text("Presets") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
            BezierCanvas(curve: curve)
                .frame(height: 140)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    TextField("", value: component(i), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospacedDigit())
                        .frame(width: 54)
                }
                Spacer()
            }
        }
    }

    private func component(_ i: Int) -> Binding<Double> {
        Binding(
            get: {
                let c = curve.wrappedValue
                return [c.x1, c.y1, c.x2, c.y2][i]
            },
            set: { v in
                var c = curve.wrappedValue
                switch i {
                case 0: c.x1 = min(max(v, 0), 1)
                case 1: c.y1 = v
                case 2: c.x2 = min(max(v, 0), 1)
                default: c.y2 = v
                }
                curve.wrappedValue = c
            })
    }
}

struct BezierCanvas: View {
    @Binding var curve: TunerBezier
    @State private var dragging: Int?

    // y is allowed slightly outside 0...1 (like CSS), so leave margins.
    private let yMin = -0.3, yMax = 1.3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, size in
                    let p0 = point(0, 0, size), p3 = point(1, 1, size)
                    let c1 = point(curve.x1, curve.y1, size), c2 = point(curve.x2, curve.y2, size)

                    // Unit square for reference.
                    var box = Path()
                    box.addRect(CGRect(x: p0.x, y: p3.y, width: p3.x - p0.x, height: p0.y - p3.y))
                    context.stroke(box, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

                    // Handles.
                    var arms = Path()
                    arms.move(to: p0); arms.addLine(to: c1)
                    arms.move(to: p3); arms.addLine(to: c2)
                    context.stroke(arms, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

                    var path = Path()
                    path.move(to: p0)
                    path.addCurve(to: p3, control1: c1, control2: c2)
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2)

                    for (i, c) in [c1, c2].enumerated() {
                        let r: CGFloat = dragging == i ? 7 : 5
                        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(.accentColor))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragging == nil {
                            let c1 = point(curve.x1, curve.y1, size), c2 = point(curve.x2, curve.y2, size)
                            dragging = hypot(drag.location.x - c1.x, drag.location.y - c1.y)
                                     < hypot(drag.location.x - c2.x, drag.location.y - c2.y) ? 0 : 1
                        }
                        let (x, y) = unpoint(drag.location, size)
                        if dragging == 0 { curve.x1 = x; curve.y1 = y } else { curve.x2 = x; curve.y2 = y }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private func point(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        let inset: CGFloat = 8
        let w = size.width - 2 * inset
        let h = size.height
        return CGPoint(x: inset + w * CGFloat(x),
                       y: h * CGFloat((yMax - y) / (yMax - yMin)))
    }

    private func unpoint(_ p: CGPoint, _ size: CGSize) -> (Double, Double) {
        let inset: CGFloat = 8
        let w = size.width - 2 * inset
        let x = min(max(Double((p.x - inset) / w), 0), 1)
        let y = yMax - Double(p.y / size.height) * (yMax - yMin)
        return (x, min(max(y, yMin), yMax))
    }
}
