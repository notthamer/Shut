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
        let situation = model.lidSoundSituation()
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
                    if let slow = model.sleep.slow {
                        SlowSleepCard(slow: slow) { model.sleep.dismissSlow() }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 22)
                .frame(width: AwakePage.statusWidth, alignment: .topLeading)
            }
            .frame(width: AwakePage.statusWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(theme.hairline).frame(width: 1)

            // The right cell scrolls by itself, like the left: with the start dial and the
            // off-state line it can outgrow the band's one height.
            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
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
            }
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1)
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
                .help("How loud the lid is. Let go to hear it.")
            HStack {
                Text("Quiet"); Spacer(); Text("Loud")
            }
            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
            Text(LidSoundText.volumeAbout(sound.canSetVolume ? settings.volumeMode : .shareOfMac, macVolume: sound.macVolume))
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
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
                          summary: LidSoundText.settingsSummary(onOpen: settings.onOpen, whenMuted: settings.whenMuted, volumeMode: settings.volumeMode),
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
    /// The long file whose clip is being chosen, if one is.
    @State private var clipping: UUID?
    /// A row being carried to a new place: hold it a moment, then drag; the others step
    /// aside; let go and the order is kept. "In order" plays down this list.
    @State private var carry: Carry?
    @Environment(\.tunerTheme) private var theme

    struct Carry: Equatable {
        let id: UUID
        let from: Int
        var offset: CGFloat = 0
    }

    static let rowHeight: CGFloat = 34
    static let visibleRows: CGFloat = 4.5

    /// Where the carried row would land, from how far it has been dragged.
    private func target(_ carry: Carry, count: Int) -> Int {
        max(0, min(count - 1, carry.from + Int((carry.offset / Self.rowHeight).rounded())))
    }

    /// A row never leaves the well: the drag is clamped to the list, whatever the pointer does.
    private func clamped(_ offset: CGFloat, from: Int, count: Int) -> CGFloat {
        max(-CGFloat(from) * Self.rowHeight, min(CGFloat(count - 1 - from) * Self.rowHeight, offset))
    }

    /// How far each row steps aside for the one being carried. The carried row follows the
    /// pointer; the others jump a row at a time, as the eyes jump between frames.
    private func shift(of index: Int, count: Int) -> CGFloat {
        guard let carry, carry.from < count else { return 0 }
        if index == carry.from { return clamped(carry.offset, from: carry.from, count: count) }
        let target = target(carry, count: count)
        if carry.from < target, index > carry.from, index <= target { return -Self.rowHeight }
        if carry.from > target, index < carry.from, index >= target { return Self.rowHeight }
        return 0
    }

    private func drop(count: Int) {
        guard let carry else { return }
        let to = target(carry, count: count)
        self.carry = nil
        guard to != carry.from else { return }
        model.moveSound(from: carry.from, to: to)
    }

    var body: some View {
        let sound = model.lidSound
        let items = sound.settings.shown
        let clipping = self.clipping ?? model.cuttingSoundForTest
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("No sounds yet. Add one, or restore the starters under Settings.")
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let rows = VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                    LidSoundRow(model: model, item: item, clipping: Binding(get: { clipping == item.id }, set: { self.clipping = $0 ? item.id : nil }),
                                carried: carry?.id == item.id, canMove: items.count > 1 && clipping == nil,
                                hold: { carry = Carry(id: item.id, from: index) },
                                drag: { offset in if carry?.id == item.id { carry?.offset = clamped(offset, from: index, count: items.count) } },
                                release: { if carry?.id == item.id { drop(count: items.count) } },
                                move: { up in model.moveSound(from: index, to: max(0, min(items.count - 1, index + (up ? -1 : 1)))) })
                        .offset(y: shift(of: index, count: items.count))
                        .zIndex(carry?.id == item.id ? 1 : 0)
                    if clipping == item.id { LidSoundCut(model: model, item: item, done: { self.clipping = nil; model.cuttingSoundForTest = nil }).transition(.blurFade) }
                }
            }
            if CGFloat(items.count) > Self.visibleRows || clipping != nil {
                ScrollView(showsIndicators: true) { rows }.frame(height: clipping == nil ? Self.rowHeight * Self.visibleRows : 236)
            } else {
                rows
            }
        }
        // A carried row whose list changed under it (removed, re-sorted) is let go of, so
        // nothing is ever left floating out of view.
        .onChange(of: items.map(\.id)) { _, ids in if let carry, !ids.contains(carry.id) { self.carry = nil } }

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
        .tunerAnimation(TunerTheme.ease, value: clipping)
        .help("The sounds the lid may play. Drop audio files here to add them.")
    }
}

private struct LidSoundRow: View {
    @ObservedObject var model: PopoverModel
    let item: LidSoundItem
    @Binding var clipping: Bool
    /// Being carried to a new place: lifted on Linen, the pointer's to move.
    var carried = false
    var canMove = true
    var hold: () -> Void = {}
    var drag: (CGFloat) -> Void = { _ in }
    var release: () -> Void = {}
    /// Move up (true) or down, one row: the keyboard and VoiceOver way to reorder.
    var move: (Bool) -> Void = { _ in }
    @State private var hover = false
    /// The name, while it is being typed over (double-click to start, Return to keep, Escape to leave).
    @State private var draft: String?
    @FocusState private var naming: Bool
    @GestureState private var holding = false
    @Environment(\.tunerTheme) private var theme

    /// Hold a moment, then drag: the name and the grip are the handle; the buttons stay buttons.
    private var carrying: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            // A gesture state resets when the gesture ends or is cancelled, so the row is always
            // let go of, even when SwiftUI drops the gesture without an end.
            .updating($holding) { value, state, _ in if case .first(true) = value { state = true }; if case .second = value { state = true } }
            .onChanged { value in
                switch value {
                case .first(true): hold()
                case .second(true, let dragging?): drag(dragging.translation.height)
                default: break
                }
            }
            .onEnded { _ in release() }
    }

    var body: some View {
        let sound = model.lidSound
        let state = sound.library.state(of: item)
        let live = sound.playing == item.displayName
        HStack(spacing: 8) {
            IconButton("play.fill", help: "Hear \(item.displayName).") { sound.preview(item) }
                .disabled(state != .ok)
                .accessibilityLabel("Play \(item.displayName)")
            HStack(spacing: 8) {
                if let draft {
                    TextField("Name", text: Binding(get: { draft }, set: { self.draft = $0 }))
                        .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                        .focused($naming)
                        .onSubmit { model.renameSound(item, to: draft); self.draft = nil }
                        .onExitCommand { self.draft = nil }
                        .onChange(of: naming) { _, focused in if !focused, let draft = self.draft { model.renameSound(item, to: draft); self.draft = nil } }
                        .onAppear { naming = true }
                        .help("Type the new name. Return keeps it, Escape leaves it.")
                } else {
                    Text(item.displayName).font(live ? TunerTheme.bodyMedium : TunerTheme.body)
                        .foregroundStyle(state == .ok ? theme.ink : theme.inkLabel).lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                        .onTapGesture(count: 2) { draft = item.displayName }
                        .help("Double-click to rename.")
                }
                if state != .ok {
                    Text(state == .missing ? "Missing" : "Can't be played")
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1)
                        .help(state == .missing ? "The file was moved or deleted. Remove it, or add it again." : "Shut could not open this file.")
                } else if live {
                    Circle().fill(TunerTheme.limeWash).overlay(Circle().strokeBorder(theme.ink, lineWidth: 1)).frame(width: 7, height: 7)
                }
                Spacer(minLength: 6)
                // The grip shows itself when the pointer is near, so the row says it can be moved.
                if canMove {
                    Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.inkTertiary).opacity(hover || carried ? 1 : 0)
                        .padding(.trailing, 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(canMove && draft == nil ? carrying : nil)
            .onChange(of: holding) { _, held in if !held { release() } }
            .help(canMove ? "Hold a moment, then drag up or down to reorder. Double-click the name to rename." : "Double-click the name to rename.")
            // The length, and, with the pointer near, Cut in its place: the name keeps its room.
            if item.canCut, state == .ok, hover || clipping {
                QuietButton(clipping ? "Done" : "Cut", disclosure: !clipping) { clipping.toggle() }
                    .help("Cut a part out as a sound of its own, or make this row play only a part.")
            } else if let length = item.heardLength {
                Text(LidSoundText.durationText(length)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                    .help(item.clipEnd == nil ? "" : "The part from \(LidSoundText.clockText(item.clipStart)) to \(LidSoundText.clockText(item.clipEnd ?? 0)).")
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
        .background(carried ? theme.linen : .clear)
        .overlay(Rectangle().strokeBorder(theme.border, lineWidth: 1).opacity(carried ? 1 : 0))
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: carried)
        .tunerAnimation(TunerTheme.ease, value: hover)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up") { move(true) }
        .accessibilityAction(named: "Move down") { move(false) }
    }
}

/// Under a row: the sound's shape, with the part to play chosen on it by eye. Drag either
/// edge to move it, or the part itself to slide it along; letting go hears the part. A
/// name, and "Add as a sound" makes the part a row of its own under this one (they share
/// the file); "Play only this part" makes this row play it.
private struct LidSoundCut: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var sound: LidSoundController
    let item: LidSoundItem
    let done: () -> Void
    @State private var from: Double
    @State private var to: Double
    @State private var name: String
    @State private var named = false
    /// Parts found by the silence between them, with the names being typed for them.
    @State private var found: [ClosedRange<Double>]?
    @State private var foundNames: [String] = []
    @Environment(\.tunerTheme) private var theme

    init(model: PopoverModel, item: LidSoundItem, done: @escaping () -> Void) {
        self.model = model; self.item = item; self.done = done
        sound = model.lidSound
        let duration = item.duration ?? LidSoundLibrary.clipLength
        let start = item.clipStart, end = item.clipEnd ?? min(duration, start + LidSoundLibrary.clipLength)
        _from = State(initialValue: start)
        _to = State(initialValue: end)
        _name = State(initialValue: LidSoundText.cutName(of: item.displayName, from: start, to: end))
    }

    private var duration: Double { item.duration ?? LidSoundLibrary.clipLength }

    private func hear() {
        var part = item; part.clipStart = from; part.clipEnd = to
        model.lidSound.preview(part)
    }

    private func moved() {
        // The name follows the part until the user has written one of their own.
        if !named { name = LidSoundText.cutName(of: item.displayName, from: from, to: to) }
    }

    private func findTheParts() {
        guard let peaks = sound.waveform(for: item) else { return }
        let parts = LidSoundLibrary.parts(in: peaks, duration: duration)
        found = parts
        foundNames = parts.indices.map { LidSoundText.partName($0) }
        if let first = parts.first { from = first.lowerBound; to = first.upperBound; moved() }
    }

    private func hear(_ range: ClosedRange<Double>) {
        var part = item; part.clipStart = range.lowerBound; part.clipEnd = range.upperBound
        model.lidSound.preview(part)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LidSoundWaveform(peaks: sound.waveform(for: item), duration: duration,
                             from: Binding(get: { from }, set: { from = $0; moved() }),
                             to: Binding(get: { to }, set: { to = $0; moved() }),
                             marks: found ?? [], onEditingEnded: hear)
                .frame(height: 64)
            HStack {
                Text("From \(LidSoundText.clockText(from))")
                Spacer()
                Text(LidSoundText.durationText(to - from)).foregroundStyle(theme.ink)
                Spacer()
                Text("To \(LidSoundText.clockText(to)) of \(LidSoundText.clockText(duration))")
            }
            .font(TunerTheme.mono(10)).foregroundStyle(theme.inkLabel)
            HStack(spacing: 8) {
                Text("Name").font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                TextField("Name", text: Binding(get: { name }, set: { name = $0; named = true }))
                    .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                    .padding(.horizontal, 10).frame(height: 30)
                    .surface(.pill)
                    .help("What the part is called in the list.")
            }
            .padding(.top, 4)
            if let found, found.count > 1 {
                // The parts, numbered as on the shape, each with its name to type: Tab moves on.
                VStack(spacing: 0) {
                    ForEach(found.indices, id: \.self) { i in
                        if i > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", i + 1)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).frame(width: 18)
                            TextField(LidSoundText.partName(i), text: Binding(get: { foundNames.indices.contains(i) ? foundNames[i] : "" },
                                                                           set: { if foundNames.indices.contains(i) { foundNames[i] = $0 } }))
                                .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                                .help("The part's name in the list.")
                            Spacer(minLength: 6)
                            Text("\(LidSoundText.clockText(found[i].lowerBound))–\(LidSoundText.clockText(found[i].upperBound))")
                                .font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                            IconButton("play.fill", help: "Hear this part.") { hear(found[i]) }
                                .accessibilityLabel("Play part \(i + 1)")
                        }
                        .padding(.horizontal, 8).frame(height: 32)
                        .contentShape(Rectangle())
                        .onTapGesture { from = found[i].lowerBound; to = found[i].upperBound; moved() }
                    }
                }
                .surface(.well, radius: TunerTheme.wellRadius)
                .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
                .padding(.top, 6)
            }
            Text(found.map { LidSoundText.partsFound($0.count) } ?? LidSoundText.cutAbout)
                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            HStack(spacing: 10) {
                if let found, found.count > 1 {
                    SecondaryButton("Add \(found.count) sounds", prominent: true) {
                        model.cutSounds(item, parts: zip(found, foundNames).map { ($0, $1) })
                        done()
                    }
                    .help("Every part as a row of its own, under this one, with the names above.")
                    QuietButton("Clear") { self.found = nil; foundNames = [] }
                        .help("Forget the parts found; the edges are yours again.")
                } else if sound.waveform(for: item) != nil {
                    QuietButton("Find the parts") { findTheParts() }
                        .help(LidSoundText.findPartsAbout)
                }
                SecondaryButton("Add as a sound", prominent: found == nil || (found?.count ?? 0) <= 1) {
                    model.cutSound(item, from: from, to: to, name: name)
                    done()
                }
                .help("A new row under this one, playing just this part. The file is shared.")
                QuietButton(item.clipEnd == nil && from == 0 ? "Play only this part" : "Use this part for this row") {
                    var changed = item; changed.clipStart = from; changed.clipEnd = to
                    model.lidSound.settings.update(changed)
                    done()
                }
                .help("This row plays only the part, between the two edges.")
                if item.clipEnd != nil || item.clipStart > 0 {
                    QuietButton("Whole file") {
                        var changed = item; changed.clipStart = 0; changed.clipEnd = nil
                        model.lidSound.settings.update(changed)
                        done()
                    }
                    .help("This row plays the whole file again.")
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 10)
        .background(theme.linen.opacity(0.5))
    }
}

/// The shape of a sound as bars, one per slice of the file, in ink inside the chosen part
/// and quiet outside it, on a Lime Wash where the part is (the selection colour, as
/// everywhere). Two edges, each a hairline with a grab zone; the part between them slides
/// as one. Everything follows the pointer one to one, as the sliders do. Nothing is read
/// from the file here: the peaks come in ready, and until they do the bars are a flat line.
struct LidSoundWaveform: View {
    let peaks: [Float]?
    let duration: TimeInterval
    @Binding var from: TimeInterval
    @Binding var to: TimeInterval
    /// Parts found by the silence between them: outlined and numbered on the shape.
    var marks: [ClosedRange<TimeInterval>] = []
    var onEditingEnded: () -> Void = {}
    @State private var grip: Grip?
    @Environment(\.tunerTheme) private var theme

    /// What the pointer took hold of: an edge, or the whole part (with the offsets it had).
    private enum Grip: Equatable { case from, to, part(fromAt: Double, toAt: Double, pointerAt: Double) }
    /// Points either side of an edge that count as taking hold of it.
    static let edgeReach: CGFloat = 8

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        max(0, min(duration, Double(x / max(width, 1)) * duration))
    }

    private func snapped(_ t: Double) -> Double { (t * 10).rounded() / 10 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let fromX = CGFloat(from / max(duration, 0.001)) * width, toX = CGFloat(to / max(duration, 0.001)) * width
            ZStack(alignment: .leading) {
                // The part, as the selection colour, under the bars.
                Rectangle().fill(theme.washLime).frame(width: max(0, toX - fromX)).offset(x: fromX)
                bars(width: width, height: height, fromX: fromX, toX: toX)
                // The parts found, each in its box with its number.
                ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                    let x0 = CGFloat(mark.lowerBound / max(duration, 0.001)) * width, x1 = CGFloat(mark.upperBound / max(duration, 0.001)) * width
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.ink.opacity(0.6), lineWidth: 1)
                        .frame(width: max(2, x1 - x0), height: height - 6).offset(x: x0, y: 0)
                        .overlay(alignment: .topLeading) {
                            Text(String(format: "%02d", index + 1)).font(TunerTheme.mono(8)).foregroundStyle(theme.ink)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.linen))
                                .offset(x: x0 + 2, y: 5)
                        }
                        .allowsHitTesting(false)
                }
                // The edges.
                Rectangle().fill(theme.ink).frame(width: 1.5).offset(x: fromX - 0.75)
                Rectangle().fill(theme.ink).frame(width: 1.5).offset(x: toX - 0.75)
                if peaks == nil {
                    Text("Reading the file…").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let x = value.location.x
                    if grip == nil {
                        if abs(x - fromX) <= Self.edgeReach { grip = .from }
                        else if abs(x - toX) <= Self.edgeReach { grip = .to }
                        else if x > fromX, x < toX { grip = .part(fromAt: from, toAt: to, pointerAt: time(at: value.startLocation.x, width: width)) }
                        else { grip = abs(x - fromX) < abs(x - toX) ? .from : .to }
                    }
                    let t = snapped(time(at: x, width: width))
                    switch grip {
                    case .from: from = min(t, to - LidSoundLibrary.shortestCut)
                    case .to: to = max(t, from + LidSoundLibrary.shortestCut)
                    case .part(let fromAt, let toAt, let pointerAt):
                        let length = toAt - fromAt
                        let start = snapped(max(0, min(duration - length, fromAt + (time(at: x, width: width) - pointerAt))))
                        from = start; to = start + length
                    case nil: break
                    }
                }
                .onEnded { _ in grip = nil; onEditingEnded() })
        }
        .background(theme.linen)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .help("Drag an edge to move it, or the part itself to slide it along. Let go to hear the part.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The part to play, from \(LidSoundText.clockText(from)) to \(LidSoundText.clockText(to))")
        .accessibilityAdjustableAction { direction in
            let step = max(0.1, duration / 50)
            switch direction {
            case .increment: let f = min(from + step, to - LidSoundLibrary.shortestCut); let t = min(duration, to + step); from = f; to = t
            case .decrement: from = max(0, from - step); to = max(from + LidSoundLibrary.shortestCut, to - step)
            @unknown default: break
            }
            onEditingEnded()
        }
    }

    private func bars(width: CGFloat, height: CGFloat, fromX: CGFloat, toX: CGFloat) -> some View {
        let count = max(peaks?.count ?? LidSoundController.waveformBuckets, 1)
        let slot = width / CGFloat(count), bar = max(1, slot * 0.6)
        return Canvas { context, _ in
            for i in 0..<count {
                let peak = CGFloat(peaks?[safe: i] ?? 0.04)
                let x = CGFloat(i) * slot + (slot - bar) / 2
                let h = max(2, (height - 12) * peak)
                let rect = CGRect(x: x, y: (height - h) / 2, width: bar, height: h)
                let inside = x + bar / 2 >= fromX && x + bar / 2 <= toX
                context.fill(Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(inside ? theme.ink : theme.inkTertiary))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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

            Eyebrow("Volume").padding(.top, 28).padding(.bottom, 12)
            Explained(sound.canSetVolume ? LidSoundText.shareOfMacAbout : LidSoundText.noVolumeControl) {
                SegmentedRow("The dial is", options: ["Its own level", "Of the Mac's"],
                             selection: Binding(get: { settings.volumeMode == .ownLevel ? 0 : 1 }, set: { settings.volumeMode = $0 == 0 ? .ownLevel : .shareOfMac }),
                             help: "What the Volume dial means.")
                    .disabled(!sound.canSetVolume)
            }

            Eyebrow("When the Mac is muted").padding(.top, 8).padding(.bottom, 12)
            Explained(sound.canUnmute ? LidSoundText.unmuteAbout : "This output has no mute switch Shut can lift, so it stays quiet either way.") {
                SegmentedRow("Muted", options: ["Stay quiet", "Unmute for it"],
                             selection: Binding(get: { settings.whenMuted == .unmute ? 1 : 0 }, set: { settings.whenMuted = $0 == 1 ? .unmute : .stayQuiet }),
                             help: "What to do when your Mac is muted as the lid closes.")
            }

            Eyebrow("Extras").padding(.top, 8).padding(.bottom, 12)
            TriggerRow("Play to the end", about: settings.playsToEnd ? LidSoundText.playsToEndAbout : LidSoundText.endsWithTheLid,
                       live: nil, detail: nil,
                       isOn: Binding(get: { settings.playsToEnd }, set: { settings.playsToEnd = $0 }), expanded: nil,
                       help: "On: the lid's sleep waits for the sound, then the Mac sleeps at once, so a two-second sound is heard whole however fast the lid comes down. Off: the sound fades as the lid lands.")
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
