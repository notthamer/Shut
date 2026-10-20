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

    /// "Add a sound…": the file panel, supplied by the app (a test leaves it empty).
    var addSounds: () -> Void = {}
    /// The folded Settings on the Lid sound page.
    @Published var showingSoundSettings = false
    /// One line under the list after an import that was refused; nil when there is none.
    @Published var importNote: String?
    /// A row whose cut editor is open, for a test that draws the page.
    @Published var cuttingSoundForTest: UUID?
    /// The library, folded under the list.
    @Published var showingLibrary = false
    /// "New pack…" was chosen for this sound: a name is being typed for the pack.
    @Published var newPackFor: UUID?

    /// The rows, in pack order (bundled packs as the manifest lists them, then Mine, then
    /// the user's), each pack keeping its own order; with a pack chosen, that pack only.
    var displayedSounds: [LidSoundItem] {
        let settings = lidSound.settings
        let order = Dictionary(uniqueKeysWithValues: settings.packs.enumerated().map { ($1.id, $0) })
        var rows = settings.shown
        if case .pack(let id) = settings.playsFrom { rows = rows.filter { $0.packID == id } }
        return rows.enumerated().sorted { a, b in
            let pa = order[a.element.packID] ?? Int.max, pb = order[b.element.packID] ?? Int.max
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    /// Keep for later: out of the list and out of every pick, file and all kept.
    func keep(_ item: LidSoundItem) {
        var kept = item; kept.kept = true
        lidSound.settings.update(kept)
    }

    /// Back from the library, into its pack, switched on.
    func useAgain(_ item: LidSoundItem) {
        var back = item; back.kept = false; back.enabled = true
        if lidSound.settings.pack(back.packID) == nil || lidSound.settings.pack(back.packID)?.hidden == true { back.packID = LidSoundPack.mineID }
        lidSound.settings.update(back)
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
        lidSound.settings.packs.append(pack)
        return pack
    }

    func renamePack(_ pack: LidSoundPack, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !pack.bundled, !trimmed.isEmpty, let index = lidSound.settings.packs.firstIndex(where: { $0.id == pack.id }) else { return }
        lidSound.settings.packs[index].name = LidSoundLibrary.uniqueName(trimmed, among: lidSound.settings.packs.filter { $0.id != pack.id }.map(\.name))
    }

    /// A pack out of the list. A bundled one stays in the app, out of sight, and "Add a pack"
    /// brings it back; a user pack goes, its sounds to Mine, never deleted. Mine itself stays.
    func removePack(_ pack: LidSoundPack) {
        if pack.bundled { setPack(pack, hidden: true); return }
        guard pack.id != LidSoundPack.mineID else { return }
        lidSound.settings.items = lidSound.settings.items.map { var item = $0; if item.packID == pack.id { item.packID = LidSoundPack.mineID }; return item }
        lidSound.settings.packs.removeAll { $0.id == pack.id }
        if lidSound.settings.playsFrom == .pack(pack.id) { lidSound.settings.playsFrom = .all }
    }

    /// A bundled pack put away whole, or brought back.
    func setPack(_ pack: LidSoundPack, hidden: Bool) {
        guard pack.bundled, let index = lidSound.settings.packs.firstIndex(where: { $0.id == pack.id }) else { return }
        lidSound.settings.packs[index].hidden = hidden
        if hidden, lidSound.settings.playsFrom == .pack(pack.id) { lidSound.settings.playsFrom = .all }
    }

    /// Copies the files in and says, once, why any was refused.
    func importSounds(_ urls: [URL]) {
        var notes: [String] = []
        for url in urls {
            switch lidSound.library.importFile(url, existing: lidSound.settings.items) {
            case .success(let item):
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

    /// A row's ×: an own file is deleted, a starter is hidden so it can come back.
    func removeSound(_ item: LidSoundItem) {
        lidSound.library.remove(item, keptBy: lidSound.settings.items)
        if item.fromManifest {
            var hidden = item; hidden.hidden = true
            lidSound.settings.update(hidden)
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

    /// A row carried to a new place, by its position among the rows displayed. Landing among
    /// another pack's rows moves the sound into that pack. Rows not displayed (hidden, kept,
    /// another pack while one is chosen) keep out of the way at the end.
    func moveSound(from: Int, to: Int) {
        var rows = displayedSounds
        guard rows.indices.contains(from), rows.indices.contains(to), from != to else { return }
        var item = rows.remove(at: from)
        rows.insert(item, at: to)
        let neighbour = to > 0 ? rows[to - 1] : (rows.count > 1 ? rows[1] : nil)
        if let neighbour, neighbour.packID != item.packID { item.packID = neighbour.packID; rows[to] = item }
        let displayed = Set(rows.map(\.id))
        lidSound.settings.items = rows + lidSound.settings.items.filter { !displayed.contains($0.id) }
    }

    func restoreStarterSounds() {
        for var item in lidSound.settings.items where item.fromManifest && item.hidden {
            item.hidden = false; item.enabled = true
            lidSound.settings.update(item)
        }
        for pack in lidSound.settings.packs where pack.bundled && pack.hidden { setPack(pack, hidden: false) }
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
        return situation
    }

    var lidSoundTabLine: String { LidSoundText.tabLine(lidSoundSituation()) }

    var statusLine: String {
        if !settings.isEnabled { return "Paused" }
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
        if !settings.isEnabled { return "\(style) · Paused" }
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
