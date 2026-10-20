import AppKit
import SwiftUI
import Tuner
import UniformTypeIdentifiers

/// The Lid sound page reads like the Stay awake page, top to bottom:
///
///     )))  Closing the lid plays Rain.             PICK   ( Random ) ( In order )
///          It starts as the lid comes down …       VOLUME ●━━━━━━━━━━━━━━━  70 %
///          [ ▶ Try it ]
///     ─────────────────────────────────────────────────────────────────────────
///     01 SOUNDS                                  02 SETTINGS ›
///     ▶ Rain      2.4 s          ◉   ×           Silent on open · stays quiet when muted
///     Add a sound…
///
/// The answer spans the band: what closing will do, and the sound it names. The one choice
/// (which way) and the volume are on its right. Under the hairline, the list with its
/// switches on the left and the folded settings on the right, each scrolling by itself.
struct LidSoundPage: View {
    @ObservedObject var model: PopoverModel
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            LidSoundBand(model: model)
            Rectangle().fill(theme.hairline).frame(height: 1)
            LidSoundControls(model: model)
        }
        .clipped()
    }
}

// MARK: - The answer

private struct LidSoundBand: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var sound: LidSoundController
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel) {
        self.model = model
        sound = model.lidSound
    }

    private var settings: LidSoundSettings { sound.settings }
    private var isOn: Bool { settings.isOn }

    var body: some View {
        let situation = sound.situation()
        let copy = LidSoundText.copy(situation)
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // On: it breathes, leans toward the pointer, and a click plays the sound.
                    LidSoundGlyph(playing: sound.playing != nil, height: 30, tint: isOn ? theme.ink : theme.inkLabel,
                                  breathes: isOn, follows: isOn && !situation.candidates.isEmpty,
                                  onTap: isOn && !situation.candidates.isEmpty ? { model.tryTheSound() } : nil)
                        .padding(.bottom, 2)
                    Text(copy.headline)
                        .font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(copy.detail)
                        .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    action(situation).padding(.top, 6)
                }
                .padding(.horizontal, 20).padding(.vertical, 22)
                .frame(width: AwakePage.statusWidth, alignment: .topLeading)
            }
            .frame(width: AwakePage.statusWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(theme.hairline).frame(width: 1)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick").font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    ModeSwitch(options: ["Random", "In order"], selection: settings.mode == .random ? 0 : 1) { index in
                        settings.mode = index == 0 ? .random : .inOrder
                    }
                    .help("Random never plays the same sound twice running. In order goes down the list.")
                }
                LidSoundVolume(sound: sound)
                LidSoundStart(sound: sound)
                if !isOn {
                    // Off: the controls are readable (they are the explanation) and the line
                    // says what comes first, so a dim pair of buttons is not a dead end.
                    Text("Switch Lid sound on, up in the header, then pick a sound.")
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!isOn)
            .opacity(isOn ? 1 : 0.5)
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: AwakePage.bandHeight)
        .clipped()
        .tunerAnimation(TunerTheme.ease, value: isOn)
    }

    /// One action under the answer: turn it on; hear it; or, muted, go and change that.
    @ViewBuilder
    private func action(_ situation: LidSoundText.Situation) -> some View {
        if !isOn {
            PrimaryButton("Turn on") { settings.isOn = true }
        } else if LidSoundText.silencedByMute(situation), situation.canUnmute {
            SecondaryButton("Change", prominent: true) { model.showingSoundSettings = true }
                .help("Open Settings, where Shut can be told to unmute for the sound.")
        } else if !situation.candidates.isEmpty {
            SecondaryButton(sound.playing == nil ? "Try it" : "Playing…", prominent: true) { model.tryTheSound() } icon: {
                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
            }
            .help("Hear the sound the next close would play, while the preview plays the close.")
        }
    }
}

/// Volume: its own, as a share of the Mac's. Letting go plays the sound at that level, so
/// nobody has to close the lid to find out.
private struct LidSoundVolume: View {
    @ObservedObject var sound: LidSoundController
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let settings = sound.settings
        VStack(alignment: .leading, spacing: 2) {
            StackedSlider("Volume", valueText: "\(Int((settings.volume * 100).rounded())) %",
                          value: Binding(get: { settings.volume * 100 }, set: { settings.volume = ($0 / 100).rounded(toPlaces: 2) }),
                          in: 0...100, step: 5, onEditingEnded: { sound.playClosePreview() })
            HStack {
                Text("Quiet"); Spacer(); Text("Loud")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
        }
        .help("Of your Mac's volume, which Shut never changes. Let go to hear it.")
    }
}

/// Where the sound starts, in degrees above shut: with the screen effect (Speed, on Lid
/// effects, so the two begin together) or at an angle of its own. The dial always shows the
/// number, so "how early" is never a guess.
private struct LidSoundStart: View {
    @ObservedObject var sound: LidSoundController
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let settings = sound.settings
        let synced = settings.startsWithEffect
        VStack(alignment: .leading, spacing: 2) {
            StackedSlider("Starts at", valueText: "\(Int(sound.startDegrees.rounded()))°",
                          value: Binding(get: { sound.startDegrees }, set: { settings.startDegrees = $0 }),
                          in: AppSettings.bandRange, step: 5)
                .disabled(synced).opacity(synced ? 0.5 : 1)
                .help(synced ? "With the screen effect: change Speed on Lid effects to move both." : "How far above shut the sound starts. Higher starts it sooner and plays more of it.")
            HStack {
                Text("Late"); Spacer(); Text("Early")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
            TriggerRow("Same as the screen effect",
                       about: synced ? LidSoundText.startsWithEffectAbout(Int(sound.effectStartDegrees.rounded())) : LidSoundText.ownStartAbout,
                       live: nil, detail: nil,
                       isOn: Binding(get: { settings.startsWithEffect }, set: { settings.startsWithEffect = $0 }), expanded: nil,
                       help: "On: the sound starts where Speed, on Lid effects, starts the screen, so the two begin together. Off: the dial above sets its own angle.")
                .padding(.top, 2)
        }
        .tunerAnimation(TunerTheme.ease, value: synced)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - The list and the settings

private struct LidSoundControls: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var sound: LidSoundController
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel) {
        self.model = model
        sound = model.lidSound
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(showsIndicators: true) {
                sounds.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: AwakePage.statusWidth)
            Rectangle().fill(theme.hairline).frame(width: 1)
            ScrollView(showsIndicators: true) {
                options.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1)
        }
        .frame(maxHeight: .infinity)
        .tunerAnimation(TunerTheme.ease, value: model.showingSoundSettings)
        .tunerAnimation(TunerTheme.ease, value: model.importNote)
    }

    private var sounds: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Sounds", number: "01").padding(.bottom, 2)
            LidSoundList(model: model)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                QuietButton("Add a sound…", disclosure: true, action: model.addSounds)
                    .help("Choose audio files. Each is copied into Shut, so the original can move or go.")
                    .padding(.leading, -6)
            }
            Text(model.importNote ?? LidSoundText.addHint)
                .font(TunerTheme.bodySmall).foregroundStyle(model.importNote == nil ? theme.inkLabel : theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, model.importNote == nil ? 0 : 10).padding(.vertical, model.importNote == nil ? 0 : 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.importNote == nil ? .clear : theme.washSaffron))
                .accessibilityLabel(model.importNote ?? LidSoundText.addHint)
        }
    }

    private var options: some View {
        let settings = sound.settings
        return VStack(alignment: .leading, spacing: TunerTheme.sectionGap) {
            FoldedSection("Settings", number: "02",
                          summary: LidSoundText.settingsSummary(onOpen: settings.onOpen, whenMuted: settings.whenMuted),
                          isOpen: Binding(get: { model.showingSoundSettings }, set: { model.showingSoundSettings = $0 }),
                          help: "A sound on open, what to do when the Mac is muted, and the starter sounds.")
            if model.showingSoundSettings { LidSoundSettingsRows(model: model).transition(.blurFade) }
        }
    }
}

/// The sounds, each with a switch, in a well that never outgrows the page: four and a half
/// rows (the half says "there is more"), scrolling inside itself beyond that. A row at work
/// says so in ink; a file that went missing says so and cannot be switched on.
private struct LidSoundList: View {
    @ObservedObject var model: PopoverModel
    @State private var dropTargeted = false
    @Environment(\.tunerTheme) private var theme

    static let rowHeight: CGFloat = 34
    static let visibleRows: CGFloat = 4.5

    var body: some View {
        let sound = model.lidSound
        let items = sound.settings.shown
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("No sounds yet. Add one, or restore the starters under Settings.")
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let rows = VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                    LidSoundRow(model: model, item: item)
                }
            }
            if CGFloat(items.count) > Self.visibleRows {
                ScrollView(showsIndicators: true) { rows }.frame(height: Self.rowHeight * Self.visibleRows)
            } else {
                rows
            }
        }
        .surface(.well, radius: TunerTheme.wellRadius)
        .overlay(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous)
            .strokeBorder(theme.ink, lineWidth: 1).opacity(dropTargeted ? 1 : 0))
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                    else if let url = item as? URL { urls.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { model.importSounds(urls) }
            return true
        }
        .tunerAnimation(TunerTheme.ease, value: dropTargeted)
        .help("The sounds the lid may play. Drop audio files here to add them.")
    }
}

private struct LidSoundRow: View {
    @ObservedObject var model: PopoverModel
    let item: LidSoundItem
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let sound = model.lidSound
        let state = sound.library.state(of: item)
        let live = sound.playing == item.displayName
        HStack(spacing: 8) {
            IconButton("play.fill", help: "Hear \(item.displayName).") { sound.preview(item) }
                .disabled(state != .ok)
                .accessibilityLabel("Play \(item.displayName)")
            Text(item.displayName).font(live ? TunerTheme.bodyMedium : TunerTheme.body)
                .foregroundStyle(state == .ok ? theme.ink : theme.inkLabel).lineLimit(1).truncationMode(.middle)
            if state != .ok {
                Text(state == .missing ? "Missing" : "Can't be played")
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1)
                    .help(state == .missing ? "The file was moved or deleted. Remove it, or add it again." : "Shut could not open this file.")
            } else if live {
                Circle().fill(TunerTheme.limeWash).overlay(Circle().strokeBorder(theme.ink, lineWidth: 1)).frame(width: 7, height: 7)
            }
            Spacer(minLength: 6)
            if let duration = item.duration {
                Text(LidSoundText.durationText(duration)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
            }
            SmallPill(isOn: item.enabled && state == .ok) {
                var changed = item; changed.enabled.toggle()
                sound.settings.update(changed)
            }
            .disabled(state != .ok)
            .accessibilityLabel("\(item.displayName) may play")
            IconButton("xmark", help: item.isStarter ? "Remove \(item.displayName). The starter sounds can be restored under Settings."
                                                      : "Remove \(item.displayName) and delete its copy from Shut.") {
                model.removeSound(item)
            }
            .accessibilityLabel("Remove \(item.displayName)")
        }
        .padding(.leading, 6).padding(.trailing, 8).frame(height: LidSoundList.rowHeight - 1)
        .accessibilityElement(children: .contain)
    }
}

/// The folded part of the page, in plain words, every row with a line under its name.
private struct LidSoundSettingsRows: View {
    @ObservedObject var model: PopoverModel
    @State private var showPick = false
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let sound = model.lidSound
        let settings = sound.settings
        let candidates = sound.library.candidates(settings.items)
        let pickName: String = {
            if case .item(let id) = settings.onOpenPick, let item = settings.items.first(where: { $0.id == id }) { return item.displayName }
            return "Same pick"
        }()
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow("On open").padding(.bottom, 12)
            TriggerRow("Also on open", about: LidSoundText.onOpenAbout, live: nil, detail: pickName,
                       isOn: Binding(get: { settings.onOpen }, set: { settings.onOpen = $0 }), expanded: $showPick,
                       help: "Play a sound as the desktop pours back in after you unlock: the close's pick again, or one in particular.")
            if showPick {
                VStack(spacing: 0) {
                    pickRow("Same pick", chosen: settings.onOpenPick == .samePick) { settings.onOpenPick = .samePick }
                    ForEach(candidates) { item in
                        Rectangle().fill(theme.hairline).frame(height: 1)
                        pickRow(item.displayName, chosen: settings.onOpenPick == .item(item.id)) { settings.onOpenPick = .item(item.id) }
                    }
                }
                .surface(.well, radius: TunerTheme.wellRadius)
                .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
                .transition(.blurFade).padding(.bottom, 6)
            }

            Eyebrow("When the Mac is muted").padding(.top, 28).padding(.bottom, 12)
            Explained(sound.canUnmute ? LidSoundText.unmuteAbout : "This output has no mute switch Shut can lift, so it stays quiet either way.") {
                SegmentedRow("Muted", options: ["Stay quiet", "Unmute for it"],
                             selection: Binding(get: { settings.whenMuted == .unmute ? 1 : 0 }, set: { settings.whenMuted = $0 == 1 ? .unmute : .stayQuiet }),
                             help: "What to do when your Mac is muted as the lid closes.")
            }

            Eyebrow("Extras").padding(.top, 8).padding(.bottom, 12)
            Text(LidSoundText.endsWithTheLid)
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            if settings.items.contains(where: { $0.isStarter && $0.hidden }) {
                QuietButton("Restore the starter sounds", action: model.restoreStarterSounds).padding(.leading, -6)
                    .help("Put Click, Breath and Hum back in the list.")
            }
        }
    }

    private func pickRow(_ name: String, chosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink)
                    .frame(width: 14).opacity(chosen ? 1 : 0)
                Text(name).font(chosen ? TunerTheme.bodyMedium : TunerTheme.body).foregroundStyle(theme.ink)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
