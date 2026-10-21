import Foundation

/// A named shelf of sounds. Bundled packs come from `Resources/Sounds/starters.json` and are
/// always there to browse; the user's own sounds live in "Mine", and the user can make
/// more. A sound belongs to exactly one pack. Whether a sound plays is the sound's own
/// `enabled` (on the lid), never the pack's: a pack is a shelf, not a switch.
struct LidSoundPack: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var bundled: Bool
    /// Where a bundled pack's audio came from, written beside it (rule 6).
    var credit: String?

    private enum CodingKeys: String, CodingKey { case id, name, bundled, credit }

    static let mineID = "mine"
    static let mine = LidSoundPack(id: mineID, name: "Mine", bundled: false)
    /// Where an older list's starters land when the manifest has no pack for them.
    static let startersID = "starters"
}
