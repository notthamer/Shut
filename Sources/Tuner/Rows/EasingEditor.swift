import SwiftUI

/// A cubic-bezier easing editor: drag the two handles, type the four numbers, or
/// pick a preset. X is clamped to 0…1, Y to −1…2, and the graph zooms out on its
/// own so the 0→1 reference always stays at 45° even when the curve overshoots.
public struct EasingEditor: View {
    let label: String
    @Binding var curve: TunerBezier
    @Environment(\.tunerTheme) private var theme
    @State private var text = ""
    @FocusState private var textFocused: Bool

    public init(_ label: String, curve: Binding<TunerBezier>) {
        self.label = label
        _curve = curve
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            HStack {
                Text(label).font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                Spacer()
                Menu {
                    Button("Linear") { curve = .linear }
                    Button("Ease in") { curve = .easeIn }
                    Button("Ease out") { curve = .easeOut }
                    Button("Ease in-out") { curve = .easeInOut }
                    Button("Overshoot") { curve = TunerBezier(0.25, -0.6, 0.6, 1.6) }
                } label: {
                    Text("Presets").font(TunerTheme.caption).foregroundStyle(theme.textLabel)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 2)

            EasingCanvas(curve: $curve)
                .aspectRatio(256.0 / 180.0, contentMode: .fit)
                .surface(.well)

            HStack(spacing: 8) {
                Text("Ease").font(TunerTheme.label).foregroundStyle(theme.textLabel)
                Spacer()
                TextField("x1, y1, x2, y2", text: $text)
                    .textFieldStyle(.plain)
                    .font(TunerTheme.value)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .focused($textFocused)
                    .onSubmit(commitText)
                    .onChange(of: textFocused) { _, f in if !f { commitText() } }
            }
            .frame(height: TunerTheme.rowHeight)
        }
        .onAppear { syncText() }
        .onChange(of: curve) { _, _ in if !textFocused { syncText() } }
    }

    private func syncText() {
        text = [curve.x1, curve.y1, curve.x2, curve.y2].map { String(format: "%.2f", $0) }.joined(separator: ", ")
    }

    private func commitText() {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { syncText(); return }
        curve = TunerBezier(min(max(parts[0], 0), 1), min(max(parts[1], -1), 2), min(max(parts[2], 0), 1), min(max(parts[3], -1), 2))
        syncText()
    }
}

struct EasingCanvas: View {
    @Binding var curve: TunerBezier
    @Environment(\.tunerTheme) private var theme
    @State private var dragging: Int?
    @State private var dragOrigin: TunerBezier?
    @State private var hoverHandle: Int?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let fit = EasingFit(size: size, curve: curve)
            ZStack {
                Canvas { context, _ in
                    let p0 = fit.project(0, 0), p3 = fit.project(1, 1)
                    let c1 = fit.project(curve.x1, curve.y1), c2 = fit.project(curve.x2, curve.y2)

                    var reference = Path(); reference.move(to: p0); reference.addLine(to: p3)
                    context.stroke(reference, with: .color(theme.textTertiary), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    var guides = Path()
                    guides.move(to: p0); guides.addLine(to: c1)
                    guides.move(to: p3); guides.addLine(to: c2)
                    context.stroke(guides, with: .color(theme.textTertiary), lineWidth: 1)

                    var path = Path(); path.move(to: p0); path.addCurve(to: p3, control1: c1, control2: c2)
                    context.stroke(path, with: .color(theme.textPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    for p in [p0, p3] {
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(theme.textPrimary))
                    }
                }
                ForEach(0..<2, id: \.self) { i in
                    let p = i == 0 ? fit.project(curve.x1, curve.y1) : fit.project(curve.x2, curve.y2)
                    let active = dragging == i || hoverHandle == i
                    Knob(size: 12, fill: active ? TunerTheme.pureBlack : theme.buttonDark)
                        .tunerAnimation(TunerTheme.ease, value: active)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .position(p)
                        .onHover { hoverHandle = $0 ? i : (hoverHandle == i ? nil : hoverHandle) }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragging == nil {
                            let c1 = fit.project(curve.x1, curve.y1), c2 = fit.project(curve.x2, curve.y2)
                            dragging = hypot(g.startLocation.x - c1.x, g.startLocation.y - c1.y) <= hypot(g.startLocation.x - c2.x, g.startLocation.y - c2.y) ? 0 : 1
                            dragOrigin = curve
                        }
                        guard let origin = dragOrigin, let index = dragging else { return }
                        // Deltas use the scale captured at press so a refit mid-drag can't amplify the gesture.
                        let originFit = EasingFit(size: size, curve: origin)
                        let dx = Double(g.translation.width) / originFit.unit
                        let dy = -Double(g.translation.height) / originFit.unit
                        var next = origin
                        if index == 0 {
                            next.x1 = (min(max(origin.x1 + dx, 0), 1) * 100).rounded() / 100
                            next.y1 = (min(max(origin.y1 + dy, -1), 2) * 100).rounded() / 100
                        } else {
                            next.x2 = (min(max(origin.x2 + dx, 0), 1) * 100).rounded() / 100
                            next.y2 = (min(max(origin.y2 + dy, -1), 2) * 100).rounded() / 100
                        }
                        curve = next
                    }
                    .onEnded { _ in dragging = nil; dragOrigin = nil }
            )
            .onExitCommand { if let origin = dragOrigin { curve = origin }; dragging = nil; dragOrigin = nil }
        }
        .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            let d = press.modifiers.contains(.shift) ? 0.1 : 0.01
            let handle = hoverHandle ?? 0
            var next = curve
            switch press.key {
            case .leftArrow: if handle == 0 { next.x1 -= d } else { next.x2 -= d }
            case .rightArrow: if handle == 0 { next.x1 += d } else { next.x2 += d }
            case .upArrow: if handle == 0 { next.y1 += d } else { next.y2 += d }
            case .downArrow: if handle == 0 { next.y1 -= d } else { next.y2 -= d }
            default: return .ignored
            }
            next.x1 = min(max(next.x1, 0), 1); next.x2 = min(max(next.x2, 0), 1)
            next.y1 = min(max(next.y1, -1), 2); next.y2 = min(max(next.y2, -1), 2)
            curve = next
            return .handled
        }
    }
}

/// Keeps both axes on the same scale so the reference line is always 45°, and
/// zooms out automatically as Y overshoots.
struct EasingFit {
    let size: CGSize
    let unit: Double
    private let padding: Double

    init(size: CGSize, curve: TunerBezier) {
        self.size = size
        padding = min(12, Double(size.width) / 4, Double(size.height) / 4)
        let radiusY = max(0.5, abs(curve.y1 - 0.5), abs(curve.y2 - 0.5))
        unit = max(min(Double(size.width) - padding * 2, (Double(size.height) / 2 - padding) / radiusY), 1)
    }

    func project(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + (x - 0.5) * unit, y: Double(size.height) / 2 - (y - 0.5) * unit)
    }
}
