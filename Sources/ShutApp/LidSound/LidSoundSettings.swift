import Combine
import Foundation

/// The Lid sound switches, backed by UserDefaults like `StayAwakeSettings`. Kept apart so
/// the feature can be read, tested and removed as one piece. Unlike Stay awake's one-close
/// arming, `isOn` here is a standing preference and is saved.
///
/// Two places, one list. Every sound the app has is in `items`, each on a shelf (its pack).
/// The ones with `enabled` set are **on the lid**: that short list, in `items` order, is
/// what a close picks from, and the only thing In order walks down. A pack is a shelf to
/// browse, never a switch, so one sound from each of nine packs is nine clicks, not nine
/// packs added and sixty switches turned off.
@MainActor
final class LidSoundSettings: ObservableObject {
    let defaults: UserDefaults

    enum Mode: String, Codable { case random, inOrder }
    enum WhenMuted: String, Codable { case stayQuiet, unmute }
    /// What the Volume dial means: a share of the Mac's volume as it is, or a level of its
    /// own that Shut sets the Mac to for the sound and puts back after.
    enum VolumeMode: String, Codable { case shareOfMac, ownLevel }
    /// What "Also on open" plays: the close's pick again, or one sound in particular.
    enum OnOpenPick: Equatable {
        case samePick
        case item(UUID)
        var stored: String { if case .item(let id) = self { return id.uuidString } else { return "same" } }
        init(stored: String?) { self = stored.flatMap(UUID.init(uuidString:)).map(OnOpenPick.item) ?? .samePick }
    }

    @Published var isOn: Bool { didSet { defaults.set(isOn, forKey: "lidSound.isOn") } }
    /// Every sound, in the order shown. One blob, so a row's fields travel together.
    @Published var items: [LidSoundItem] { didSet { defaults.set(try? JSONEncoder().encode(items), forKey: "lidSound.items") } }
    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "lidSound.mode") } }
    /// 0…1 of the Mac's own volume, which Shut never changes.
    @Published var volume: Double { didSet { defaults.set(volume, forKey: "lidSound.volume") } }
    @Published var onOpen: Bool { didSet { defaults.set(onOpen, forKey: "lidSound.onOpen") } }
    @Published var onOpenPick: OnOpenPick { didSet { defaults.set(onOpenPick.stored, forKey: "lidSound.onOpenPick") } }
    @Published var whenMuted: WhenMuted { didSet { defaults.set(whenMuted.rawValue, forKey: "lidSound.whenMuted") } }
    @Published var volumeMode: VolumeMode { didSet { defaults.set(volumeMode.rawValue, forKey: "lidSound.volumeMode") } }
    /// The sound starts where the screen effect does (Speed, on Lid effects), or at its own
    /// angle, `startDegrees` above shut.
    @Published var startsWithEffect: Bool { didSet { defaults.set(startsWithEffect, forKey: "lidSound.startsWithEffect") } }
    @Published var startDegrees: Double { didSet { defaults.set(startDegrees, forKey: "lidSound.startDegrees") } }
    /// The sound plays to its end: the Mac waits for it, then sleeps at once. Off: a short
    /// fade as the lid lands, whatever the length.
    @Published var playsToEnd: Bool { didSet { defaults.set(playsToEnd, forKey: "lidSound.playsToEnd") } }
    /// The shelves: Mine, then the user's own packs, then the bundled ones as the manifest
    /// lists them. Only the user's packs are saved; the bundled ones come from the manifest
    /// each launch.
    @Published var packs: [LidSoundPack] { didSet { defaults.set(try? JSONEncoder().encode(packs.filter { !$0.bundled }), forKey: "lidSound.packs") } }
    /// The user has put a sound on the lid themselves, by + or a drag: the hint that says how
    /// is for before that, and never after.
    @Published var hasPutOnLid: Bool { didSet { defaults.set(hasPutOnLid, forKey: "lidSound.hasPutOnLid") } }

    /// Random never plays the same sound twice running; in order carries on from here.
    var lastPickID: UUID? { didSet { defaults.set(lastPickID?.uuidString, forKey: "lidSound.lastPickID") } }
    var nextIndex: Int { didSet { defaults.set(nextIndex, forKey: "lidSound.nextIndex") } }
    /// "Unmute for it" lifted the mute and has not put it back yet (the Mac may have slept
    /// first). Restored on the next launch or wake, on the same output device only.
    var muteToRestore: Bool { didSet { defaults.set(muteToRestore, forKey: "lidSound.muteToRestore") } }
    var muteToRestoreDeviceUID: String? { didSet { defaults.set(muteToRestoreDeviceUID, forKey: "lidSound.muteToRestoreDeviceUID") } }
    /// "Its own level" set the Mac's volume and has not put it back yet; the value owed.
    var volumeToRestore: Double? { didSet { defaults.set(volumeToRestore, forKey: "lidSound.volumeToRestore") } }

    init(defaults: UserDefaults = .standard, manifest: [LidSoundLibrary.ManifestPack]? = nil) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        let manifest = manifest ?? LidSoundLibrary().packs()
        isOn = bool("lidSound.isOn", false)
        if let data = defaults.data(forKey: "lidSound.items"), let saved = try? JSONDecoder().decode([LidSoundItem].self, from: data) {
            // An older list's manifest sounds find their pack first; then the list is brought
            // to this shape, once: written back here, since a property observer does not run
            // in init, and the keys it read are removed below, so a second launch finds
            // nothing left to migrate.
            let settled = Self.settled(saved, against: manifest)
            let migrated = Self.migrated(settled, hiddenPacks: Set(defaults.stringArray(forKey: "lidSound.hiddenPacks") ?? []))
            if migrated != saved { defaults.set(try? JSONEncoder().encode(migrated), forKey: "lidSound.items") }
            items = migrated
        } else {
            // First launch: every bundled sound on its shelf, the starters on the lid, so the
            // first close has something to play.
            items = manifest.flatMap { pack in pack.starters.map { $0.item(onLid: pack.startsOnTheLid) } }
        }
        for key in ["lidSound.hiddenPacks", "lidSound.shownPacks", "lidSound.playsFrom", "lidSound.nextIndexByScope"] { defaults.removeObject(forKey: key) }
        let userPacks = (defaults.data(forKey: "lidSound.packs")).flatMap { try? JSONDecoder().decode([LidSoundPack].self, from: $0) } ?? [LidSoundPack.mine]
        packs = (userPacks.contains { $0.id == LidSoundPack.mineID } ? userPacks : [LidSoundPack.mine] + userPacks) + manifest.map(\.pack)
        mode = defaults.string(forKey: "lidSound.mode").flatMap(Mode.init(rawValue:)) ?? .random
        volume = defaults.object(forKey: "lidSound.volume") as? Double ?? 0.7
        onOpen = bool("lidSound.onOpen", false)
        onOpenPick = OnOpenPick(stored: defaults.string(forKey: "lidSound.onOpenPick"))
        whenMuted = defaults.string(forKey: "lidSound.whenMuted").flatMap(WhenMuted.init(rawValue:)) ?? .stayQuiet
        // Its own level by default: the dial is the level heard, whatever the Mac is set to.
        volumeMode = defaults.string(forKey: "lidSound.volumeMode").flatMap(VolumeMode.init(rawValue:)) ?? .ownLevel
        startsWithEffect = bool("lidSound.startsWithEffect", true)
        startDegrees = defaults.object(forKey: "lidSound.startDegrees") as? Double ?? 60
        playsToEnd = bool("lidSound.playsToEnd", false)
        hasPutOnLid = bool("lidSound.hasPutOnLid", false)
        lastPickID = defaults.string(forKey: "lidSound.lastPickID").flatMap(UUID.init(uuidString:))
        nextIndex = defaults.integer(forKey: "lidSound.nextIndex")
        muteToRestore = defaults.bool(forKey: "lidSound.muteToRestore")
        muteToRestoreDeviceUID = defaults.string(forKey: "lidSound.muteToRestoreDeviceUID")
        volumeToRestore = defaults.object(forKey: "lidSound.volumeToRestore") as? Double
    }

    /// A 0.4.0 list had three ways for a sound to be out of the pick besides its switch: kept
    /// for later, a starter hidden, or its whole pack put away. All three now mean one thing,
    /// off the lid, and the sound stays on its shelf. Nothing that was silent starts playing.
    static func migrated(_ items: [LidSoundItem], hiddenPacks: Set<String>) -> [LidSoundItem] {
        items.map { item in
            var item = item
            if item.kept || item.hidden || hiddenPacks.contains(item.packID) { item.enabled = false }
            item.kept = false
            item.hidden = false
            return item
        }
    }

    /// An older list's manifest sounds carry no pack: give each the manifest pack that lists
    /// its file and part; the rest stay where they are. Also runs after `adoptNewPacks`.
    func settlePacks(against manifest: [LidSoundLibrary.ManifestPack]) {
        let settled = Self.settled(items, against: manifest)
        if settled != items { items = settled }
    }

    static func settled(_ items: [LidSoundItem], against manifest: [LidSoundLibrary.ManifestPack]) -> [LidSoundItem] {
        var settled = items
        for (index, item) in settled.enumerated() where item.fromManifest && item.packID == LidSoundPack.startersID {
            if let pack = manifest.first(where: { pack in pack.starters.contains { item.samePart(file: $0.file, from: $0.from ?? 0, to: $0.to) } }) {
                settled[index].packID = pack.id
            } else if let first = manifest.first {
                settled[index].packID = first.id
            }
        }
        return settled
    }

    /// The stage: what a close picks from, in the order In order walks.
    var onTheLid: [LidSoundItem] { items.filter(\.enabled) }
    /// One shelf: a pack's sounds, in list order.
    func shelf(_ packID: String) -> [LidSoundItem] { items.filter { $0.packID == packID } }
    func pack(_ id: String) -> LidSoundPack? { packs.first { $0.id == id } }

    /// A release can bring new packs and new sounds. Any pack the list does not have is added;
    /// any sound in the manifest the list does not have yet (the same file and part as a
    /// manifest sound) is added to its shelf, off the lid: what plays is the user's choice
    /// and a release does not make it for them. A cut of the user's own that is a manifest
    /// sound by name and part (the author's cuts, made before the pack existed) is not
    /// doubled: it is claimed by the pack and moves there out of Mine. Only a cut: a whole
    /// file that happens to share a name is the user's and stays where it is. A pack the
    /// user made keeps what they put in it.
    func adoptNewPacks(_ manifest: [LidSoundLibrary.ManifestPack]) {
        let userPacks = packs.filter { !$0.bundled }
        var added: [LidSoundItem] = []
        var claimed = items
        for pack in manifest {
            for starter in pack.starters {
                let from = starter.from ?? 0, to = starter.to
                let sameClip: (LidSoundItem) -> Bool = { item in
                    abs(item.clipStart - from) < 0.01 && ((item.clipEnd == nil && to == nil) || abs((item.clipEnd ?? -1) - (to ?? -1)) < 0.01)
                }
                if claimed.contains(where: { $0.fromManifest && $0.samePart(file: starter.file, from: from, to: to) }) { continue }
                if let own = claimed.firstIndex(where: { $0.isCut && $0.displayName == starter.name && sameClip($0) }) {
                    if claimed[own].packID == LidSoundPack.mineID { claimed[own].packID = pack.id }
                    continue
                }
                added.append(starter.item(onLid: false))
            }
        }
        packs = userPacks + manifest.map(\.pack)
        if claimed != items || !added.isEmpty { items = claimed + added }
        settlePacks(against: manifest)
    }

    func update(_ item: LidSoundItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}
