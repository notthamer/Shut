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
    /// Both pages have this height: the panel is one size whichever section is on show. (It
    /// briefly followed the Stay awake page's content; a window that changes size when you
    /// change tabs felt wrong.)
    static let bodyHeight: CGFloat = 560

    var body: some View {
        let bodyHeight = Self.bodyHeight
        VStack(spacing: 0) {
            PopoverHeader(model: model, hostedInWindow: hostedInWindow)
            // The one place the spectrum appears. With two sections it is the mark under the
            // chosen one (drawn by the tab) over a hairline; a Mac with no lid has one
            // section, and keeps the full line.
            if model.stayAwake.hasLid {
                Rectangle().fill(theme.hairline).frame(height: 1)
            } else {
                SpectrumLine(height: 2)
            }
            ZStack {
                switch model.page {
                case .styles:
                    HStack(spacing: 0) {
                        PreviewColumn(model: model)
                            .padding(16)
                            // Top-aligned: if it ever runs long, the bottom gives, never the preview.
                            .frame(width: Self.previewWidth, height: bodyHeight, alignment: .top)
                        Rectangle().fill(theme.hairline).frame(width: 1)
                        ControlsColumn(model: model)
                            .frame(width: Self.width - Self.previewWidth - 1, height: bodyHeight)
                    }
                    .opacity(model.settings.isEnabled ? 1 : 0.45)
                    .allowsHitTesting(model.settings.isEnabled)
                    .tunerAnimation(TunerTheme.quick, value: model.settings.isEnabled)
                    .transition(.blurFade)
                case .awake:
                    AwakePage(model: model).transition(.blurFade)
                }
            }
            .frame(width: Self.width, height: bodyHeight)
            .tunerAnimation(TunerTheme.ease, value: model.page)
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

    static let height: CGFloat = 56

    /// Green: following the lid. Orange: running, but substituting. Grey: paused
    /// or nothing to follow.
    private var statusColor: Color {
        guard model.settings.isEnabled else { return theme.textTertiary }
        if model.registry.isSubstituting { return TunerTheme.saffron }
        return model.sensor.capability == .unsupported ? theme.textTertiary : TunerTheme.spectrumBlue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MarkGlyph(size: 26, tint: theme.ink)
            Text("Shut.").font(TunerTheme.displayFont).tracking(TunerTheme.displayTracking).foregroundStyle(theme.ink)
                .help(model.statusLine)
            Circle().fill(statusColor).frame(width: 6, height: 6)
                .tunerAnimation(TunerTheme.ease, value: statusColor)
                .help(model.statusLine)
            // The dot's words are the Lid effects tab's second line.
            if model.stayAwake.hasLid {
                SectionTabs(model: model).padding(.leading, 10)
            }
            Spacer(minLength: 8)
            if !hostedInWindow {
                IconButton("macwindow", help: "Open Shut as a window you can move and minimize.", action: model.openWindow)
            }
            // One switch, in one place, and it belongs to the section on show. The section's
            // name is already in the header, selected; the switch says only its state.
            if model.page == .awake, model.stayAwake.hasLid {
                let on = model.stayAwake.settings.isOn && model.stayAwake.settings.hasConsented
                Text(on ? "On" : "Off").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                SmallPill(isOn: on, size: .regular) { model.toggleAwake() }
                    .help("Keep the Mac awake with the lid shut while something is working.")
                    .accessibilityLabel("Stay awake")
            } else {
                Text(model.settings.isEnabled ? "On" : "Off").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                SmallPill(isOn: model.settings.isEnabled, size: .regular) { model.settings.isEnabled.toggle() }
                    .help(model.settings.isEnabled ? "Stop animating the lid." : "Start animating the lid.")
                    .accessibilityLabel("Lid effects")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .tunerAnimation(TunerTheme.ease, value: model.statusIsOrdinary)
        // In the window the traffic lights own the top strip; the header sits under it.
        .padding(.top, hostedInWindow ? 26 : 0)
    }
}

struct PopoverFooter: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme
    @State private var launchAtLogin = false
    @State private var automaticUpdates: Bool? = nil

    /// App-wide settings are not part of whichever page is above them, so they stay out of
    /// sight behind the gear. They swap in place: the panel is a non-activating window, and
    /// a popover of its own would count as a click outside and close it.
    @State private var showingSettings = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if showingSettings {
                HStack(spacing: 8) {
                    Text("Open at login").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                    SmallPill(isOn: launchAtLogin) { launchAtLogin.toggle(); model.setLaunchAtLogin(launchAtLogin) }
                }
                HStack(spacing: 8) {
                    Text("In Dock").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                    SmallPill(isOn: model.settings.showInDock) { model.settings.showInDock.toggle() }
                        .help("Keep Shut in the Dock. Off keeps it in the menu bar only.")
                }
                if let on = automaticUpdates {
                    HStack(spacing: 8) {
                        Text("Auto-update").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        SmallPill(isOn: on) { automaticUpdates = !on; model.setAutomaticUpdates(!on) }
                            .help("Check for a new version about once a day. Off: only when you choose Check for Updates.")
                    }
                }
                Spacer()
                // TEMPORARY (remove before 0.3.0 ships): a way to look at the first run and
                // the update tour again while they are being reviewed.
                QuietButton("Welcome") { model.replayWelcome() }
                QuietButton("What’s new") { model.replayWhatsNew() }
                QuietButton("Done") { showingSettings = false }
            } else {
                IconButton("gearshape", help: "Open at login, Dock icon, updates.") { showingSettings = true }
                    .accessibilityLabel("App settings")
                Spacer()
                VersionMark()
                QuietButton("Quit", action: model.quit)
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: showingSettings)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onAppear { launchAtLogin = model.launchAtLogin(); automaticUpdates = model.automaticUpdates() }
    }
}

/// The version, where someone reporting a problem can find it and nobody else has to look:
/// small, mono, the faintest ink, beside Quit. A click copies the line a bug report needs
/// (app version and build, macOS, Mac model) and says so for a moment.
struct VersionMark: View {
    var version = InstanceVersion.current
    @State private var copied = false
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(version.report(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
        } label: {
            Text(copied ? "Copied" : version.label)
                .font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary.opacity(copied ? 1 : 0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .focusEffectDisabled()
        .tunerAnimation(TunerTheme.ease, value: copied)
        .help("\(version.report())\nClick to copy, for a bug report.")
        .accessibilityLabel("Shut version \(version.short), build \(version.build). Copies version details.")
    }
}

/// The app's name for the shared switch: small for the footer, regular elsewhere.
struct SmallPill: View {
    typealias Size = TunerSwitch.Size
    let isOn: Bool
    var size: Size = .small
    let action: () -> Void
    var body: some View { TunerSwitch(isOn: isOn, size: size, action: action) }
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
    /// Opens a list under its row: a real chevron and a little more ink than a plain link,
    /// so "Apps" reads as somewhere to go, and "Reset" as something to do.
    var disclosure = false
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    init(_ title: String, disclosure: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.disclosure = disclosure; self.action = action
    }

    var body: some View {
        Button(action: action) {
            // A text link: ink on hover, otherwise Carbon; no fill.
            HStack(spacing: 4) {
                Text(title).font(disclosure ? TunerTheme.body : TunerTheme.bodySmall)
                if disclosure {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(hover || disclosure ? theme.ink : theme.inkLabel)
            .opacity(disclosure && !hover ? 0.8 : 1)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
    }
}


/// The bare mark, no tile: the "S" glyph filled with the spectrum. Used in the
/// header and on the welcome stage.
struct MarkGlyph: View {
    let size: CGFloat
    /// Ink on paper; nil fills the glyph with the spectrum (the black stage).
    var tint: Color? = nil
    var body: some View {
        if let mark = AppAssets.markCropped {
            Group {
                if let tint {
                    tint
                } else {
                    LinearGradient(gradient: TunerTheme.spectrum, startPoint: .leading, endPoint: .trailing)
                }
            }
            .mask(Image(nsImage: mark).resizable().interpolation(.high).aspectRatio(contentMode: .fit))
            .frame(width: size, height: size)
        } else {
            LogoMark(size: size)
        }
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
