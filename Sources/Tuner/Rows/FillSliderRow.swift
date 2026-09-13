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
    /// Shows this instead of the number (Speed shows degrees). Read-only.
    let valueText: ((Double) -> String)?
    /// The ring shows only for keyboard focus, never because the window opened.
    @State private var keyboardFocus = false
    /// Fixed value column, for the same reason.
    public static let valueWidth: CGFloat = 60

    @Environment(\.tunerTheme) private var theme
    @State private var hovering = false
    @State private var dragging = false
    @State private var dragStart: CGPoint?
    @State private var valueHovering = false
    @State private var valueArmed = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var rowFocused: Bool

    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double? = nil, decimals: Int? = nil, unit: String = "", help: String = "",
                reset: (() -> Void)? = nil, showsValue: Bool = true, height: CGFloat = TunerTheme.rowHeight,
                labelWidth: CGFloat = 96, valueText: ((Double) -> String)? = nil) {
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
        self.valueText = valueText
    }

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }

    private var isDiscrete: Bool { (range.upperBound - range.lowerBound) / step <= 10 }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(TunerTheme.body)
                .foregroundStyle(theme.inkLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
                .onTapGesture(count: 2) { reset?() }
            track
            if showsValue { valueView.frame(width: Self.valueWidth, alignment: .trailing) }
        }
        .frame(height: height)
        .focusable(!editing)
        .focused($rowFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .onHover { hovering = $0; if !$0 { valueHovering = false; valueArmed = false } }
        .tunerFocusRing(rowFocused && keyboardFocus && !editing, radius: TunerTheme.rowRadius)
        .onChange(of: rowFocused) { _, focused in if !focused { keyboardFocus = false } }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(TunerFormat.string(value, decimals: decimals, unit: unit))
    }

    private var knob: CGFloat { height >= TunerTheme.rowHeight ? 16 : 14 }
    private let trackHeight: CGFloat = 8

    /// The track: a Linen capsule with a one-point border, Silver ticks, an ink
    /// fill up to the knob, and the knob itself. It follows the pointer 1:1;
    /// nothing here is animated but colour.
    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(width - knob, 1)
            let knobX = fraction * travel
            let fillWidth = knobX + knob / 2
            let active = hovering || dragging
            let marks = isDiscrete ? max(Int(((range.upperBound - range.lowerBound) / step).rounded()) - 1, 0) : 9
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.linen)
                    .overlay(Capsule().strokeBorder(active ? theme.borderHover : theme.border, lineWidth: 1))
                    .frame(height: trackHeight)
                    .tunerAnimation(TunerTheme.ease, value: active)
                ForEach(0..<marks, id: \.self) { i in
                    Rectangle()
                        .fill(theme.border)
                        .frame(width: 1, height: trackHeight - 2)
                        .offset(x: knob / 2 + travel * CGFloat(i + 1) / CGFloat(marks + 1))
                }
                Capsule()
                    .fill(theme.ink)
                    .frame(width: max(fillWidth, knob / 2), height: trackHeight)
                Knob(size: knob, fill: active ? TunerTheme.pureBlack : theme.buttonDark)
                    .offset(x: knobX)
                    .tunerAnimation(TunerTheme.ease, value: active)
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity, alignment: .center)
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
        } else if let valueText {
            Text(valueText(value))
                .font(TunerTheme.value)
                .foregroundStyle(theme.ink)
                .monospacedDigit()
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
            }
            .onEnded { g in
                defer { dragging = false; dragStart = nil }
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
        keyboardFocus = true
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
