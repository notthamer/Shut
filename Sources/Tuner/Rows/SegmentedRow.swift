import SwiftUI

/// Label left, a pill-style segmented control right. Toggles render as Off / On
/// so every row in the panel has the same shape.
public struct SegmentedRow: View {
    let label: String
    let options: [String]
    @Binding var selection: Int
    let help: String

    @Environment(\.tunerTheme) private var theme
    @Namespace private var pill

    public init(_ label: String, options: [String], selection: Binding<Int>, help: String = "") {
        self.label = label
        self.options = options
        _selection = selection
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(TunerTheme.label)
                .foregroundStyle(theme.textLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(TunerTheme.label)
                        .foregroundStyle(index == selection ? theme.textPrimary : theme.textLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if index == selection {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(theme.surfaceActive)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selection = index }
                }
            }
            .padding(2)
            .tunerAnimation(TunerTheme.quick, value: selection)
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: TunerTheme.rowHeight)
        .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(theme.surface))
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            switch press.key {
            case .leftArrow, .upArrow: selection = (selection - 1 + options.count) % options.count; return .handled
            case .rightArrow, .downArrow: selection = (selection + 1) % options.count; return .handled
            default: return .ignored
            }
        }
        .help(help)
    }
}

/// A Bool as Off / On segments.
public struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    let help: String

    public init(_ label: String, isOn: Binding<Bool>, help: String = "") {
        self.label = label
        _isOn = isOn
        self.help = help
    }

    public var body: some View {
        SegmentedRow(label, options: ["Off", "On"],
                     selection: Binding(get: { isOn ? 1 : 0 }, set: { isOn = $0 == 1 }), help: help)
    }
}
