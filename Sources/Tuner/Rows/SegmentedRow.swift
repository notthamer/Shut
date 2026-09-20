import SwiftUI

/// Label left, a pill-style segmented control right. Toggles render as Off / On
/// so every row in the panel has the same shape.
public struct SegmentedRow: View {
    let label: String
    let options: [String]
    @Binding var selection: Int
    let help: String

    @Environment(\.tunerTheme) private var theme

    public init(_ label: String, options: [String], selection: Binding<Int>, help: String = "") {
        self.label = label
        self.options = options
        _selection = selection
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(TunerTheme.body)
                .foregroundStyle(theme.inkLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                    Button { selection = index } label: {
                        Text(name)
                            .font(TunerTheme.body)
                            .foregroundStyle(index == selection ? theme.ink : theme.inkLabel)
                            // Short words that must never become "…": the label gives way, not these.
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(theme.card)
                                    .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                                    .opacity(index == selection ? 1 : 0)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .tunerAnimation(TunerTheme.ease, value: selection)
                }
            }
            .padding(2)
            .surface(.pill)
        }
        .frame(height: TunerTheme.rowHeight)
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

/// A Bool: its label and the switch. (It was Off / On segments; see `TunerSwitch`.)
public struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    let help: String
    @Environment(\.tunerTheme) private var theme

    public init(_ label: String, isOn: Binding<Bool>, help: String = "") {
        self.label = label
        _isOn = isOn
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(label).font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineLimit(1)
            Spacer(minLength: 4)
            TunerSwitch(isOn: isOn, size: .regular) { isOn.toggle() }
        }
        .frame(height: TunerTheme.rowHeight)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
