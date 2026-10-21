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
///     01 ON THE LID              Add a sound…    02 PACKS
///     ▶ Rain     Mine     2.4 s        …  ≡      Mine                 0      ›
///     ▶ Click    Starters 0.1 s        …  ≡      Starters          2 of 8    ˅
///     03 TIMING ›   Starts at 60°, with the …      ▶ Click         0.1 s   ✓  …
///     04 SETTINGS › Silent on open · stays quiet     ▶ Blob          0.2 s   +  …
///                                                    Play this pack · Add all
///                                                  Pops              0 of 6    ›
///
/// The answer spans the band: what closing will do, and the sound it names. The one choice
/// (which way) and the volume are on its right, and that is all the band holds, so it is
/// short and nothing in it scrolls. Under the hairline, two columns that each scroll once,
/// the way a music app keeps what is playing apart from the playlists. On the left the
/// stage: what the lid plays, in the order In order walks, never out of view, with the
/// timing and the settings folded under it. On the right the packs, one open at a time: a
/// sound is dragged from a pack onto the stage (or + puts it there), and Play this pack
/// makes the stage that pack. A pack is a playlist, never a switch, so one sound from each
/// of nine packs is nine drags. A well never scrolls inside a column that scrolls.
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
        // As tall as the taller cell and no taller: a three-line answer or the slow-sleep
        // card makes the band grow and the list below give way, so nothing is ever clipped
        // and nothing in the band scrolls.
        HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    // On: it breathes, leans toward the pointer, and a click plays the sound.
                    LidSoundGlyph(playing: sound.playing != nil, height: 26, tint: isOn ? theme.ink : theme.inkLabel,
                                  breathes: isOn, follows: isOn && !situation.candidates.isEmpty,
                                  onTap: isOn && !situation.candidates.isEmpty ? { model.tryTheSound() } : nil)
                        .padding(.bottom, 2)
                    Text(copy.headline)
                        .font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink).lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(copy.detail)
                        .font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    action(situation).padding(.top, 4)
                    if !model.sleep.running.isEmpty {
                        LaggardCard(laggards: model.sleep.running, stop: { model.sleep.stop($0) }, dismiss: { for laggard in model.sleep.running { model.sleep.ignore(laggard) } })
                            .padding(.top, 2)
                    }
                    if let slow = model.sleep.slow, !Set(slow.names).isSubset(of: Set(model.sleep.running.map(\.name))) {
                        SlowSleepCard(slow: slow) { model.sleep.dismissSlow() }.padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
                .frame(width: AwakePage.statusWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(theme.hairline).frame(width: 1)

            // The right cell holds the two things to set first, and only them, so it fits
            // the band's height with nothing to scroll.
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick").font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    ModeSwitch(options: ["Random", "In order"], selection: settings.mode == .random ? 0 : 1) { index in
                        settings.mode = index == 0 ? .random : .inOrder
                    }
                    .help("Random never plays the same sound twice running. In order goes down the list.")
                }
                LidSoundVolume(sound: sound)
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
        .fixedSize(horizontal: false, vertical: true)
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
                stage.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: AwakePage.statusWidth)
            Rectangle().fill(theme.hairline).frame(width: 1)
            ScrollView(showsIndicators: true) {
                packs.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fadesAtTheFold()
            .frame(width: PopoverView.width - AwakePage.statusWidth - 1)
        }
        .frame(maxHeight: .infinity)
        .tunerAnimation(TunerTheme.ease, value: model.showingSoundSettings)
        .tunerAnimation(TunerTheme.ease, value: model.showingSoundTiming)
        .tunerAnimation(TunerTheme.ease, value: model.openPackID)
        .tunerAnimation(TunerTheme.ease, value: model.importNote)
    }

    /// The left column: the stage, then the timing and the settings folded under it.
    private var stage: some View {
        let settings = sound.settings
        let isOn = settings.isOn
        return VStack(alignment: .leading, spacing: 10) {
            // The section's one action sits in its heading, so it is there before the list
            // is scrolled, however long the list grows.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Eyebrow("On the lid", number: "01")
                Spacer(minLength: 8)
                if model.editingStage {
                    // Edit: tick rows, then one action takes them off the lid together.
                    let chosen = model.stageSelection.count
                    let whole = chosen == model.stage.count
                    QuietButton(whole ? "None" : "All") { model.selectWholeStage(!whole) }
                        .help(whole ? "Untick every row." : "Tick every row.")
                    QuietButton(chosen == 0 ? "Remove" : "Remove \(chosen)") { model.removeSelectedFromLid() }
                        .disabled(chosen == 0)
                        .help("The ticked sounds off the lid, back in their packs. Nothing is deleted.")
                    QuietButton("Done") { model.editingStage = false }
                        .padding(.trailing, -6)
                } else {
                    if !model.stage.isEmpty {
                        QuietButton("Edit") { model.editingStage = true }
                            .help("Tick several sounds and take them off the lid at once.")
                    }
                    QuietButton("Add a sound…", disclosure: true) { model.addSounds(.lid) }
                        .help(LidSoundText.addHint)
                        .padding(.trailing, -6)
                }
            }
            .padding(.bottom, 2)
            .tunerAnimation(TunerTheme.ease, value: model.editingStage)
            LidSoundList(model: model)
            if let note = model.importNote {
                Text(note)
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.washSaffron))
                    .transition(.blurFade)
            }
            // When the sound begins, folded with its answer on the fold, so the stage has the
            // column and the angle is still one line away.
            FoldedSection("Timing", number: "03",
                          summary: LidSoundText.timingSummary(startDegrees: Int(sound.startDegrees.rounded()), withEffect: settings.startsWithEffect, playsToEnd: settings.playsToEnd),
                          isOpen: Binding(get: { model.showingSoundTiming }, set: { model.showingSoundTiming = $0 }),
                          help: "Where the sound begins: the screen effect's angle, or one of its own.")
                .padding(.top, 18)
            if model.showingSoundTiming {
                LidSoundStart(sound: sound).transition(.blurFade)
                    .disabled(!isOn)
                    .opacity(isOn ? 1 : 0.5)
                    .tunerAnimation(TunerTheme.ease, value: isOn)
            }
            FoldedSection("Settings", number: "04",
                          summary: LidSoundText.settingsSummary(onOpen: settings.onOpen, whenMuted: settings.whenMuted, volumeMode: settings.volumeMode),
                          isOpen: Binding(get: { model.showingSoundSettings }, set: { model.showingSoundSettings = $0 }),
                          help: "A sound on open, the volume dial, what to do when the Mac is muted, and your packs.")
                .padding(.top, 10)
            if model.showingSoundSettings { LidSoundSettingsRows(model: model).transition(.blurFade) }
        }
    }

    /// The right column: the user's packs as playlists, and under them, folded, the ones
    /// that came with the app. A new user sees Mine and a fold, not a wall of starters.
    private var packs: some View {
        let settings = sound.settings
        let own = settings.packs.filter { !$0.bundled }
        let bundled = settings.packs.filter(\.bundled)
        let bundledSounds = settings.items.filter { item in bundled.contains { $0.id == item.packID } }.count
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Packs", number: "02").padding(.bottom, 2)
            LidSoundPackList(model: model, packs: own, canMakeOne: true)
            FoldedSection("From Shut", summary: LidSoundText.bundledPacksLine(packs: bundled.map(\.name), sounds: bundledSounds),
                          isOpen: Binding(get: { model.showingBundledPacks }, set: { model.showingBundledPacks = $0 }),
                          help: LidSoundText.bundledPacksAbout)
                .padding(.top, 18)
            if model.showingBundledPacks { LidSoundPackList(model: model, packs: bundled, canMakeOne: false).transition(.blurFade) }
        }
        .tunerAnimation(TunerTheme.ease, value: model.showingBundledPacks)
    }
}

/// Where a row is: on the lid (the stage), or in a pack on the right.
enum LidSoundPlace: Equatable {
    case stage
    case shelf(LidSoundPack)
}

/// The stage: the sounds on the lid, in a well as long as the list. The column it sits in
/// is what scrolls, so there is never a scroll inside a scroll. Rows can be carried to a
/// new place ("In order" walks down the list); a sound dragged in from a pack lands at the
/// row it is dropped on; dropped audio files are added. A row at work says so in ink; a
/// file that went missing says so.
private struct LidSoundList: View {
    @ObservedObject var model: PopoverModel
    @State private var dropTargeted = false
    /// Where a sound dragged in would land: the gap before this row, drawn as a line.
    @State private var dropIndex: Int?
    /// The long file whose clip is being chosen, if one is.
    @State private var clipping: UUID?
    /// A row being carried to a new place: hold it a moment, then drag; the others step
    /// aside; let go and the order is kept.
    @State private var carry: Carry?
    @Environment(\.tunerTheme) private var theme

    struct Carry: Equatable {
        let id: UUID
        let from: Int
        var offset: CGFloat = 0
    }

    static let rowHeight: CGFloat = 34

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
        let items = model.stage
        let clipping = self.clipping ?? model.cuttingSoundForTest
        let editing = model.editingStage
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(LidSoundText.stageEmpty)
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                    LidSoundRow(model: model, item: item, place: .stage,
                                clipping: Binding(get: { clipping == item.id }, set: { self.clipping = $0 ? item.id : nil }),
                                ticked: editing ? model.stageSelection.contains(item.id) : nil,
                                carried: carry?.id == item.id, canMove: !editing && items.count > 1 && clipping == nil,
                                hold: { carry = Carry(id: item.id, from: index) },
                                drag: { offset in if carry?.id == item.id { carry?.offset = clamped(offset, from: index, count: items.count) } },
                                release: { if carry?.id == item.id { drop(count: items.count) } },
                                move: { up in model.moveSound(from: index, to: max(0, min(items.count - 1, index + (up ? -1 : 1)))) })
                        .offset(y: shift(of: index, count: items.count))
                        .zIndex(carry?.id == item.id ? 1 : 0)
                    if clipping == item.id { LidSoundCut(model: model, item: item, done: { self.clipping = nil; model.cuttingSoundForTest = nil }).transition(.blurFade) }
                }
            }
            if let pending = model.newPackFor, let item = items.first(where: { $0.id == pending }) {
                LidSoundNewPack(model: model, item: item)
            }
        }
        // A carried row whose list changed under it (removed, re-sorted) is let go of, so
        // nothing is ever left floating out of view.
        .onChange(of: items.map(\.id)) { _, ids in
            if let carry, !ids.contains(carry.id) { self.carry = nil }
            if items.isEmpty { model.editingStage = false }
        }
        .tunerAnimation(TunerTheme.ease, value: editing)

        .surface(.well, radius: TunerTheme.wellRadius)
        .overlay(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous)
            .strokeBorder(theme.ink, lineWidth: 1).opacity(dropTargeted ? 1 : 0))
        .overlay(alignment: .top) {
            // The landing line: 2 pt of ink in the gap the sound would fall into.
            if let dropIndex, !items.isEmpty {
                Rectangle().fill(theme.ink).frame(height: 2)
                    .padding(.horizontal, 8)
                    .offset(y: CGFloat(min(dropIndex, items.count)) * Self.rowHeight - 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
        .onDrop(of: [.fileURL, .utf8PlainText, .plainText],
                delegate: LidSoundStageDrop(model: model, count: items.count, targeted: $dropTargeted, insertion: $dropIndex))
        .tunerAnimation(TunerTheme.ease, value: dropTargeted)
        .tunerAnimation(TunerTheme.ease, value: clipping)
        .help(LidSoundText.onTheLidAbout)
    }
}

/// What lands on the stage: a sound dragged from a pack (its id, as text, under a prefix no
/// other text carries), at the row under the pointer; or audio files, added to Mine and
/// onto the lid. Text that is not a sound of ours is let fall.
private struct LidSoundStageDrop: DropDelegate {
    let model: PopoverModel
    let count: Int
    @Binding var targeted: Bool
    @Binding var insertion: Int?

    static let prefix = "shut-sound:"
    static let packPrefix = "shut-pack:"
    static func payload(for item: LidSoundItem) -> String { prefix + item.id.uuidString }
    static func payload(for pack: LidSoundPack) -> String { packPrefix + pack.id }

    /// The gap nearest the pointer: halfway down a row, the next gap.
    private func gap(_ info: DropInfo) -> Int { max(0, min(count, Int((info.location.y / LidSoundList.rowHeight).rounded()))) }
    private var isSound: (DropInfo) -> Bool { { $0.hasItemsConforming(to: [.utf8PlainText, .plainText]) } }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL, .utf8PlainText, .plainText]) }
    func dropEntered(info: DropInfo) { targeted = true; if isSound(info) { insertion = gap(info) } }
    func dropExited(info: DropInfo) { targeted = false; insertion = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isSound(info) { insertion = gap(info) }
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        insertion = nil
        let index = gap(info)
        let texts = info.itemProviders(for: [.utf8PlainText, .plainText])
        if !texts.isEmpty {
            for provider in texts {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    if text.hasPrefix(Self.prefix), let id = UUID(uuidString: String(text.dropFirst(Self.prefix.count))) {
                        DispatchQueue.main.async { model.putOnLid(id, at: index) }
                    } else if text.hasPrefix(Self.packPrefix) {
                        let packID = String(text.dropFirst(Self.packPrefix.count))
                        DispatchQueue.main.async { model.putPackOnLid(packID, at: index) }
                    }
                }
            }
            return true
        }
        let files = info.itemProviders(for: [.fileURL])
        guard !files.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in files {
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
}

/// Packs, as a music app lists playlists: one well, every pack a row, one open at a time
/// across both wells. Open, a pack shows its sounds, each with + or ✓ and each draggable
/// onto the stage, and under them Play this pack (the stage becomes the pack) and Add all.
/// The user's well ends with "New pack…".
private struct LidSoundPackList: View {
    @ObservedObject var model: PopoverModel
    let packs: [LidSoundPack]
    let canMakeOne: Bool
    @State private var dropTargeted = false
    /// The long file whose clip is being chosen, if one is.
    @State private var clipping: UUID?
    /// The name of a new pack while it is being typed.
    @State private var newName: String?
    /// A pack of the user's being renamed, and the name so far.
    @State private var renaming: (id: String, name: String)?
    @FocusState private var naming: Bool
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
                if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                let open = model.openPackID == pack.id
                let rows = model.shelf(pack.id)
                if let renaming, renaming.id == pack.id {
                    HStack(spacing: 8) {
                        TextField("Name", text: Binding(get: { renaming.name }, set: { self.renaming = (pack.id, $0) }))
                            .textFieldStyle(.plain).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                            .focused($naming)
                            .onSubmit { model.renamePack(pack, to: renaming.name); self.renaming = nil }
                            .onExitCommand { self.renaming = nil }
                            .onAppear { naming = true }
                            .help("The pack's new name. Return keeps it, Escape leaves it.")
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                } else {
                    LidSoundPackRow(model: model, pack: pack, count: rows.count, onLid: rows.filter(\.enabled).count, open: open)
                }
                if open {
                    VStack(spacing: 0) {
                        if rows.isEmpty {
                            Rectangle().fill(theme.hairline).frame(height: 1)
                            Text(LidSoundText.shelfEmpty)
                                .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(rows) { item in
                            Rectangle().fill(theme.hairline).frame(height: 1)
                            LidSoundRow(model: model, item: item, place: .shelf(pack),
                                        clipping: Binding(get: { clipping == item.id }, set: { clipping = $0 ? item.id : nil }), canMove: false)
                                .padding(.leading, 10)   // a step in: these are the pack's, under its name
                            if clipping == item.id { LidSoundCut(model: model, item: item, done: { clipping = nil }).transition(.blurFade) }
                        }
                        // Under the rows: what to do with the pack, and a way to add to it. A bundled
                        // pack takes the user's sounds too: a playlist is theirs to fill.
                        Rectangle().fill(theme.hairline).frame(height: 1)
                        HStack(spacing: 6) {
                            if !rows.isEmpty {
                                QuietButton("Play this pack") { model.playOnly(pack) }
                                    .help("The lid plays this pack and nothing else: the stage becomes these sounds.")
                                Text("·").font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                                if rows.allSatisfy(\.enabled) {
                                    QuietButton("Take all off") { model.setShelf(pack, onLid: false) }
                                        .help("Every sound in this pack off the lid.")
                                } else {
                                    QuietButton("Add all") { model.setShelf(pack, onLid: true) }
                                        .help("Every sound in this pack onto the lid, after what is there.")
                                }
                            }
                            Spacer(minLength: 0)
                            QuietButton("Add a sound…", disclosure: true) { model.addSounds(.pack(pack)) }
                                .help("Choose audio files for this pack: mp3, m4a, wav or aiff. They go in here, off the lid; + puts one on. Files can also be dropped on the pack.")
                        }
                        .padding(.leading, 16).padding(.trailing, 8).frame(height: 32)
                        if !pack.bundled, pack.id != LidSoundPack.mineID {
                            // A pack of the user's own is theirs to rename and to let go of: its sounds
                            // go to Mine, never deleted.
                            Rectangle().fill(theme.hairline).frame(height: 1)
                            HStack(spacing: 6) {
                                QuietButton("Rename") { renaming = (pack.id, pack.name) }
                                    .help("A new name for this pack.")
                                Text("·").font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                                QuietButton("Remove pack") { model.removePack(pack) }
                                    .help(rows.isEmpty ? "Remove this pack." : "Remove this pack. Its \(rows.count == 1 ? "sound goes" : "\(rows.count) sounds go") to Mine; nothing is deleted.")
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, 16).padding(.trailing, 8).frame(height: 32)
                        }
                        if let pending = model.newPackFor, let item = rows.first(where: { $0.id == pending }) {
                            LidSoundNewPack(model: model, item: item)
                        }
                    }
                    .transition(.blurFade)
                }
            }
            if canMakeOne {
                if !packs.isEmpty { Rectangle().fill(theme.hairline).frame(height: 1) }
                if let name = newName {
                    HStack(spacing: 8) {
                        Text("New pack").font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                        TextField("Name", text: Binding(get: { name }, set: { newName = $0 }))
                            .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                            .focused($naming)
                            .onSubmit { if let pack = model.newPack(named: name) { model.openPackID = pack.id }; newName = nil }
                            .onExitCommand { newName = nil }
                            .onAppear { naming = true }
                            .help("The pack's name. Return makes it, Escape leaves it.")
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                } else {
                    QuietButton("New pack…") { newName = "" }
                        .help("A pack of your own, a playlist for the lid. Move sounds into it from a row's menu.")
                        .padding(.horizontal, 6).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .surface(.well, radius: TunerTheme.wellRadius)
        .overlay(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous)
            .strokeBorder(theme.ink, lineWidth: 1).opacity(dropTargeted ? 1 : 0))
        .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
        // Files dropped on the packs go into the open pack (one of these), else into Mine.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            let open = packs.first { $0.id == model.openPackID }
            let destination: PopoverModel.SoundDestination = open.map { .pack($0) } ?? .pack(model.lidSound.settings.pack(LidSoundPack.mineID) ?? LidSoundPack.mine)
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
            group.notify(queue: .main) { model.importSounds(urls, to: destination) }
            return true
        }
        .tunerAnimation(TunerTheme.ease, value: dropTargeted)
        .tunerAnimation(TunerTheme.ease, value: clipping)
        .tunerAnimation(TunerTheme.ease, value: newName == nil)
        .tunerAnimation(TunerTheme.ease, value: renaming == nil)
        .help(canMakeOne ? LidSoundText.packsAbout : LidSoundText.bundledPacksAbout)
    }
}

/// Makes a row draggable when there is something to drag, and gives the drag the row's own
/// look to carry: a card with ▶, the name and the length, lifted off the well. The stage's
/// rows have their own hold-and-drag for reordering, and a system drag would fight it.
private struct DragOntoStage: ViewModifier {
    let payload: String?
    let item: LidSoundItem
    @Environment(\.tunerTheme) private var theme

    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.inkLabel).frame(width: 28)
                    Text(item.displayName).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                    Spacer(minLength: 12)
                    if let length = item.heardLength {
                        Text(LidSoundText.durationText(length)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary)
                    }
                }
                .padding(.leading, 6).padding(.trailing, 12)
                .frame(width: 260, height: LidSoundList.rowHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            }
        } else {
            content
        }
    }
}

/// A pack's row dragged onto the stage: a card with the pack's name and how many sounds it
/// brings. Nothing to drag when the pack is empty.
private struct DragPackOntoStage: ViewModifier {
    let pack: LidSoundPack?
    let count: Int
    @Environment(\.tunerTheme) private var theme

    func body(content: Content) -> some View {
        if let pack {
            content.draggable(LidSoundStageDrop.payload(for: pack)) {
                HStack(spacing: 8) {
                    Text(pack.name).font(TunerTheme.bodyMedium).foregroundStyle(theme.ink).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(count == 1 ? "1 sound" : "\(count) sounds").font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.horizontal, 12)
                .frame(width: 260, height: LidSoundList.rowHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            }
        } else {
            content
        }
    }
}

/// A pack's row: its name, how many of its sounds are on the lid, and a chevron that says
/// whether it is open. The credit is its help. A click opens it and closes the other.
private struct LidSoundPackRow: View {
    @ObservedObject var model: PopoverModel
    let pack: LidSoundPack
    let count: Int
    let onLid: Int
    let open: Bool
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        Button { model.openPackID = open ? nil : pack.id } label: {
            HStack(spacing: 8) {
                Text(pack.name).font(open ? TunerTheme.bodyMedium : TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Text(LidSoundText.shelfLine(onLid: onLid, of: count)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkLabel)
                    .frame(width: 14)
            }
            .padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // The whole pack can be dragged onto the stage: every sound in it lands together, where
        // it is dropped. What travels is the pack's name and its count.
        .modifier(DragPackOntoStage(pack: count > 0 ? pack : nil, count: count))
        .help(pack.bundled ? (pack.credit.map { "\($0) Drag the pack onto the lid to put every sound in it there." } ?? "Comes with the app.")
                           : "Your own pack. Drag it onto the lid to put every sound in it there; rename it below.")
        .accessibilityLabel("\(pack.name), \(LidSoundText.shelfLine(onLid: onLid, of: count)) on the lid")
        .accessibilityAddTraits(open ? [.isHeader, .isSelected] : .isHeader)
    }
}

/// The tick in Edit: an empty ring, or the ring in ink with a check in it.
private struct LidSoundTick: View {
    let on: Bool
    let name: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            LidSoundMark(on: on, off: nil, hover: hover)
                .frame(width: 28, height: 28).contentShape(Circle())
        }
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
        .buttonStyle(PressStyle())
        .tunerAnimation(TunerTheme.ease, value: on)
        .help(on ? "Ticked: Remove takes \(name) off the lid." : "Tick \(name) to remove it from the lid.")
        .accessibilityLabel(on ? "\(name), ticked" : "\(name), not ticked")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The one control on a pack's row. Off the lid, a small plus in the label ink. On it, the
/// Lid sound glyph itself, tiny and still, in ink: the sound carries the mark of the thing
/// it is on, the same three bars as the tab and the band, so it needs no legend. With the
/// pointer near, the bars give way to an ×, so the way off is seen before it is looked for.
private struct LidSoundLidToggle: View {
    let item: LidSoundItem
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if item.enabled {
                    LidSoundGlyph(playing: false, height: 11, tint: theme.ink).opacity(hover ? 0 : 1)
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.ink).opacity(hover ? 1 : 0)
                } else {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(hover ? theme.ink : theme.inkLabel)
                }
            }
            .frame(width: 28, height: 28)
            .background(Circle().fill(hover ? theme.linen : .clear))
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tunerAnimation(TunerTheme.ease, value: hover)
        .tunerAnimation(TunerTheme.ease, value: item.enabled)
        .help(item.enabled ? "On the lid. Click to take \(item.displayName) off; it stays in this pack." : "Put \(item.displayName) on the lid.")
        .accessibilityLabel(item.enabled ? "Take \(item.displayName) off the lid" : "Put \(item.displayName) on the lid")
        .accessibilityAddTraits(item.enabled ? .isSelected : [])
    }
}

/// Edit's tick: an 18 pt ring, empty until ticked, then in ink with a check in it.
private struct LidSoundMark: View {
    let on: Bool
    /// The symbol when off (a plus on a pack's row); nil draws the empty ring (Edit's tick).
    let off: String?
    var hover = false
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? theme.ink : (hover ? theme.inkLabel : theme.border), lineWidth: 1)
                .opacity(on || off == nil || hover ? 1 : 0)
            Image(systemName: on ? "checkmark" : (off ?? "checkmark"))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(on ? theme.ink : theme.inkLabel)
                .opacity(on || off != nil ? 1 : 0)
        }
        .frame(width: 18, height: 18)
    }
}

/// One sound. On the lid: ▶, the name, its shelf, the length, a menu and a grip. On a shelf:
/// ▶, the name, the length, + or ✓, and the menu.
private struct LidSoundRow: View {
    @ObservedObject var model: PopoverModel
    let item: LidSoundItem
    let place: LidSoundPlace
    @Binding var clipping: Bool
    /// In Edit on the stage: whether this row is ticked. nil when not editing.
    var ticked: Bool? = nil
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
        let onStage = place == .stage
        HStack(spacing: 8) {
            if let ticked {
                // Edit: the tick stands where ▶ was, and the whole row is its target.
                LidSoundTick(on: ticked, name: item.displayName) { model.toggleStageSelection(item.id) }
            } else {
                IconButton("play.fill", help: "Hear \(item.displayName).") { sound.preview(item) }
                    .disabled(state != .ok)
                    .accessibilityLabel("Play \(item.displayName)")
            }
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
                        .onTapGesture(count: 2) { if ticked == nil { draft = item.displayName } }
                        .onTapGesture(count: 1) { if ticked != nil { model.toggleStageSelection(item.id) } }
                        .help(ticked == nil ? "Double-click to rename." : "Tick to remove from the lid.")
                }
                if state != .ok {
                    Text(state == .missing ? "Missing" : "Can't be played")
                        .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineLimit(1)
                        .help(state == .missing ? "The file was moved or deleted. Remove it, or add it again." : "Shut could not open this file.")
                } else if live {
                    Circle().fill(TunerTheme.limeWash).overlay(Circle().strokeBorder(theme.ink, lineWidth: 1)).frame(width: 7, height: 7)
                } else if onStage, draft == nil, let shelf = sound.settings.pack(item.packID) {
                    // Which shelf it came from, in the faintest ink: the stage mixes them.
                    Text(shelf.name).font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary).lineLimit(1).truncationMode(.tail)
                        .help("On the \(shelf.name) shelf, under Browse.")
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
            .help(canMove ? "Hold a moment, then drag up or down to reorder. Double-click the name to rename."
                          : onStage ? "Double-click the name to rename." : "Drag onto the lid, or press +. Double-click the name to rename.")
            // The length, and, with the pointer near, Cut in its place: the name keeps its room.
            if item.canCut, state == .ok, hover || clipping {
                QuietButton(clipping ? "Done" : "Cut", disclosure: !clipping) { clipping.toggle() }
                    .help("Cut a part out as a sound of its own, or make this row play only a part.")
            } else if let length = item.heardLength {
                Text(LidSoundText.durationText(length)).font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                    .help(item.clipEnd == nil ? "" : "The part from \(LidSoundText.clockText(item.clipStart)) to \(LidSoundText.clockText(item.clipEnd ?? 0)).")
            }
            if !onStage {
                LidSoundLidToggle(item: item) { model.setOnLid(item, !item.enabled) }
                    .disabled(state != .ok && !item.enabled)
            }
            // Everything else about a row, behind one mark: the row stays a name and a button.
            if ticked == nil { Menu {
                Button("Hear") { sound.preview(item) }.disabled(state != .ok)
                Button("Rename") { draft = item.displayName }
                if item.canCut, state == .ok { Button(clipping ? "Done cutting" : "Cut a part…") { clipping.toggle() } }
                Menu("Move to") {
                    ForEach(sound.settings.packs.filter { $0.id != item.packID }) { pack in
                        Button(pack.name) { model.moveSound(item, to: pack.id) }
                    }
                    Divider()
                    Button("New pack…") { model.newPackFor = item.id }
                }
                if onStage { Button("Remove from the lid") { model.setOnLid(item, false) } }
                if !item.fromManifest {
                    Divider()
                    Button("Delete from Shut", role: .destructive) { model.removeSound(item) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.inkLabel)
                    .frame(width: 28, height: 28).contentShape(Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(onStage ? "Hear, rename, cut, move to a pack, or remove from the lid: it stays in its pack." : "Hear, rename, cut, or move to a pack.")
            .accessibilityLabel("More for \(item.displayName)") }
        }
        .padding(.leading, 6).padding(.trailing, 8).frame(height: LidSoundList.rowHeight - 1)
        .background(carried ? theme.linen : .clear)
        .overlay(Rectangle().strokeBorder(theme.border, lineWidth: 1).opacity(carried ? 1 : 0))
        .contentShape(Rectangle())
        // A pack's row is dragged onto the stage as a whole: the row is the handle and the row
        // is what travels, so what lands is what was picked up. The buttons stay buttons.
        .modifier(DragOntoStage(payload: onStage ? nil : LidSoundStageDrop.payload(for: item), item: item))
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
    /// The found part the handles are on: moving them fixes this part, not just the preview.
    @State private var chosenPart: Int?
    /// What the silences would split the sound into, worked out as soon as the shape is in
    /// and offered in one line, so nobody has to know to ask.
    @State private var suggested: [ClosedRange<Double>] = []
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
        // With a found part chosen, the handles are editing it: the silence finder's guess
        // is a start, and the ear has the last word.
        if let i = chosenPart, found?.indices.contains(i) == true { found?[i] = from...to }
    }

    /// The handles onto a found part, so they can fix it.
    private func choose(_ i: Int) {
        guard let found, found.indices.contains(i) else { return }
        chosenPart = i
        from = found[i].lowerBound; to = found[i].upperBound
        if !named { name = LidSoundText.cutName(of: item.displayName, from: from, to: to) }
    }

    /// A found part the user does not want: out of the list, the numbers closing up.
    private func drop(_ i: Int) {
        guard found?.indices.contains(i) == true else { return }
        found?.remove(at: i)
        if foundNames.indices.contains(i) { foundNames.remove(at: i) }
        if (found?.count ?? 0) <= 1 { found = nil; foundNames = []; chosenPart = nil; return }
        choose(min(i, (found?.count ?? 1) - 1))
    }

    private func suggest() {
        guard suggested.isEmpty, let peaks = sound.waveform(for: item) else { return }
        suggested = LidSoundLibrary.parts(in: peaks, duration: duration)
    }

    private func findTheParts() {
        guard let peaks = sound.waveform(for: item) else { return }
        let parts = suggested.isEmpty ? LidSoundLibrary.parts(in: peaks, duration: duration) : suggested
        found = parts
        foundNames = parts.indices.map { LidSoundText.partName($0) }
        choose(0)
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
                        let chosen = chosenPart == i
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", i + 1)).font(TunerTheme.mono(10)).foregroundStyle(chosen ? theme.ink : theme.inkTertiary).frame(width: 18)
                            TextField(LidSoundText.partName(i), text: Binding(get: { foundNames.indices.contains(i) ? foundNames[i] : "" },
                                                                           set: { if foundNames.indices.contains(i) { foundNames[i] = $0 } }))
                                .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                                .help("The part's name in the list.")
                            Spacer(minLength: 6)
                            Text("\(LidSoundText.clockText(found[i].lowerBound))–\(LidSoundText.clockText(found[i].upperBound))")
                                .font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                            IconButton("play.fill", help: "Hear this part.") { hear(found[i]) }
                                .accessibilityLabel("Play part \(i + 1)")
                            IconButton("xmark", help: "Leave this part out.") { drop(i) }
                                .accessibilityLabel("Leave out part \(i + 1)")
                        }
                        .padding(.horizontal, 8).frame(height: 32)
                        // The chosen part sits on the selection colour: the handles are its.
                        .background(chosen ? theme.washLime : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { choose(i) }
                        .help(chosen ? "The handles are on this part: drag them to fix where it begins and ends." : "Click to put the handles on this part.")
                    }
                }
                .surface(.well, radius: TunerTheme.wellRadius)
                .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
                .padding(.top, 6)
                .tunerAnimation(TunerTheme.ease, value: chosenPart)
            }
            if let found, found.count > 1 {
                Text(LidSoundText.partsFound(found.count))
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            } else {
                Text(LidSoundText.cutAbout)
                    .font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                if suggested.count > 1 {
                    // The offer: the silences already found, one click from being the parts.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(LidSoundText.partsSuggested(suggested.count))
                            .font(TunerTheme.bodySmall).foregroundStyle(theme.ink).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        QuietButton("Split there") { findTheParts() }
                            .help(LidSoundText.findPartsAbout)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.washSaffron))
                    .padding(.top, 4)
                }
            }
            HStack(spacing: 10) {
                if let found, found.count > 1 {
                    SecondaryButton("Add \(found.count) sounds", prominent: true) {
                        model.cutSounds(item, parts: zip(found, foundNames).map { ($0, $1) })
                        done()
                    }
                    .help("Every part as a row of its own, under this one, with the names above.")
                    QuietButton("Clear") { self.found = nil; foundNames = []; chosenPart = nil }
                        .help("Forget the parts found; the handles are yours again.")
                } else if sound.waveform(for: item) != nil, suggested.count <= 1 {
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
        .onAppear(perform: suggest)
        .onChange(of: sound.waveform(for: item) == nil) { _, _ in suggest() }
        .tunerAnimation(TunerTheme.ease, value: suggested.count)
    }
}

/// The shape of a sound as bars, one per slice of the file, in ink inside the chosen part
/// and quiet outside it, on a Lime Wash where the part is (the selection colour, as
/// everywhere). Two edges, each with a handle to take hold of (a small pill, Paper White on
/// an ink line, the way a slider's knob says "me"), the pointer turning to a resize arrow
/// near it and to a hand over the part, which slides as one. The handle in hand shows its
/// time. Everything follows the pointer one to one, as the sliders do. Nothing is read from
/// the file here: the peaks come in ready, and until they do the bars are a flat line.
struct LidSoundWaveform: View {
    let peaks: [Float]?
    let duration: TimeInterval
    @Binding var from: TimeInterval
    @Binding var to: TimeInterval
    /// Parts found by the silence between them: outlined and numbered on the shape.
    var marks: [ClosedRange<TimeInterval>] = []
    var onEditingEnded: () -> Void = {}
    @State private var grip: Grip?
    /// What the pointer is over, for the cursor: an edge, the part, or nothing.
    @State private var near: Near?
    @Environment(\.tunerTheme) private var theme

    /// What the pointer took hold of: an edge, or the whole part (with the offsets it had).
    private enum Grip: Equatable { case from, to, part(fromAt: Double, toAt: Double, pointerAt: Double) }
    private enum Near: Equatable { case edge, part }
    /// Points either side of an edge that count as taking hold of it.
    static let edgeReach: CGFloat = 10
    static let handleSize = CGSize(width: 8, height: 26)

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
                // The edges, each with its handle; the one in hand carries its time.
                edge(at: fromX, time: from, held: grip == .from, height: height)
                edge(at: toX, time: to, held: grip == .to, height: height)
                if peaks == nil {
                    Text("Reading the file…").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let x = point.x
                    let now: Near? = abs(x - fromX) <= Self.edgeReach || abs(x - toX) <= Self.edgeReach ? .edge : (x > fromX && x < toX ? .part : nil)
                    if now != near { near = now; cursor(for: now) }
                case .ended:
                    if near != nil { near = nil; cursor(for: nil) }
                }
            }
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
        // Half a handle of margin either side, so a handle at the very start or end is whole.
        .padding(.horizontal, Self.handleSize.width / 2)
        .background(theme.linen)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .help("Drag a handle to set where the part begins or ends, or drag the part itself to slide it along. Let go to hear it.")
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

    /// The pointer says what a drag here would do, before it is tried.
    private func cursor(for near: Near?) {
        switch near {
        case .edge: NSCursor.resizeLeftRight.set()
        case .part: NSCursor.openHand.set()
        case nil: NSCursor.arrow.set()
        }
    }

    /// An edge: the line, the handle on it, and, while held, the time it is at.
    private func edge(at x: CGFloat, time: Double, held: Bool, height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(theme.ink).frame(width: 1.5, height: height)
            Capsule().fill(theme.card)
                .overlay(Capsule().strokeBorder(theme.ink, lineWidth: 1))
                .frame(width: Self.handleSize.width, height: Self.handleSize.height)
                .overlay {
                    // Two faint lines in the handle: a grip, as on a row.
                    HStack(spacing: 1.5) { Rectangle().frame(width: 1); Rectangle().frame(width: 1) }
                        .foregroundStyle(theme.inkTertiary).frame(height: 8)
                }
            if held {
                Text(LidSoundText.clockText(time)).font(TunerTheme.mono(9)).foregroundStyle(theme.ink)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
                    .offset(y: -(height / 2) + 9)
            }
        }
        .frame(width: Self.handleSize.width, height: height)
        .offset(x: x - Self.handleSize.width / 2)
        .allowsHitTesting(false)
        .tunerAnimation(TunerTheme.ease, value: held)
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

/// What a close picks from: every pack, or one. Up to three packs sit in the pill beside
/// All; more go in a menu, so the row never outgrows its column.
/// Under the list while a pack is being named for a sound: Return makes it and moves the
/// sound there; Escape leaves it.
private struct LidSoundNewPack: View {
    @ObservedObject var model: PopoverModel
    let item: LidSoundItem
    @State private var name = ""
    @FocusState private var naming: Bool
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text("New pack").font(TunerTheme.body).foregroundStyle(theme.inkLabel)
            TextField("Name", text: $name).textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                .focused($naming)
                .onSubmit {
                    if let pack = model.newPack(named: name) { model.moveSound(item, to: pack.id) }
                    model.newPackFor = nil
                }
                .onExitCommand { model.newPackFor = nil }
                .onAppear { naming = true }
                .help("The pack's name. Return makes it and moves \(item.displayName) there.")
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(theme.linen.opacity(0.5))
    }
}

/// The packs, under Settings: every shelf, with where a bundled one's audio came from; the
/// user's own can be renamed (double-click) and removed (its sounds go to Mine). A bundled
/// pack is a shelf, never in anyone's way: nothing on it plays unless it was put on the lid.
private struct LidSoundPackRows: View {
    @ObservedObject var model: PopoverModel
    @State private var draft: (id: String, name: String)?
    @State private var newName: String?
    @FocusState private var naming: Bool
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        let settings = model.lidSound.settings
        let inUse = settings.packs
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(inUse.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 { Rectangle().fill(theme.hairline).frame(height: 1) }
                    let count = settings.items.filter { $0.packID == pack.id }.count
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            if let draft, draft.id == pack.id {
                                TextField("Name", text: Binding(get: { draft.name }, set: { self.draft = (pack.id, $0) }))
                                    .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                                    .focused($naming)
                                    .onSubmit { model.renamePack(pack, to: draft.name); self.draft = nil }
                                    .onExitCommand { self.draft = nil }
                                    .onAppear { naming = true }
                            } else {
                                Text(pack.name).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                                    .onTapGesture(count: 2) { if !pack.bundled { draft = (pack.id, pack.name) } }
                                    .help(pack.bundled ? "Comes with the app." : "Double-click to rename.")
                            }
                            if let credit = pack.credit {
                                Text(credit).font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary).lineLimit(1).truncationMode(.tail).help(credit)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(count == 1 ? "1 sound" : "\(count) sounds").font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary).fixedSize()
                        if !pack.bundled, pack.id != LidSoundPack.mineID {
                            IconButton("xmark", help: "Remove the pack. Its sounds go to Mine.") { model.removePack(pack) }
                                .accessibilityLabel("Remove the pack \(pack.name)")
                        }
                    }
                    .padding(.horizontal, 10).frame(minHeight: 36)
                }
                Rectangle().fill(theme.hairline).frame(height: 1)
                if let name = newName {
                    HStack(spacing: 8) {
                        Text("New pack").font(TunerTheme.body).foregroundStyle(theme.inkLabel)
                        TextField("Name", text: Binding(get: { name }, set: { newName = $0 }))
                            .textFieldStyle(.plain).font(TunerTheme.body).foregroundStyle(theme.ink)
                            .focused($naming)
                            .onSubmit { model.newPack(named: name); newName = nil }
                            .onExitCommand { newName = nil }
                            .onAppear { naming = true }
                    }
                    .padding(.horizontal, 10).frame(height: 36)
                } else {
                    QuietButton("New pack…") { newName = "" }
                        .help("A pack of your own. Move sounds into it from a row's menu.")
                        .padding(.horizontal, 4).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .surface(.well, radius: TunerTheme.wellRadius)
            .clipShape(RoundedRectangle(cornerRadius: TunerTheme.wellRadius, style: .continuous))
        }
        .tunerAnimation(TunerTheme.ease, value: newName == nil)
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

            Eyebrow("Packs").padding(.top, 8).padding(.bottom, 12)
            LidSoundPackRows(model: model)

            Eyebrow("Extras").padding(.top, 28).padding(.bottom, 12)
            TriggerRow("Play to the end", about: settings.playsToEnd ? LidSoundText.playsToEndAbout : LidSoundText.endsWithTheLid,
                       live: nil, detail: nil,
                       isOn: Binding(get: { settings.playsToEnd }, set: { settings.playsToEnd = $0 }), expanded: nil,
                       help: "On: the lid's sleep waits for the sound, then the Mac sleeps at once, so a two-second sound is heard whole however fast the lid comes down. Off: the sound fades as the lid lands.")
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
