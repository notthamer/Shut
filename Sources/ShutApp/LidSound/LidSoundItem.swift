import Foundation

/// One sound: a starter that ships with the app, or a file the user added. Own files live
/// in Shut's Sounds folder under `fileName`; starters resolve into the resource bundle. A
/// starter is never deleted: taken off the lid, it waits on its shelf.
struct LidSoundItem: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var displayName: String
    /// On the lid: in the short list a close picks from. Off, the sound waits on its shelf.
    var enabled: Bool
    var isStarter: Bool
    /// 0.4.0's "removed starter". Read for the migration, never set again.
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
    /// Listed in the app's own starters.json: it has no file to delete and cannot be removed,
    /// only taken off the lid. A part the user cut from a starter is theirs, and goes when removed.
    var fromManifest = false
    /// The pack this sound belongs to (`LidSoundPack.id`).
    var packID: String = LidSoundPack.mineID
    /// 0.4.0's "kept for later". Read for the migration, never set again.
    var kept = false

    /// Older lists have no `fromManifest`, `packID` or `kept`: a whole starter was from the
    /// manifest, a cut was not; a manifest sound's pack is settled against the manifest at
    /// launch (`LidSoundSettings.settlePacks`), everything else is Mine.
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
        packID = try c.decodeIfPresent(String.self, forKey: .packID) ?? (fromManifest ? LidSoundPack.startersID : LidSoundPack.mineID)
        kept = try c.decodeIfPresent(Bool.self, forKey: .kept) ?? false
    }

    init(id: UUID, fileName: String, displayName: String, enabled: Bool, isStarter: Bool, hidden: Bool = false,
         duration: TimeInterval? = nil, contentHash: String? = nil, clipStart: TimeInterval = 0, clipEnd: TimeInterval? = nil,
         isCut: Bool = false, fromManifest: Bool = false, packID: String = LidSoundPack.mineID, kept: Bool = false) {
        self.id = id; self.fileName = fileName; self.displayName = displayName; self.enabled = enabled; self.isStarter = isStarter
        self.hidden = hidden; self.duration = duration; self.contentHash = contentHash; self.clipStart = clipStart; self.clipEnd = clipEnd
        self.isCut = isCut; self.fromManifest = fromManifest; self.packID = packID; self.kept = kept
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

    /// The same file and the same part.
    func samePart(file: String, from: TimeInterval, to: TimeInterval?) -> Bool {
        guard fileName == file, abs(clipStart - from) < 0.01 else { return false }
        if clipEnd == nil && to == nil { return true }
        return abs((clipEnd ?? -1) - (to ?? -1)) < 0.01
    }
}
