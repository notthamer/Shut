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

    /// Random never plays the same sound twice running; in order carries on from here.
    var lastPickID: UUID? { didSet { defaults.set(lastPickID?.uuidString, forKey: "lidSound.lastPickID") } }
    var nextIndex: Int { didSet { defaults.set(nextIndex, forKey: "lidSound.nextIndex") } }
    /// "Unmute for it" lifted the mute and has not put it back yet (the Mac may have slept
    /// first). Restored on the next launch or wake, on the same output device only.
    var muteToRestore: Bool { didSet { defaults.set(muteToRestore, forKey: "lidSound.muteToRestore") } }
    var muteToRestoreDeviceUID: String? { didSet { defaults.set(muteToRestoreDeviceUID, forKey: "lidSound.muteToRestoreDeviceUID") } }
    /// "Its own level" set the Mac's volume and has not put it back yet; the value owed.
    var volumeToRestore: Double? { didSet { defaults.set(volumeToRestore, forKey: "lidSound.volumeToRestore") } }

    /// The sounds that ship with the app, as `(display name, file in Resources/Sounds)`.
    nonisolated static let starters: [(name: String, file: String)] = [("Click", "Click.wav"), ("Breath", "Breath.wav"), ("Hum", "Hum.wav")]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        isOn = bool("lidSound.isOn", false)
        if let data = defaults.data(forKey: "lidSound.items"), let saved = try? JSONDecoder().decode([LidSoundItem].self, from: data) {
            items = saved
        } else {
            // First launch: the starters, switched on, so the first close has something to play.
            items = Self.starters.map { LidSoundItem(id: UUID(), fileName: $0.file, displayName: $0.name, enabled: true, isStarter: true) }
        }
        mode = defaults.string(forKey: "lidSound.mode").flatMap(Mode.init(rawValue:)) ?? .random
        volume = defaults.object(forKey: "lidSound.volume") as? Double ?? 0.7
        onOpen = bool("lidSound.onOpen", false)
        onOpenPick = OnOpenPick(stored: defaults.string(forKey: "lidSound.onOpenPick"))
        whenMuted = defaults.string(forKey: "lidSound.whenMuted").flatMap(WhenMuted.init(rawValue:)) ?? .stayQuiet
        // Its own level by default: the dial is the level heard, whatever the Mac is set to.
        volumeMode = defaults.string(forKey: "lidSound.volumeMode").flatMap(VolumeMode.init(rawValue:)) ?? .ownLevel
        startsWithEffect = bool("lidSound.startsWithEffect", true)
        startDegrees = defaults.object(forKey: "lidSound.startDegrees") as? Double ?? 60
        lastPickID = defaults.string(forKey: "lidSound.lastPickID").flatMap(UUID.init(uuidString:))
        nextIndex = defaults.integer(forKey: "lidSound.nextIndex")
        muteToRestore = defaults.bool(forKey: "lidSound.muteToRestore")
        muteToRestoreDeviceUID = defaults.string(forKey: "lidSound.muteToRestoreDeviceUID")
        volumeToRestore = defaults.object(forKey: "lidSound.volumeToRestore") as? Double
    }

    /// The rows on the page: everything that is not a hidden starter.
    var shown: [LidSoundItem] { items.filter { !$0.hidden } }

    func update(_ item: LidSoundItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}
