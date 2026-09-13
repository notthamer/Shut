import SwiftUI

/// Label, hex readout, and a 20-pt swatch that opens the system colour panel.
public struct ColorRow: View {
    let label: String
    @Binding var color: TunerColor
    let help: String

    @Environment(\.tunerTheme) private var theme
    @State private var swatchHover = false

    public init(_ label: String, color: Binding<TunerColor>, help: String = "") {
        self.label = label
        _color = color
        self.help = help
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(label).font(TunerTheme.label).foregroundStyle(theme.textLabel).lineLimit(1)
            Spacer(minLength: 4)
            Text(color.hex).font(TunerTheme.value).foregroundStyle(theme.textPrimary)
                .padding(.trailing, 6)
            ColorPicker("", selection: Binding(get: { Color(color) }, set: { color = TunerColor($0) }), supportsOpacity: true)
                .labelsHidden()
                .frame(width: 30, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.glassEdgeDark, lineWidth: 1))
                .shadow(color: theme.shadowSoft, radius: 3, y: 1)
                .scaleEffect(swatchHover ? 1.08 : 1)
                .onHover { swatchHover = $0 }
                .tunerMotion(TunerTheme.quick, value: swatchHover)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: TunerTheme.rowHeight)
        .glassSurface(.inset)
        .help(help)
    }
}
