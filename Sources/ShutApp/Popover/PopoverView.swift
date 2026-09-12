import SwiftUI
import Tuner

/// The whole popover: header, preview column, controls column, footer.
struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    static let width: CGFloat = 600
    static let previewWidth: CGFloat = 290
    static let bodyHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(model: model)
            Rectangle().fill(theme.surfaceSubtle).frame(height: 1)
            HStack(spacing: 0) {
                PreviewColumn(model: model)
                    .padding(14)
                    .frame(width: Self.previewWidth, height: Self.bodyHeight)
                Rectangle().fill(theme.surfaceSubtle).frame(width: 1)
                ControlsColumn(model: model)
                    .frame(width: Self.width - Self.previewWidth - 1, height: Self.bodyHeight)
            }
            .opacity(model.settings.isEnabled ? 1 : 0.45)
            .allowsHitTesting(model.settings.isEnabled)
            .tunerAnimation(TunerTheme.quick, value: model.settings.isEnabled)
            Rectangle().fill(theme.surfaceSubtle).frame(height: 1)
            PopoverFooter(model: model)
        }
        .frame(width: Self.width)
        .background(theme.panel)
        .tunerThemed()
    }
}

struct PopoverHeader: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Shut.").font(TunerTheme.rootTitle).foregroundStyle(theme.textRoot)
                Text(model.statusLine).font(.system(size: 10.5)).foregroundStyle(theme.textLabel)
            }
            .help(model.sensor.capability.explanation)
            Spacer(minLength: 8)
            SmallPill(isOn: model.settings.isEnabled, size: .regular) { model.settings.isEnabled.toggle() }
                .help(model.settings.isEnabled ? "Stop animating the lid." : "Start animating the lid.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct PopoverFooter: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var launchAtLogin = false

    var body: some View {
        HStack(spacing: 10) {
            Text("Open at login")
                .font(TunerTheme.caption).foregroundStyle(theme.textLabel)
            SmallPill(isOn: launchAtLogin) { launchAtLogin.toggle(); model.setLaunchAtLogin(launchAtLogin) }
            Spacer()
            QuietButton("Tune everything…", action: model.openTuner)
            QuietButton("Quit", action: model.quit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
        Capsule().fill(isOn ? theme.textRoot : theme.surfaceActive)
            .frame(width: w, height: h)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? theme.panel : theme.textLabel).frame(width: h - 4, height: h - 4).padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .tunerAnimation(TunerTheme.quick, value: isOn)
    }
}

struct QuietButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Text(title)
            .font(TunerTheme.caption)
            .foregroundStyle(hover ? theme.textRoot : theme.textLabel)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? theme.surfaceHover : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
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
