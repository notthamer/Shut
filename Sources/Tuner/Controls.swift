import AppKit
import SwiftUI

// The control views. Each takes the parameter binding and its spec; the panel
// decides layout. Styling is intentionally restrained (system controls, small
// labels) so the panel feels like a native inspector.

private let labelWidth: CGFloat = 132

struct ControlRow<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)
            content
        }
    }
}

struct SliderControlView<P>: View {
    @Binding var values: P
    let spec: SliderSpec<P>

    var body: some View {
        ControlRow(spec.label) {
            Slider(value: Binding(get: { spec.get(values) }, set: { spec.set(&values, snap($0)) }),
                   in: spec.range)
                .controlSize(.small)
            Text(formatted)
                .font(.caption.monospacedDigit())
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(.primary)
                .onTapGesture(count: 2) { spec.set(&values, spec.get(values)) }
        }
    }

    private func snap(_ v: Double) -> Double {
        guard let step = spec.step, step > 0 else { return v }
        return (v / step).rounded() * step
    }

    private var formatted: String {
        let v = spec.get(values)
        let number = String(format: "%.\(spec.decimals)f", v)
        return spec.unit.isEmpty ? number : "\(number) \(spec.unit)"
    }
}

struct ToggleControlView<P>: View {
    @Binding var values: P
    let spec: ToggleSpec<P>

    var body: some View {
        ControlRow(spec.label) {
            Toggle("", isOn: Binding(get: { spec.get(values) }, set: { spec.set(&values, $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
        }
    }
}

struct ColorControlView<P>: View {
    @Binding var values: P
    let spec: ColorSpec<P>

    var body: some View {
        ControlRow(spec.label) {
            ColorPicker("", selection: Binding(
                get: { Color(spec.get(values)) },
                set: { spec.set(&values, TunerColor($0)) }
            ), supportsOpacity: true)
            .labelsHidden()
            Text(hex).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var hex: String {
        let c = spec.get(values)
        return String(format: "#%02X%02X%02X", Int(c.red * 255), Int(c.green * 255), Int(c.blue * 255))
    }
}

struct SegmentedControlView<P>: View {
    @Binding var values: P
    let spec: SegmentedSpec<P>

    var body: some View {
        ControlRow(spec.label) {
            Picker("", selection: Binding(get: { spec.getIndex(values) }, set: { spec.setIndex(&values, $0) })) {
                ForEach(Array(spec.options.enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

struct ActionButtonView<P>: View {
    @Binding var values: P
    let spec: ActionSpec<P>

    var body: some View {
        ControlRow("") {
            Button(spec.label) { spec.run(&values) }
                .controlSize(.small)
            Spacer()
        }
    }
}

// MARK: - Color bridging

extension Color {
    init(_ c: TunerColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

extension TunerColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                  blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }
}
