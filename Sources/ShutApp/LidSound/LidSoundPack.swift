import Foundation

/// A named group of sounds. Bundled packs come from `Resources/Sounds/starters.json` and
/// cannot be deleted, only hidden; the user's own sounds live in "Mine", and the user can
/// make more. A sound belongs to exactly one pack; the library is not a pack but a state
/// of a sound (`LidSoundItem.kept`).
struct LidSoundPack: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var bundled: Bool
    /// Where a bundled pack's audio came from, written beside it (rule 6).
    var credit: String?
    var hidden = false

    static let mineID = "mine"
    static let mine = LidSoundPack(id: mineID, name: "Mine", bundled: false)
    /// Where an older list's starters land when the manifest has no pack for them.
    static let startersID = "starters"
}
