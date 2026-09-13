import AppKit
import SwiftUI

/// The signature control: the whole row is the track. Label left, monospaced
/// value right, the fill grows from the left, and a slim handle appears on hover.
///
/// - Drag anywhere on the row: absolute, value = pointer x / width.
/// - Click without dragging: snaps to the nearest 10 % if within 3.125 %, or to
///   the nearest step for discrete ranges (≤ 10 steps).
/// - Hover the value for 0.8 s → it underlines → click to type. Enter commits,
///   Escape cancels.
/// - Double-click the label to reset.
/// - Keyboard: arrows ±1 step, ⇧ ×10, Home/End. Scroll wheel ±1 step.
public struct FillSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int
    let unit: String
    let help: String
    let reset: (() -> Void)?
    /// False for sliders whose number means nothing to the user (Speed).
    let showsValue: Bool
    let height: CGFloat
    /// Fixed label column, so every track in a section is the same length.
    let labelWidth: CGFloat
    /// Fixed value column, for the same reason.
    static let valueWidth: CGFloat = 60

    @Environment(\.tunerTheme) private var theme
    @State private var hovering = false
    @State private var dragging = false
    @State private var dragStart: CGPoint?
    /// Points of track stretch while dragging past either end (rubber band).
    @State private var stretch: CGFloat = 0
    @State private var valueHovering = false
    @State private var valueArmed = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var rowFocused: Bool

    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double? = nil, decimals: Int? = nil, unit: String = "", help: String = "",
                reset: (() -> Void)? = nil, showsValue: Bool = true, height: CGFloat = TunerTheme.rowHeight,
                labelWidth: CGFloat = 96) {
        self.label = label
        _value = value
        self.range = range
        let span = range.upperBound - range.lowerBound
        let inferred: Double = span <= 1 ? 0.01 : span <= 10 ? 0.1 : span <= 100 ? 1 : 10
        self.step = step ?? inferred
        self.decimals = decimals ?? TunerFormat.decimals(step: step ?? inferred, range: range, fallback: 2)
        self.unit = unit
        self.help = help
        self.reset = reset
        self.showsValue = showsValue
        self.height = height
        self.labelWidth = labelWidth
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private var isDiscrete: Bool { (range.upperBound - range.lowerBound) / step <= 10 }

    public var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(TunerTheme.label)
                .foregroundStyle(theme.textLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
                .onTapGesture(count: 2) { reset?() }
            track
            if showsValue { valueView.frame(width: Self.valueWidth, alignment: .trailing) }
        }
        .padding(.leading, 14)
        .padding(.trailing, showsValue ? 12 : 8)
        .frame(height: height)
        // The housing: a raised pill of soft clay.
        .glassSurface(.raised, radius: height / 2)
        .focusable(!editing)
        .focused($rowFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onHover { hovering = $0; if !$0 { valueHovering = false; valueArmed = false } }
        .tunerFocusRing(rowFocused && !editing, radius: height / 2)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(TunerFormat.string(value, decimals: decimals, unit: unit))
    }

    /// Knob diameter and track height scale with the row so the Lid scrubber
    /// (28 pt) and the 36-pt rows share one look.
    private var knob: CGFloat { height - 12 }
    private var trackHeight: CGFloat { height - 16 }

    /// The well: a warm gradient revealed by the knob's travel, thin ticks,
    /// and the knob riding on top.
    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(width - knob, 1)
            let knobX = fraction * travel
            let fillWidth = knobX + knob / 2
            let marks = isDiscrete ? max(Int(((range.upperBound - range.lowerBound) / step).rounded()) - 1, 0) : 9
            ZStack(alignment: .leading) {
                Color.clear.glassSurface(.inset, radius: trackHeight / 2)

                // Fill and ticks, clipped to the well so the blur stays inside it.
                ZStack(alignment: .leading) {
                    // The gradient spans the whole track; the fill reveals it, so
                    // the colour at the knob reads the value: red low, yellow high.
                    // Softly blurred, like light through frosted glass.
                    Capsule()
                        .fill(LinearGradient(colors: TunerTheme.warm, startPoint: .leading, endPoint: .trailing))
                        .frame(width: width)
                        .blur(radius: 2.5)
                        .overlay(alignment: .top) {
                            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                                .frame(height: trackHeight * 0.5)
                        }
                        .mask(alignment: .leading) {
                            // The fill's leading edge is soft too.
                            HStack(spacing: 0) {
                                Rectangle().frame(width: max(fillWidth - 4, 0))
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                                Spacer(minLength: 0)
                            }
                        }
                        .tunerAnimation(TunerTheme.quick, value: dragging)

                    // Ticks: light inside the fill, faint ink outside it.
                    ForEach(0..<marks, id: \.self) { i in
                        let x = knob / 2 + travel * CGFloat(i + 1) / CGFloat(marks + 1)
                        Rectangle()
                            .fill(x < fillWidth ? Color.white.opacity(0.7) : TunerTheme.inkBase.opacity(0.12))
                            .frame(width: 1.5, height: trackHeight * 0.55)
                            .offset(x: x - 0.75)
                    }
                }
                .clipShape(Capsule())
                // A warm glow spills out of the well around the fill.
                .shadow(color: TunerTheme.warm[1].opacity(dragging ? 0.45 : 0.3), radius: 6)

                ChromeKnob(size: knob)
                    .scaleEffect(dragging ? 1.08 : (hovering ? 1.04 : 1))
                    .offset(x: knobX)
                    .tunerMotion(TunerTheme.liquid, value: dragging)
                    .tunerMotion(TunerTheme.quick, value: hovering)
                    .allowsHitTesting(false)
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            // The whole track stretches past its ends, like a rubber band.
            .scaleEffect(x: 1 + abs(stretch) / max(width, 1), y: 1, anchor: stretch > 0 ? .leading : .trailing)
            .tunerMotion(.spring(response: 0.35, dampingFraction: 0.85), value: stretch)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .background(ScrollWheelCatcher { delta in
                guard hovering, !editing else { return }
                nudge(by: delta > 0 ? -1 : 1)
            })
        }
        .frame(minWidth: 60)
    }

    @ViewBuilder
    private var valueView: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(TunerTheme.value)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: Self.valueWidth)
                .focused($fieldFocused)
                .onSubmit { commitDraft() }
                .onExitCommand { editing = false }
                .onChange(of: fieldFocused) { _, focused in if !focused { commitDraft() } }
        } else {
            Text(TunerFormat.string(value, decimals: decimals, unit: unit))
                .font(TunerTheme.value)
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.textLabel).frame(height: 1).opacity(valueArmed ? 1 : 0)
                }
                .onHover { inside in
                    valueHovering = inside
                    if inside {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if valueHovering { valueArmed = true } }
                    } else { valueArmed = false }
                }
                .onTapGesture { if valueArmed { beginEditing() } }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStart == nil { dragStart = g.startLocation }
                if !dragging, let start = dragStart, hypot(g.location.x - start.x, g.location.y - start.y) > 3 {
                    dragging = true
                }
                guard dragging, !editing else { return }
                setValue(fromX: g.location.x, width: width, snapping: false)
                // Past either end: dead zone of 32 pt, then up to 8 pt of stretch that
                // eases in with the square root of the overshoot.
                let over = g.location.x < 0 ? -g.location.x : (g.location.x > width ? g.location.x - width : 0)
                let sign: CGFloat = g.location.x < 0 ? -1 : 1
                let amount = max(over - 32, 0)
                stretch = amount > 0 ? sign * 8 * sqrt(min(amount / 200, 1)) : 0
            }
            .onEnded { g in
                defer { dragging = false; dragStart = nil; stretch = 0 }
                guard !editing else { return }
                if !dragging { setValue(fromX: g.location.x, width: width, snapping: true) }
            }
    }

    private func setValue(fromX x: CGFloat, width: CGFloat, snapping: Bool) {
        let travel = width - knob
        guard travel > 0 else { return }
        var f = Double(min(max((x - knob / 2) / travel, 0), 1))
        if snapping {
            if isDiscrete {
                // fall through to step rounding below
            } else {
                let nearest = (f * 10).rounded() / 10
                if abs(f - nearest) <= 0.03125 { f = nearest }
            }
        }
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        value = quantize(raw)
    }

    private func quantize(_ raw: Double) -> Double {
        let stepped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private func nudge(by steps: Double) {
        value = quantize(value + steps * step)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !editing else { return .ignored }
        let multiplier: Double = press.modifiers.contains(.shift) ? 10 : 1
        switch press.key {
        case .rightArrow, .upArrow: nudge(by: multiplier); return .handled
        case .leftArrow, .downArrow: nudge(by: -multiplier); return .handled
        case .home: value = range.lowerBound; return .handled
        case .end: value = range.upperBound; return .handled
        case .return: beginEditing(); return .handled
        default:
            if press.key == KeyEquivalent("\u{8}") || press.characters == "\u{7F}" { reset?(); return .handled }
            return .ignored
        }
    }

    private func beginEditing() {
        draft = String(format: "%.\(decimals)f", value)
        editing = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commitDraft() {
        guard editing else { return }
        editing = false
        let cleaned = draft.replacingOccurrences(of: unit, with: "").trimmingCharacters(in: .whitespaces)
        if let parsed = Double(cleaned.replacingOccurrences(of: ",", with: ".")) { value = quantize(parsed) }
    }
}
