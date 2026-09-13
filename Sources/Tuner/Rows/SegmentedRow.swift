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
    /// The pill stretches a little along its travel and settles: liquid.
    @State private var stretch: CGFloat = 1

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
                    Button { selection = index } label: {
                        Text(name)
                            .font(TunerTheme.label)
                            .foregroundStyle(index == selection ? theme.textPrimary : theme.textLabel)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background {
                                if index == selection {
                                    Capsule()
                                        .fill(theme.tintAmber)
                                        .overlay(Capsule().strokeBorder(theme.glassEdgeDark, lineWidth: 1))
                                        .overlay(alignment: .top) {
                                            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom))
                                                .frame(height: 8)
                                                .mask(Capsule().strokeBorder(lineWidth: 1))
                                        }
                                        .shadow(color: theme.shadowSoft, radius: 4, y: 2)
                                        .scaleEffect(x: stretch, y: 1)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                }
            }
            .padding(2)
            .tunerMotion(TunerTheme.liquid, value: selection)
            .tunerMotion(TunerTheme.liquid, value: stretch)
            .onChange(of: selection) { _, _ in
                stretch = 1.12
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { stretch = 1 }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: TunerTheme.rowHeight)
        .glassSurface(.raised, radius: TunerTheme.rowHeight / 2)
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
