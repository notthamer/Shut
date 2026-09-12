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

    @Environment(\.tunerTheme) private var theme
    @State private var hovering = false
    @State private var dragging = false
    @State private var dragStart: CGPoint?
    /// Points of track stretch while dragging past either end (rubber band).
    @State private var stretch: CGFloat = 0
    @State private var labelWidth: CGFloat = 0
    @State private var valueWidth: CGFloat = 0
    @State private var valueHovering = false
    @State private var valueArmed = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var rowFocused: Bool

    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double? = nil, decimals: Int? = nil, unit: String = "", help: String = "",
                reset: (() -> Void)? = nil, showsValue: Bool = true, height: CGFloat = TunerTheme.rowHeight) {
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
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private var isDiscrete: Bool { (range.upperBound - range.lowerBound) / step <= 10 }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let handleX = max(min(fraction * width - 1.5, width - 4), 1)
            // The handle ducks when it would sit on top of the label or the value.
            let collides = handleX < labelWidth + 18 || handleX > width - valueWidth - 18
            ZStack(alignment: .leading) {
                // Track and fill stretch together past the ends, like a rubber band.
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                        .fill(hovering || dragging ? theme.surfaceHover : theme.surface)
                    RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                        .fill(dragging ? theme.borderHover : theme.surfaceActive)
                        .frame(width: max(fraction * width, 0))
                        .tunerAnimation(TunerTheme.quick, value: dragging)
                }
                .scaleEffect(x: 1 + abs(stretch) / max(width, 1), y: 1, anchor: stretch > 0 ? .leading : .trailing)
                // The one bounce on the panel: a rubber band carries the drag's momentum.
                .tunerMotion(.spring(response: 0.35, dampingFraction: 0.85), value: stretch)

                // Hash marks fade in while active.
                let marks = isDiscrete ? max(Int(((range.upperBound - range.lowerBound) / step).rounded()) - 1, 0) : 9
                ForEach(0..<marks, id: \.self) { i in
                    Rectangle()
                        .fill(theme.borderHover)
                        .frame(width: 1, height: 8)
                        .offset(x: width * CGFloat(i + 1) / CGFloat(marks + 1))
                        .opacity(hovering || dragging ? 1 : 0)
                }
                .tunerAnimation(TunerTheme.easeOut(0.16), value: hovering || dragging)

                // Handle
                Capsule()
                    .fill(theme.textPrimary)
                    .frame(width: 3, height: min(20, height - 12))
                    .scaleEffect(x: hovering || dragging ? 1 : 0.25, y: collides ? 0.75 : 1)
                    .offset(x: handleX)
                    .opacity(collides ? handleOpacity * 0.2 : handleOpacity)
                    .tunerMotion(TunerTheme.quick, value: hovering)
                    .tunerMotion(TunerTheme.quick, value: collides)

                HStack(spacing: 8) {
                    Text(label)
                        .font(TunerTheme.label)
                        .foregroundStyle(theme.textLabel)
                        .lineLimit(1)
                        .background(GeometryReader { g in Color.clear.onAppear { labelWidth = g.size.width }.onChange(of: g.size.width) { _, w in labelWidth = w } })
                        .onTapGesture(count: 2) { reset?() }
                    Spacer(minLength: 4)
                    if showsValue {
                        valueView
                            .background(GeometryReader { g in Color.clear.onAppear { valueWidth = g.size.width }.onChange(of: g.size.width) { _, w in valueWidth = w } })
                    }
                }
                .padding(.horizontal, 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous))
            .gesture(dragGesture(width: width))
            .background(ScrollWheelCatcher { delta in
                guard hovering, !editing else { return }
                nudge(by: delta > 0 ? -1 : 1)
            })
        }
        .frame(height: height)
        .focusable(!editing)
        .focused($rowFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onHover { hovering = $0; if !$0 { valueHovering = false; valueArmed = false } }
        .tunerFocusRing(rowFocused && !editing)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(TunerFormat.string(value, decimals: decimals, unit: unit))
    }

    private var handleOpacity: Double {
        if dragging { return 0.9 }
        if hovering { return 0.5 }
        return 0
    }

    @ViewBuilder
    private var valueView: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(TunerTheme.value)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
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
        guard width > 0 else { return }
        var f = Double(min(max(x / width, 0), 1))
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
