import AVFAudio
import CryptoKit
import Foundation

/// The sound files: the starters in the resource bundle, the user's own in
/// `~/Library/Application Support/Shut/Sounds`. Files are copied in at import, so the
/// original can move or go; nothing here is ever read while idle.
final class LidSoundLibrary {
    /// The most the lid ever plays of a file: a close is a second or two; thirty is generous.
    /// A longer file is not refused, it is clipped: it plays from where the user chooses, for
    /// this long at most.
    static let clipLength: TimeInterval = 30
    /// The longest file that is still worth copying in. A song is fine; an album is not.
    static let longest: TimeInterval = 600
    /// The shortest part worth cutting out.
    static let shortestCut: TimeInterval = 0.5

    let directory: URL
    private let bundle: Bundle?
    /// Files that failed to open since launch, so the page can say so without retrying.
    private(set) var unreadable: Set<UUID> = []

    enum FileState: Equatable { case ok, missing, unreadable }

    enum ImportError: Error, Equatable {
        case unreadable
        case tooLong(TimeInterval)
        case duplicate(of: UUID)
        case copyFailed
    }

    init(directory: URL? = nil, bundle: Bundle? = AppAssets.resourceBundle()) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shut", isDirectory: true).appendingPathComponent("Sounds", isDirectory: true)
        self.bundle = bundle
    }

    // MARK: Where a sound is

    /// The starters the bundle really has: `--self-check` counts them.
    func starterURLs() -> [URL] {
        LidSoundSettings.starters.compactMap { starterURL($0.file) }
    }

    private func starterURL(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        return bundle?.url(forResource: "Resources/Sounds/\(name)", withExtension: ext)
            ?? bundle?.url(forResource: "Sounds/\(name)", withExtension: ext)
            ?? bundle?.url(forResource: name, withExtension: ext)
    }

    func url(for item: LidSoundItem) -> URL? {
        item.isStarter ? starterURL(item.fileName) : directory.appendingPathComponent(item.fileName)
    }

    func state(of item: LidSoundItem) -> FileState {
        if unreadable.contains(item.id) { return .unreadable }
        guard let url = url(for: item), FileManager.default.fileExists(atPath: url.path) else { return .missing }
        return .ok
    }

    func markUnreadable(_ item: LidSoundItem) { unreadable.insert(item.id) }

    /// The sounds a close may pick from: switched on, not hidden, and on disk.
    func candidates(_ items: [LidSoundItem]) -> [LidSoundItem] {
        items.filter { $0.enabled && !$0.hidden && state(of: $0) == .ok }
    }

    // MARK: Import and remove

    /// The duration, by opening the file for reading. nil when Core Audio cannot.
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// The sound's shape: the loudest moment in each of `buckets` slices of the file, 0…1,
    /// so a part can be chosen by eye. Read once, kept in memory, never written anywhere.
    static func peaks(of url: URL, buckets: Int) -> [Float]? {
        guard buckets > 0, let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let total = Int(file.length)
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(min(total, 65_536))) else { return nil }
        let perBucket = max(1, Int((Double(total) / Double(buckets)).rounded(.up)))
        var peaks = [Float](repeating: 0, count: buckets)
        var frame = 0
        while frame < total {
            do { try file.read(into: buffer) } catch { break }
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            for i in 0..<count {
                let bucket = min(buckets - 1, (frame + i) / perBucket)
                var loudest: Float = 0
                for channel in 0..<Int(format.channelCount) { loudest = max(loudest, abs(channels[channel][i])) }
                if loudest > peaks[bucket] { peaks[bucket] = loudest }
            }
            frame += count
        }
        let top = peaks.max() ?? 0
        return top > 0 ? peaks.map { $0 / top } : peaks
    }

    static func hash(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Validates and copies one file in. `existing` is the list as it is, for the name and
    /// the duplicate check; the returned item is for the caller to append.
    func importFile(_ source: URL, existing: [LidSoundItem]) -> Result<LidSoundItem, ImportError> {
        guard let duration = Self.duration(of: source) else { return .failure(.unreadable) }
        guard duration <= Self.longest else { return .failure(.tooLong(duration)) }
        let hash = Self.hash(of: source)
        if let hash, let same = existing.first(where: { $0.contentHash == hash && !$0.hidden && !$0.isCut }) { return .failure(.duplicate(of: same.id)) }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let name = Self.uniqueName(base, among: existing.map(\.displayName))
        let fileName = "\(name).\(ext)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            return .failure(.copyFailed)
        }
        return .success(LidSoundItem(id: UUID(), fileName: fileName, displayName: name, enabled: true, isStarter: false,
                                     duration: duration, contentHash: hash))
    }

    /// "Rain", then "Rain 2", "Rain 3": a name says which file it is, so two never share one.
    static func uniqueName(_ base: String, among names: [String]) -> String {
        let taken = Set(names.map { $0.lowercased() })
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        let candidate = trimmed.isEmpty ? "Sound" : trimmed
        guard taken.contains(candidate.lowercased()) else { return candidate }
        var n = 2
        while taken.contains("\(candidate) \(n)".lowercased()) { n += 1 }
        return "\(candidate) \(n)"
    }

    /// An own file lives as long as any row plays it, the source or a part cut from it: the
    /// last of them to go takes the file with it. A starter is for the caller to hide.
    func remove(_ item: LidSoundItem, keptBy others: [LidSoundItem] = []) {
        unreadable.remove(item.id)
        guard !item.isStarter, let url = url(for: item) else { return }
        guard !others.contains(where: { $0.id != item.id && $0.fileName == item.fileName }) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    enum CutError: Error, Equatable { case tooShort, outside }

    /// A part of a sound as a sound of its own: the same file, from `from` to `to`.
    static func cut(_ source: LidSoundItem, from: TimeInterval, to: TimeInterval, name: String, existing: [LidSoundItem]) -> Result<LidSoundItem, CutError> {
        guard let duration = source.duration, from >= 0, to <= duration + 0.01 else { return .failure(.outside) }
        guard to - from >= shortestCut else { return .failure(.tooShort) }
        let name = uniqueName(name, among: existing.map(\.displayName))
        return .success(LidSoundItem(id: UUID(), fileName: source.fileName, displayName: name, enabled: true, isStarter: source.isStarter,
                                     duration: duration, contentHash: nil, clipStart: from, clipEnd: min(to, duration), isCut: true))
    }

    // MARK: Picking

    /// Which sound this close plays. Random never repeats the previous pick when there is a
    /// choice; in order carries on from `nextIndex`, wrapping, whatever was removed since.
    /// `random` is injectable so a test can say what the dice rolled.
    static func pick(from candidates: [LidSoundItem], mode: LidSoundSettings.Mode, lastPickID: UUID?, nextIndex: Int,
                     random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> (item: LidSoundItem, nextIndex: Int)? {
        guard !candidates.isEmpty else { return nil }
        switch mode {
        case .random:
            let fresh = candidates.count > 1 ? candidates.filter { $0.id != lastPickID } : candidates
            let item = fresh[random(fresh.count)]
            return (item, nextIndex)
        case .inOrder:
            let index = ((nextIndex % candidates.count) + candidates.count) % candidates.count
            return (candidates[index], (index + 1) % candidates.count)
        }
    }
}
