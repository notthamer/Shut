import SwiftUI
import Tuner

/// The whole popover: header, preview column, controls column, footer.
struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    /// In the main window the header leaves room for the traffic lights and
    /// drops the "open as a window" button.
    var hostedInWindow = false
    @Environment(\.tunerTheme) private var theme

    static let width: CGFloat = 640
    static let previewWidth: CGFloat = 290
    static let bodyHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(model: model, hostedInWindow: hostedInWindow)
            // The one place the spectrum appears: a thin line under the header.
            SpectrumLine(height: 2)
            HStack(spacing: 0) {
                PreviewColumn(model: model)
                    .padding(14)
                    .frame(width: Self.previewWidth, height: Self.bodyHeight)
                Rectangle().fill(theme.hairline).frame(width: 1)
                ControlsColumn(model: model)
                    .frame(width: Self.width - Self.previewWidth - 1, height: Self.bodyHeight)
            }
            .opacity(model.settings.isEnabled ? 1 : 0.45)
            .allowsHitTesting(model.settings.isEnabled)
            .tunerAnimation(TunerTheme.quick, value: model.settings.isEnabled)
            Rectangle().fill(theme.hairline).frame(height: 1)
            PopoverFooter(model: model)
        }
        .frame(width: Self.width)
        .tunerThemed()
    }
}

struct PopoverHeader: View {
    @ObservedObject var model: PopoverModel
    var hostedInWindow = false
    @Environment(\.tunerTheme) private var theme

    /// Green: following the lid. Orange: running, but substituting. Grey: paused
    /// or nothing to follow.
    private var statusColor: Color {
        guard model.settings.isEnabled else { return theme.textTertiary }
        if model.registry.isSubstituting { return TunerTheme.saffron }
        return model.sensor.capability == .unsupported ? theme.textTertiary : TunerTheme.spectrumBlue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Shut.").font(TunerTheme.displayFont).tracking(TunerTheme.displayTracking).foregroundStyle(theme.ink)
                .help(model.statusLine)
            Circle().fill(statusColor).frame(width: 6, height: 6)
                .tunerAnimation(TunerTheme.ease, value: statusColor)
                .help(model.statusLine)
            Spacer(minLength: 8)
            if !hostedInWindow {
                IconButton("macwindow", help: "Open Shut as a window you can move and minimize.", action: model.openWindow)
            }
            SmallPill(isOn: model.settings.isEnabled, size: .regular) { model.settings.isEnabled.toggle() }
                .help(model.settings.isEnabled ? "Stop animating the lid." : "Start animating the lid.")
        }
        .padding(.horizontal, 14)
        // Traffic lights sit in the first 64 pt of a window's header.
        .padding(.leading, hostedInWindow ? 58 : 0)
        .frame(height: 56)
    }
}

struct PopoverFooter: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var launchAtLogin = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Text("Open at login").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                SmallPill(isOn: launchAtLogin) { launchAtLogin.toggle(); model.setLaunchAtLogin(launchAtLogin) }
            }
            HStack(spacing: 8) {
                Text("In Dock").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                SmallPill(isOn: model.settings.showInDock) { model.settings.showInDock.toggle() }
                    .help("Keep Shut in the Dock. Off keeps it in the menu bar only.")
            }
            Spacer()
            QuietButton("Tune everything…", action: model.openTuner)
                .keyboardShortcut("t", modifiers: [.control, .option])
            QuietButton("Quit", action: model.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onAppear { launchAtLogin = model.launchAtLogin() }
    }
}

/// An Off/On pill: small for the footer, regular for the master switch.
struct SmallPill: View {
    enum Size { case small, regular }
    let isOn: Bool
    var size: Size = .small
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    var body: some View {
        let w: CGFloat = size == .small ? 26 : 36, h: CGFloat = size == .small ? 14 : 20
        Button(action: action) {
            // Soft Graphite when on, a bordered Linen trough when off, a Paper
            // White knob. The colour eases; the knob simply moves.
            Capsule().fill(isOn ? theme.buttonDark : theme.linen)
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : theme.border, lineWidth: 1))
                .frame(width: w, height: h)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(theme.card)
                        .overlay(Circle().strokeBorder(theme.border, lineWidth: isOn ? 0 : 1))
                        .frame(width: h - 4, height: h - 4)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .tunerAnimation(TunerTheme.ease, value: isOn)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A 24-pt symbol button with the same hover surface as QuietButton.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? theme.ink : theme.inkLabel)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hover ? theme.linen : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
        .help(help)
    }
}

struct QuietButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            // A text link: ink on hover, otherwise Carbon; no fill.
            Text(title)
                .font(TunerTheme.bodySmall)
                .foregroundStyle(hover ? theme.ink : theme.inkLabel)
                .padding(.horizontal, 6).padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
    }
}


/// The app's logo from the package bundle, with a symbol fallback.
struct LogoMark: View {
    let size: CGFloat
    @Environment(\.tunerTheme) private var theme
    var body: some View {
        if let logo = AppAssets.logo {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "laptopcomputer")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(theme.textRoot)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(theme.surfaceActive))
        }
    }
}
