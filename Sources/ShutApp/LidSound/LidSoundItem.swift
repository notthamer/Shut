import Foundation

/// One sound in the list: a starter that ships with the app, or a file the user added. Own
/// files live in Shut's Sounds folder under `fileName`; starters resolve into the resource
/// bundle. A starter is never deleted, only hidden, so "Restore the starter sounds" can.
struct LidSoundItem: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var displayName: String
    var enabled: Bool
    var isStarter: Bool
    var hidden = false
    /// Seconds, read once at import (starters: once at first launch). nil until known.
    var duration: TimeInterval?
    /// SHA-256 of the file's bytes, so the same file added twice is one row.
    var contentHash: String?
    /// A long file plays from here, in seconds: the clip the user chose.
    var clipStart: TimeInterval = 0

    /// Longer than the lid will ever play: it gets a clip.
    var isLong: Bool { (duration ?? 0) > LidSoundLibrary.clipLength }
}
