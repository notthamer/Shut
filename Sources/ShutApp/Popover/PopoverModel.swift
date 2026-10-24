import AppKit
import Combine
import LidSensor
import SwiftUI
import TransitionKit
import Tuner

/// Everything the popover reads and every action it can take, so the view stays
/// declarative and can be rendered in a test without a running app.
@MainActor
final class PopoverModel: ObservableObject {
    let settings: AppSettings
    let registry: TransitionRegistry
    let preview: PreviewModel
    let sensor: LidSensorMonitor
    let thumbnails: TransitionThumbnailRenderer?
    let stayAwake: StayAwakeController
    let lidSound: LidSoundController
    let sleep: SleepWatch

    /// Actions supplied by the app; tests pass no-ops.
    var openTuner: () -> Void = {}
    var openWindow: () -> Void = {}
    /// "What's new" behind the gear: the same card the menu bar menu opens.
    var showWhatsNew: () -> Void = {}
    var quit: () -> Void = { DispatchQueue.main.async { NSApp.terminate(nil) } }
    var allowScreenRecording: () -> Void = {}
    var relaunch: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var launchAtLogin: () -> Bool = { false }
    /// nil when there is no updater (a build not signed for release): the switch is hidden.
    var automaticUpdates: () -> Bool? = { nil }
    var setAutomaticUpdates: (Bool) -> Void = { _ in }
    var checkForUpdates: () -> Void = {}
    /// The featured dials for a style, drawn with Tuner rows.
    var featuredDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// The rest of a style's dials, grouped in folders, for "All dials".
    var moreDials: (String) -> AnyView = { _ in AnyView(EmptyView()) }
    /// Presets, copy, paste, import and export for a style.
    var shareView: (String, Binding<Bool>) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var resetStyle: (String) -> Void = { _ in }

    /// The panel has three pages of the same size: the lid styles, Stay awake, and Lid sound.
    enum Page { case styles, awake, sound }
    @Published var page: Page = .styles
    @Published var showingAwakeConsent = false

    @Published var stateDescription = "idle"
    @Published var thumbnailGeneration = 0
    /// Per-style counters so a changed dial re-draws one card, not the grid.
    @Published private(set) var thumbnailVersions: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Tests pass no `stayAwake` or `lidSound` and get ones on throwaway defaults that are never started.
    init(settings: AppSettings, registry: TransitionRegistry, preview: PreviewModel, sensor: LidSensorMonitor,
         thumbnails: TransitionThumbnailRenderer?, stayAwake: StayAwakeController? = nil, lidSound: LidSoundController? = nil,
         sleep: SleepWatch? = nil) {
        self.sleep = sleep ?? SleepWatch(defaults: UserDefaults(suiteName: "Sleep-\(UUID().uuidString)") ?? .standard, powerLog: { nil })
        self.stayAwake = stayAwake ?? StayAwakeController(
            settings: StayAwakeSettings(defaults: UserDefaults(suiteName: "StayAwake-\(UUID().uuidString)") ?? .standard))
        self.lidSound = lidSound ?? LidSoundController(
            settings: LidSoundSettings(defaults: UserDefaults(suiteName: "LidSound-\(UUID().uuidString)") ?? .standard),
            appSettings: settings, sensor: sensor, hasLid: self.stayAwake.hasLid,
            library: LidSoundLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("LidSound-\(UUID().uuidString)")))
        self.settings = settings
        self.registry = registry
        self.preview = preview
        self.sensor = sensor
        self.thumbnails = thumbnails
        registry.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Thumbnails draw over the real desktop once we have one.
        preview.onRealSnapshot = { [weak self] image in
            guard let self, let thumbnails = self.thumbnails else { return }
            if let small = Self.downscale(image, to: PlaceholderDesktop.defaultSize),
               (try? thumbnails.setBackdrop(small, isPlaceholder: false)) != nil {
                self.thumbnailGeneration += 1
                for t in self.registry.all { self.thumbnailVersions[t.id, default: 0] += 1 }
            }
        }
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        self.stayAwake.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        self.lidSound.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        self.sleep.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sensor.$capability.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    /// The status line's button. The first switch-on opens the page and explains itself.
    func performAwake(_ action: AwakeText.Action) {
        if action == .turnOn, stayAwake.needsConsent {
            page = .awake
            showingAwakeConsent = true
        } else {
            stayAwake.perform(action)
        }
    }

    func toggleAwake() {
        if stayAwake.needsConsent { showingAwakeConsent = true }
        else { stayAwake.settings.isOn.toggle() }
    }

    // MARK: Lid sound

    /// Where an added sound goes: onto the lid (and into Mine, since every sound has a pack),
    /// or into one pack, where it waits off the lid like anything else put in a playlist.
    enum SoundDestination: Equatable {
        case lid
        case pack(LidSoundPack)
        var packID: String { if case .pack(let pack) = self { return pack.id } else { return LidSoundPack.mineID } }
        var packName: String? { if case .pack(let pack) = self { return pack.name } else { return nil } }
        var onLid: Bool { self == .lid }
    }
    /// "Add a sound…": the file panel, supplied by the app (a test leaves it empty).
    var addSounds: (SoundDestination) -> Void = { _ in }
    /// The folded Settings on the Lid sound page.
    @Published var showingSoundSettings = false
    /// One line under the list after an import that was refused; nil when there is none.
    @Published var importNote: String?
    /// A row whose cut editor is open, for a test that draws the page.
    @Published var cuttingSoundForTest: UUID?
    /// The pack open under Packs, one at a time; nil when all are closed.
    @Published var openPackID: String?
    /// The folded Timing under the stage.
    @Published var showingSoundTiming = false
    /// "From Shut" is open: the packs that came with the app, under the user's own.
    @Published var showingBundledPacks = false
    /// Edit, on the stage: a mark beside each row, and the marked ones come off the lid at once.
    @Published var editingStage = false { didSet { if !editingStage { stageSelection = [] } } }
    @Published var stageSelection: Set<UUID> = []
    /// A drag from a pack is in flight: the stage says "Drop here" before the pointer reaches
    /// it. Set when the drag starts; cleared by the drop, or by the first pointer movement the
    /// page sees after the drag (a drag session owns the pointer while it lasts).
    @Published var dragging = false
    var draggingSince: Date = .distantPast

    func dragBegan() { dragging = true; draggingSince = Date() }
    func dragEnded() { if dragging { dragging = false } }
    /// Pointer movement over the page: a drag that ended somewhere else is over. The first
    /// moments after the start are ignored, since one event can slip in before the session
    /// takes the pointer.
    func pointerMoved() { if dragging, Date().timeIntervalSince(draggingSince) > 0.4 { dragging = false } }

    /// In order: the sound the next close plays, if there is one.
    var nextOnLid: LidSoundItem? {
        guard lidSound.settings.mode == .inOrder else { return nil }
        let candidates = lidSound.candidates
        guard !candidates.isEmpty else { return nil }
        let index = ((lidSound.settings.nextIndex % candidates.count) + candidates.count) % candidates.count
        return candidates[index]
    }

    /// Random: the one that played last, so the rotation can be seen moving.
    var lastPlayedOnLid: LidSoundItem? {
        guard lidSound.settings.mode == .random, let id = lidSound.settings.lastPickID else { return nil }
        return stage.first { $0.id == id }
    }

    /// "Play this next": In order carries on from this row.
    func playNext(_ item: LidSoundItem) {
        guard let index = lidSound.candidates.firstIndex(where: { $0.id == item.id }) else { return }
        lidSound.settings.nextIndex = index
    }

    /// Once a sound has been put on the lid by hand, the hint that says how is done.
    private func notePutOnLid() { if !lidSound.settings.hasPutOnLid { lidSound.settings.hasPutOnLid = true } }
    /// "New pack…" was chosen for this sound: a name is being typed for the pack.
    @Published var newPackFor: UUID?

    /// The stage: what a close picks from, in the order In order walks.
    var stage: [LidSoundItem] { lidSound.settings.onTheLid }

    /// The sounds on a shelf, in list order.
    func shelf(_ packID: String) -> [LidSoundItem] { lidSound.settings.shelf(packID) }

    /// + and ✓: a sound onto the lid, or off it, onto its shelf. Nothing else about it changes.
    func setOnLid(_ item: LidSoundItem, _ on: Bool) {
        guard item.enabled != on else { return }
        var changed = item; changed.enabled = on
        lidSound.settings.update(changed)
        if on { notePutOnLid() }
    }

    /// "Add all" / "Take all off" under an open pack: every sound in it, at once.
    func setShelf(_ pack: LidSoundPack, onLid: Bool) {
        lidSound.settings.items = lidSound.settings.items.map { var item = $0; if item.packID == pack.id { item.enabled = onLid }; return item }
        if onLid { notePutOnLid() }
    }

    func toggleStageSelection(_ id: UUID) {
        if stageSelection.contains(id) { stageSelection.remove(id) } else { stageSelection.insert(id) }
    }

    /// Every row on the stage ticked, or none.
    func selectWholeStage(_ all: Bool) { stageSelection = all ? Set(stage.map(\.id)) : [] }

    /// Edit's one action: the ticked sounds off the lid, back in their packs; then Edit is done.
    func removeSelectedFromLid() {
        let chosen = stageSelection
        lidSound.settings.items = lidSound.settings.items.map { var item = $0; if chosen.contains(item.id) { item.enabled = false }; return item }
        editingStage = false
    }

    /// A whole pack dropped on the stage at `index`: every sound in it onto the lid, together,
    /// in list order, at that place among the sounds already there. Ones of the pack's that
    /// were on the lid already move into the group.
    func putPackOnLid(_ packID: String, at index: Int) {
        var items = lidSound.settings.items
        guard items.contains(where: { $0.packID == packID }) else { return }
        // Where in the rest of the stage the group goes: the gap counted rows of this pack too.
        let stageBefore = items.filter(\.enabled)
        let target = stageBefore.prefix(max(0, min(index, stageBefore.count))).filter { $0.packID != packID }.count
        for i in items.indices where items[i].packID == packID { items[i].enabled = true }
        let pack = items.filter { $0.packID == packID }   // after the switch-on, so each is written back on
        let slots = items.indices.filter { items[$0].enabled }
        let others = slots.map { items[$0] }.filter { $0.packID != packID }
        let stage = Array(others.prefix(target)) + pack + Array(others.dropFirst(target))
        for (slot, item) in zip(slots, stage) { items[slot] = item }
        lidSound.settings.items = items
        notePutOnLid()
    }

    /// "Play this pack": the stage becomes exactly this pack, in list order, the way choosing
    /// a playlist replaces what was playing.
    func playOnly(_ pack: LidSoundPack) {
        lidSound.settings.items = lidSound.settings.items.map { var item = $0; item.enabled = item.packID == pack.id; return item }
        notePutOnLid()
    }

    /// A sound dropped on the stage at `index` (a place between its rows, 0…count): onto the
    /// lid if it was not, and into that place among the sounds that are. The sounds on their
    /// shelves keep their places in the list.
    func putOnLid(_ id: UUID, at index: Int) {
        var items = lidSound.settings.items
        guard let at = items.firstIndex(where: { $0.id == id }) else { return }
        let wasOnLid = items[at].enabled
        items[at].enabled = true
        let slots = items.indices.filter { items[$0].enabled }
        var stage = slots.map { items[$0] }
        guard let from = stage.firstIndex(where: { $0.id == id }) else { return }
        var to = index
        if wasOnLid, index > from { to -= 1 }   // the gap counted the row itself
        to = max(0, min(stage.count - 1, to))
        stage.insert(stage.remove(at: from), at: to)
        for (slot, item) in zip(slots, stage) { items[slot] = item }
        lidSound.settings.items = items
        notePutOnLid()
    }

    func moveSound(_ item: LidSoundItem, to packID: String) {
        guard lidSound.settings.pack(packID) != nil else { return }
        var moved = item; moved.packID = packID
        lidSound.settings.update(moved)
    }

    /// A pack of the user's own. The name is theirs; the id is not shown.
    @discardableResult
    func newPack(named name: String) -> LidSoundPack? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let unique = LidSoundLibrary.uniqueName(trimmed, among: lidSound.settings.packs.map(\.name))
        let pack = LidSoundPack(id: "user-" + UUID().uuidString, name: unique, bundled: false)
        // After the user's other packs, before the bundled ones: the user's lead the list.
        let packs = lidSound.settings.packs
        lidSound.settings.packs.insert(pack, at: packs.firstIndex(where: \.bundled) ?? packs.endIndex)
        return pack
    }

    func renamePack(_ pack: LidSoundPack, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !pack.bundled, !trimmed.isEmpty, let index = lidSound.settings.packs.firstIndex(where: { $0.id == pack.id }) else { return }
        lidSound.settings.packs[index].name = LidSoundLibrary.uniqueName(trimmed, among: lidSound.settings.packs.filter { $0.id != pack.id }.map(\.name))
    }

    /// A user's pack goes, its sounds to Mine, never deleted. A bundled pack and Mine stay:
    /// they are shelves, and a shelf is not something to remove.
    func removePack(_ pack: LidSoundPack) {
        guard !pack.bundled, pack.id != LidSoundPack.mineID else { return }
        lidSound.settings.items = lidSound.settings.items.map { var item = $0; if item.packID == pack.id { item.packID = LidSoundPack.mineID }; return item }
        lidSound.settings.packs.removeAll { $0.id == pack.id }
        if openPackID == pack.id { openPackID = nil }
    }

    /// Copies the files in, to the lid or into a pack, and says, once, why any was refused.
    func importSounds(_ urls: [URL], to destination: SoundDestination = .lid) {
        var notes: [String] = []
        for url in urls {
            switch lidSound.library.importFile(url, existing: lidSound.settings.items) {
            case .success(let imported):
                var item = imported
                item.packID = destination.packID
                item.enabled = destination.onLid
                lidSound.settings.items.append(item)
                if item.isLong, let duration = item.duration { notes.append(LidSoundText.longNote(name: item.displayName, seconds: duration)) }
            case .failure(let error):
                var duplicateOf: String?
                if case .duplicate(let id) = error { duplicateOf = lidSound.settings.items.first { $0.id == id }?.displayName }
                notes.append(LidSoundText.refusal(error, name: url.lastPathComponent, duplicateOf: duplicateOf))
            }
        }
        importNote = notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    /// Remove: an own file is deleted, with its row. A bundled sound has nothing to delete
    /// and cannot leave the app: it comes off the lid and waits on its shelf.
    func removeSound(_ item: LidSoundItem) {
        lidSound.library.remove(item, keptBy: lidSound.settings.items)
        if item.fromManifest {
            setOnLid(item, false)
        } else {
            lidSound.settings.items.removeAll { $0.id == item.id }
        }
    }

    /// A part of a sound, as a sound of its own, placed right under its source.
    func cutSound(_ source: LidSoundItem, from: TimeInterval, to: TimeInterval, name: String) {
        switch LidSoundLibrary.cut(source, from: from, to: to, name: name, existing: lidSound.settings.items) {
        case .success(let part):
            var items = lidSound.settings.items
            let at = (items.firstIndex { $0.id == source.id } ?? items.count - 1) + 1
            items.insert(part, at: min(at, items.count))
            lidSound.settings.items = items
            importNote = nil
        case .failure(let error):
            importNote = LidSoundText.cutRefusal(error)
        }
    }

    /// Several parts of one sound at once, each named, in order under the source.
    func cutSounds(_ source: LidSoundItem, parts: [(range: ClosedRange<TimeInterval>, name: String)]) {
        var items = lidSound.settings.items
        var at = (items.firstIndex { $0.id == source.id } ?? items.count - 1) + 1
        var refusals: [String] = []
        for part in parts {
            let name = part.name.trimmingCharacters(in: .whitespaces)
            switch LidSoundLibrary.cut(source, from: part.range.lowerBound, to: part.range.upperBound,
                                       name: name.isEmpty ? LidSoundText.cutName(of: source.displayName, from: part.range.lowerBound, to: part.range.upperBound) : name,
                                       existing: items) {
            case .success(let item): items.insert(item, at: min(at, items.count)); at += 1
            case .failure(let error): refusals.append(LidSoundText.cutRefusal(error))
            }
        }
        lidSound.settings.items = items
        var seen: Set<String> = []
        importNote = refusals.isEmpty ? nil : refusals.filter { seen.insert($0).inserted }.joined(separator: " ")
    }

    /// The name on the row, the user's; never two the same.
    func renameSound(_ item: LidSoundItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.displayName else { return }
        var renamed = item
        renamed.displayName = LidSoundLibrary.uniqueName(trimmed, among: lidSound.settings.items.filter { $0.id != item.id }.map(\.displayName))
        lidSound.settings.update(renamed)
    }

    /// A row carried to a new place on the lid, by its position there. The sounds on the lid
    /// take one another's places in the list; the ones on their shelves stay where they are.
    func moveSound(from: Int, to: Int) {
        var items = lidSound.settings.items
        let slots = items.indices.filter { items[$0].enabled }
        var stage = slots.map { items[$0] }
        guard stage.indices.contains(from), stage.indices.contains(to), from != to else { return }
        stage.insert(stage.remove(at: from), at: to)
        for (slot, item) in zip(slots, stage) { items[slot] = item }
        lidSound.settings.items = items
    }

    /// "Try it": the sound the next close would play, and the close itself in the preview.
    func tryTheSound() {
        lidSound.playClosePreview()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preview.glide(to: registry.current.thumbnailProgress)
        } else {
            preview.playRound()
        }
    }

    /// Seconds since the last close's sleep began, while it has not finished.
    func sleepPendingSeconds(now: Date = Date()) -> Int? {
        sleep.pendingSince.map { Int(now.timeIntervalSince($0).rounded()) }
    }

    /// Everything the Lid sound words need, with what the sleep watcher knows.
    func lidSoundSituation(now: Date = Date()) -> LidSoundText.Situation {
        var situation = lidSound.situation()
        situation.sleepPendingSeconds = sleepPendingSeconds(now: now)
        situation.slowSleepers = sleep.slow?.names ?? []
        situation.sleepHeldBy = sleep.running.map(\.name)
        return situation
    }

    var lidSoundTabLine: String { LidSoundText.tabLine(lidSoundSituation()) }

    var statusLine: String {
        if !settings.isEnabled { return "Off" }
        if registry.isSubstituting { return "\(registry.current.displayName) needs Screen Recording" }
        if BuiltInDisplay.screen == nil, BuiltInDisplay.externalCount > 0 {
            return "Lid shut on an external display: nothing to play"
        }
        let base: String
        switch sensor.capability {
        case .continuousAngle: base = "Following the lid"
        case .lidStateOnly: base = "Plays when the lid closes"
        case .unsupported: return "Preview only: no lid sensor on this Mac"
        }
        return BuiltInDisplay.externalCount > 0 ? "\(base), on the built-in display" : base
    }

    /// Running and doing what it says: nothing the header needs to spell out. The
    /// permission card speaks for a style that is standing in, so that counts too.
    var statusIsOrdinary: Bool {
        guard settings.isEnabled else { return false }
        if BuiltInDisplay.screen == nil, BuiltInDisplay.externalCount > 0 { return false }
        return sensor.capability != .unsupported
    }

    /// The "Lid effects" tab's second line: the style and whether it is running, or why not.
    var lidEffectsLine: String {
        let style = registry.current.displayName
        if !settings.isEnabled { return "\(style) · Off" }
        if BuiltInDisplay.screen == nil, BuiltInDisplay.externalCount > 0 { return "Lid shut · nothing to play" }
        if registry.isSubstituting { return "\(style) · plain fade for now" }
        if sensor.capability == .unsupported { return "\(style) · preview only" }
        return "\(style) · On"
    }

    /// Set once "Allow…" has opened System Settings: from then on the card's next step is
    /// the restart macOS needs before the permission counts.
    @Published var askedForScreenRecording = false
    /// The list of apps under "An app is busy".
    @Published var showingAllowedApps = false
    /// The folded Settings on the Awake page.
    @Published var showingAwakeSettings = false {
        didSet { if showingAwakeSettings, !oldValue { stayAwake.startTheBatteryLevelFromTheChargeOnce() } }
    }

    var needsPermissionCard: Bool {
        registry.current.needsSnapshot && !registry.captureAvailable
    }

    /// Speed: 0 = slow (the whole close), 1 = fast (the last 20°).
    var speed: Double {
        get { 1 - (settings.bandDegrees - AppSettings.bandRange.lowerBound) / (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
        set { settings.bandDegrees = AppSettings.bandRange.upperBound - newValue * (AppSettings.bandRange.upperBound - AppSettings.bandRange.lowerBound) }
    }

    /// Where the effect really starts, in degrees above shut: the requested band
    /// after the calibration caps it under this lid's rest angle.
    var effectiveStartDegrees: Double {
        let range = sensor.calibration.animationRange(bandDegrees: settings.bandDegrees)
        return range.upperBound - range.lowerBound
    }

    func select(_ id: String) {
        guard let transition = registry.transition(id: id) else {
            Log.app.error("select: unknown style \(id, privacy: .public)")
            return
        }
        registry.select(id: id)
        settings.transitionID = id
        Log.app.info("style selected: \(id, privacy: .public)")
        // Every style is the untouched desktop at Open, so a pick would look like
        // nothing happened. Play the whole round, close and open, as if Play had
        // been pressed. Under Reduce Motion, glide to the recognisable frame instead.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preview.glide(to: transition.thumbnailProgress)
        } else {
            preview.playRound()
        }
    }

    func thumbnail(for transition: TransitionKit.AnyTransition) -> CGImage? {
        thumbnails?.image(for: transition)
    }

    private static func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func invalidateThumbnail(id: String) {
        thumbnails?.invalidate(id: id)
        thumbnailGeneration += 1
        thumbnailVersions[id, default: 0] += 1
    }

    func thumbnailVersion(for id: String) -> Int { thumbnailVersions[id] ?? 0 }
}
