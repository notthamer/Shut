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
    /// The part that plays, in seconds into the file: from here, and, when set, to here.
    var clipStart: TimeInterval = 0
    var clipEnd: TimeInterval?
    /// A part cut from another sound: it shares that sound's file and owns no file of its own.
    var isCut = false
    /// Listed in the app's own starters.json: removed, it is hidden and can be restored. A
    /// part the user cut from a starter is theirs, and goes when removed.
    var fromManifest = false

    /// Older lists have no `fromManifest`: a whole starter was from the manifest, a cut was not.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        displayName = try c.decode(String.self, forKey: .displayName)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        isStarter = try c.decode(Bool.self, forKey: .isStarter)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash)
        clipStart = try c.decodeIfPresent(TimeInterval.self, forKey: .clipStart) ?? 0
        clipEnd = try c.decodeIfPresent(TimeInterval.self, forKey: .clipEnd)
        isCut = try c.decodeIfPresent(Bool.self, forKey: .isCut) ?? false
        fromManifest = try c.decodeIfPresent(Bool.self, forKey: .fromManifest) ?? (isStarter && !isCut)
    }

    init(id: UUID, fileName: String, displayName: String, enabled: Bool, isStarter: Bool, hidden: Bool = false,
         duration: TimeInterval? = nil, contentHash: String? = nil, clipStart: TimeInterval = 0, clipEnd: TimeInterval? = nil,
         isCut: Bool = false, fromManifest: Bool = false) {
        self.id = id; self.fileName = fileName; self.displayName = displayName; self.enabled = enabled; self.isStarter = isStarter
        self.hidden = hidden; self.duration = duration; self.contentHash = contentHash; self.clipStart = clipStart; self.clipEnd = clipEnd
        self.isCut = isCut; self.fromManifest = fromManifest
    }

    /// What is heard, in seconds: the part, or the whole file.
    var heardLength: TimeInterval? {
        guard let duration else { return nil }
        let end = min(clipEnd ?? duration, duration)
        return max(0, end - clipStart)
    }

    /// Longer than the lid will ever play: it gets a start of its own.
    var isLong: Bool { (heardLength ?? 0) > LidSoundLibrary.clipLength }
    /// Long enough to cut a part from.
    var canCut: Bool { (duration ?? 0) >= LidSoundLibrary.shortestCut * 2 }
}
