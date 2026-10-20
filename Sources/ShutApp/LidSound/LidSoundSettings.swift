import Combine
import Foundation

/// The Lid sound switches, backed by UserDefaults like `StayAwakeSettings`. Kept apart so
/// the feature can be read, tested and removed as one piece. Unlike Stay awake's one-close
/// arming, `isOn` here is a standing preference and is saved.
@MainActor
final class LidSoundSettings: ObservableObject {
    let defaults: UserDefaults

    enum Mode: String, Codable { case random, inOrder }
    enum WhenMuted: String, Codable { case stayQuiet, unmute }
    /// What the Volume dial means: a share of the Mac's volume as it is, or a level of its
    /// own that Shut sets the Mac to for the sound and puts back after.
    enum VolumeMode: String, Codable { case shareOfMac, ownLevel }
    /// What a close picks from: every pack, or one.
    enum PlaysFrom: Equatable {
        case all
        case pack(String)
        var stored: String { if case .pack(let id) = self { return id } else { return "all" } }
        var key: String { stored }
        init(stored: String?) { self = (stored == nil || stored == "all") ? .all : .pack(stored!) }
    }
    /// What "Also on open" plays: the close's pick again, or one sound in particular.
    enum OnOpenPick: Equatable {
        case samePick
        case item(UUID)
        var stored: String { if case .item(let id) = self { return id.uuidString } else { return "same" } }
        init(stored: String?) { self = stored.flatMap(UUID.init(uuidString:)).map(OnOpenPick.item) ?? .samePick }
    }

    @Published var isOn: Bool { didSet { defaults.set(isOn, forKey: "lidSound.isOn") } }
    /// The list, in the order shown. One blob, so a row's fields travel together.
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
    /// The packs: the user's own first, Mine leading, then the bundled ones as the manifest
    /// lists them (hidden or not). The user's sounds lead the list; what came with the app
    /// follows, as a phone lists your ringtones over its own. Only the user's packs and the
    /// hidden flags are saved.
    @Published var packs: [LidSoundPack] { didSet { savePacks() } }
    @Published var playsFrom: PlaysFrom { didSet { defaults.set(playsFrom.stored, forKey: "lidSound.playsFrom") } }
    /// In order carries on per scope, so switching packs and back does not lose the place.
    var nextIndexByScope: [String: Int] { didSet { defaults.set(try? JSONEncoder().encode(nextIndexByScope), forKey: "lidSound.nextIndexByScope") } }

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
        let firstLaunch: Bool
        let loaded: [LidSoundItem]
        if let data = defaults.data(forKey: "lidSound.items"), let saved = try? JSONDecoder().decode([LidSoundItem].self, from: data) {
            loaded = saved
            firstLaunch = false
        } else {
            // First launch: the starters, switched on, so the first close has something to play.
            loaded = manifest.flatMap(\.starters).map { $0.item() }
            firstLaunch = true
        }
        // An older list's manifest sounds find their pack first, so that a pack whose sounds
        // are in this list counts as listed below, whatever its flag says.
        let settled = firstLaunch ? loaded : Self.settled(loaded, against: manifest)
        items = settled
        // The packs: bundled from the manifest, with what the user decided about each saved
        // (in the list or out of it); a pack never seen before starts as the manifest says,
        // unless its sounds are already in this list. The user's own packs first.
        let hiddenBundled = Set(defaults.stringArray(forKey: "lidSound.hiddenPacks") ?? [])
        let shownBundled = Set(defaults.stringArray(forKey: "lidSound.shownPacks") ?? [])
        let userPacks = (defaults.data(forKey: "lidSound.packs")).flatMap { try? JSONDecoder().decode([LidSoundPack].self, from: $0) } ?? [LidSoundPack.mine]
        let listed = firstLaunch ? [] : Set(settled.map(\.packID))
        packs = (userPacks.contains { $0.id == LidSoundPack.mineID } ? userPacks : [LidSoundPack.mine] + userPacks) + manifest.map { entry in
            var pack = entry.pack
            if hiddenBundled.contains(pack.id) { pack.hidden = true }
            else if shownBundled.contains(pack.id) || listed.contains(pack.id) { pack.hidden = false }
            return pack
        }
        playsFrom = PlaysFrom(stored: defaults.string(forKey: "lidSound.playsFrom"))
        nextIndexByScope = (defaults.data(forKey: "lidSound.nextIndexByScope")).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
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
        lastPickID = defaults.string(forKey: "lidSound.lastPickID").flatMap(UUID.init(uuidString:))
        nextIndex = defaults.integer(forKey: "lidSound.nextIndex")
        muteToRestore = defaults.bool(forKey: "lidSound.muteToRestore")
        muteToRestoreDeviceUID = defaults.string(forKey: "lidSound.muteToRestoreDeviceUID")
        volumeToRestore = defaults.object(forKey: "lidSound.volumeToRestore") as? Double
    }

    private func savePacks() {
        defaults.set(try? JSONEncoder().encode(packs.filter { !$0.bundled }), forKey: "lidSound.packs")
        defaults.set(packs.filter { $0.bundled && $0.hidden }.map(\.id), forKey: "lidSound.hiddenPacks")
        defaults.set(packs.filter { $0.bundled && !$0.hidden }.map(\.id), forKey: "lidSound.shownPacks")
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

    /// The rows on the page: listed sounds, in packs that are not hidden, not kept for later.
    var shown: [LidSoundItem] {
        let hiddenPacks = hiddenPackIDs
        return items.filter { !$0.hidden && !$0.kept && !hiddenPacks.contains($0.packID) }
    }
    /// The library: saved for later, out of the list.
    var kept: [LidSoundItem] { items.filter { $0.kept && !$0.hidden } }
    var hiddenPackIDs: Set<String> { Set(packs.filter(\.hidden).map(\.id)) }
    /// The packs a sound can be moved to or played from: not hidden.
    var visiblePacks: [LidSoundPack] { packs.filter { !$0.hidden } }
    func pack(_ id: String) -> LidSoundPack? { packs.first { $0.id == id } }

    /// In order's place within a scope.
    func nextIndex(for scope: PlaysFrom) -> Int { nextIndexByScope[scope.key] ?? 0 }
    func setNextIndex(_ index: Int, for scope: PlaysFrom) { nextIndexByScope[scope.key] = index }

    /// A release can bring new packs and new sounds. Any pack the list does not have is added;
    /// any sound in the manifest the list does not have yet (the same file and part as a
    /// manifest sound) is added, switched on, at the end of its pack. Hidden ones stay hidden.
    /// A cut of the user's own that is a manifest sound by name and part (the author's
    /// cuts, made before the pack existed) is not doubled: it is claimed by the pack and
    /// moves there out of Mine, so the pack is in the list with its sounds, not offered
    /// empty beside them. Only a cut in the list: a whole file that happens to share a
    /// name, or a sound kept for later, is the user's and stays where it is. A pack the
    /// user made keeps what they put in it.
    func adoptNewPacks(_ manifest: [LidSoundLibrary.ManifestPack]) {
        let known = Dictionary(uniqueKeysWithValues: packs.filter(\.bundled).map { ($0.id, $0.hidden) })
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
                if let own = claimed.firstIndex(where: { $0.isCut && !$0.kept && !$0.hidden && $0.displayName == starter.name && sameClip($0) }) {
                    if claimed[own].packID == LidSoundPack.mineID { claimed[own].packID = pack.id }
                    continue
                }
                added.append(starter.item())
            }
        }
        let listed = Set(claimed.map(\.packID))
        packs = userPacks + manifest.map { entry in
            var pack = entry.pack
            if let decided = known[entry.id] { pack.hidden = decided }
            else if listed.contains(entry.id) { pack.hidden = false }
            return pack
        }
        let claimedSome = claimed != items
        if claimedSome || !added.isEmpty { items = claimed + added }
        settlePacks(against: manifest)
        // The claim can empty the pack that was chosen to play from: then every pack plays.
        // Only then: a pack the user emptied on purpose stays chosen.
        if claimedSome, case .pack(let id) = playsFrom, !shown.contains(where: { $0.packID == id }) { playsFrom = .all }
    }

    func update(_ item: LidSoundItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}
