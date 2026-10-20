import AppKit
import Combine
import Foundation
import LidSensor

/// The app's side of Lid sound: joins the settings, the files, the hinge and the lid
/// controller's two moments to one player, and is what the page, the tab and the menu read.
///
/// Nothing runs while idle. The player exists from the moment the lid starts to come down
/// until the sound ends; the output-device listener exists only while a window is open.
/// The one timer is a one-shot that ends a fade (`AVAudioPlayer` has no fade-complete
/// callback), and it exists only while a sound is fading.
@MainActor
final class LidSoundController: ObservableObject {
    let settings: LidSoundSettings
    let library: LidSoundLibrary
    let hasLid: Bool

    /// The name of the sound playing right now, for the glyph and the tab.
    @Published private(set) var playing: String?
    @Published private(set) var outputName: String?
    @Published private(set) var isMuted = false
    @Published private(set) var canUnmute = true
    @Published private(set) var canSetVolume = true
    /// The Mac's volume as last read, 0…1, for the page.
    @Published private(set) var macVolume: Float?

    private let appSettings: AppSettings
    private let sensor: LidSensorMonitor
    private let output: OutputMuting
    private let makePlayer: (URL) throws -> SoundPlaying
    /// A one-shot, injectable so a test can fire it by hand.
    private let after: (TimeInterval, @escaping () -> Void) -> DispatchWorkItem
    /// The hinge's capability, read when it matters; a test says what Mac it is on.
    private let capability: () -> HingeCapability

    private var cue = LidSoundCue()
    private var player: SoundPlaying?
    private var prepared: LidSoundItem?
    /// The opening's sound, made and prepared at wake so the audio hardware is awake before
    /// the desktop pours back in, not during it.
    private var warmOpening: (item: LidSoundItem, player: SoundPlaying)?
    private var fadeEnd: DispatchWorkItem?
    /// A long file's thirty seconds, counted from `play`.
    private var capEnd: DispatchWorkItem?
    private var liftedMute = false
    private var hingeSink: AnyCancellable?
    private var listener: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(settings: LidSoundSettings, appSettings: AppSettings, sensor: LidSensorMonitor, hasLid: Bool,
         library: LidSoundLibrary? = nil, output: OutputMuting? = nil,
         makePlayer: ((URL) throws -> SoundPlaying)? = nil,
         after: ((TimeInterval, @escaping () -> Void) -> DispatchWorkItem)? = nil,
         capability: (() -> HingeCapability)? = nil) {
        self.settings = settings
        self.appSettings = appSettings
        self.sensor = sensor
        self.hasLid = hasLid
        self.library = library ?? LidSoundLibrary()
        self.output = output ?? CoreAudioOutput()
        self.makePlayer = makePlayer ?? { try AudioPlayer(url: $0) }
        self.capability = capability ?? { [sensor] in sensor.capability }
        self.after = after ?? { seconds, work in
            let item = DispatchWorkItem(block: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
            return item
        }
    }

    func start() {
        restoreMuteIfOwed()
        // The starters' lengths, read once: three small files, the first time only.
        for var item in settings.items where item.duration == nil {
            if let url = library.url(for: item), let duration = LidSoundLibrary.duration(of: url) {
                item.duration = duration
                settings.update(item)
            }
        }
        // A sleep cut whatever was playing; the next close starts clean.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.cue.phase != .idle { Log.sound.notice("the Mac slept mid-sound") }
                self.cue.finished()
                self.dropPlayer()
                self.restoreMuteIfOwed()
                self.warmTheOpening()
            }
        }
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        appSettings.$isEnabled.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)
        apply()
    }

    /// Quit: the lid goes on without us, and the Mac's mute is as we found it.
    func shutDown() {
        fadeEnd?.cancel()
        dropPlayer()
        restoreMuteIfOwed()
        listener = nil
        hingeSink = nil
    }

    private func apply() {
        cue.playsOnHinge = !appSettings.isEnabled
        cue.landFades = capability() == .continuousAngle
        cue.startAngle = settings.startsWithEffect ? nil : settings.startDegrees
        let listening = settings.isOn && hasLid
        if listening, hingeSink == nil {
            hingeSink = sensor.$state.compactMap { $0 }.sink { [weak self] state in self?.hinge(state) }
        } else if !listening, hingeSink != nil {
            hingeSink = nil
            cue.finished()
            dropPlayer()
        }
        objectWillChange.send()
    }

    // MARK: From the hinge and the lid controller

    func hinge(_ state: HingeState) {
        guard settings.isOn else { return }
        lastAngle = state.angle
        perform(cue.hinge(progress: state.progress, direction: state.direction, angle: state.angle))
    }
    private var lastAngle: Double?

    /// Where the screen effect starts, in degrees above shut: Speed, on Lid effects, after
    /// the calibration caps it under this lid's rest angle.
    var effectStartDegrees: Double {
        let range = sensor.calibration.animationRange(bandDegrees: appSettings.bandDegrees)
        return range.upperBound - range.lowerBound
    }

    /// The angle the sound starts at, whichever way it is set.
    var startDegrees: Double { settings.startsWithEffect ? effectStartDegrees : settings.startDegrees }

    /// The lid has started to come down: wake the audio hardware now, not when it matters.
    func lidStartedClosing() {
        guard settings.isOn, cue.phase == .idle else { return }
        perform(cue.hinge(progress: LidSoundCue.armAt * 2, direction: .closing))
    }

    /// The overlay is appearing.
    func closeBeginning() {
        guard settings.isOn else { return }
        perform(cue.closeBeginning(startsAtOwnAngle: cue.startAngle != nil && lastAngle != nil))
    }

    /// The close ended without the lid shutting.
    func closeEnded(reason: String) {
        guard cue.phase != .idle else { return }
        Log.sound.info("close ended (\(reason, privacy: .public)) in phase \(String(describing: self.cue.phase), privacy: .public)")
        perform(cue.closeEnded())
    }

    /// What the opening would play right now, if anything.
    private func openingPick() -> LidSoundItem? {
        guard settings.isOn, settings.onOpen else { return nil }
        let candidates = library.candidates(settings.items)
        switch settings.onOpenPick {
        case .item(let id): return candidates.first { $0.id == id } ?? LidSoundLibrary.pick(from: candidates, mode: .random, lastPickID: nil, nextIndex: 0)?.item
        case .samePick: return candidates.first { $0.id == settings.lastPickID } ?? LidSoundLibrary.pick(from: candidates, mode: .random, lastPickID: nil, nextIndex: 0)?.item
        }
    }

    /// At wake: make and prepare the opening's sound now, off the main thread, so the
    /// hardware is ready before the unlock. Nothing is heard here.
    func warmTheOpening() {
        warmOpening = nil
        guard let item = openingPick(), let player = make(item) else { return }
        player.prepare()
        warmOpening = (item, player)
    }

    /// The desktop is pouring back in after the unlock (or would be, with Animate opening off).
    func openingBeginning() {
        guard let item = openingPick() else { return }
        if let warm = warmOpening, warm.item.id == item.id {
            warmOpening = nil
            playNow(item, reason: "opening", ready: warm.player)
        } else {
            playNow(item, reason: "opening")
        }
    }

    // MARK: From the page

    /// "Try it", and the Volume slider let go: the close's own pick, at the volume set.
    func playClosePreview() {
        let candidates = library.candidates(settings.items)
        guard let pick = LidSoundLibrary.pick(from: candidates, mode: settings.mode, lastPickID: settings.lastPickID, nextIndex: settings.nextIndex) else { return }
        playNow(pick.item, reason: "try it")
    }

    /// The ▶ beside a row.
    func preview(_ item: LidSoundItem) { playNow(item, reason: "preview") }

    /// The output-device listener, only while one of Shut's windows is open.
    func setLiveUpdates(_ open: Bool) {
        if open {
            readOutput()
            listener = output.listen { [weak self] in self?.readOutput() }
        } else {
            listener = nil
        }
    }

    private func readOutput() {
        outputName = output.deviceName
        isMuted = output.isMuted
        canUnmute = output.canSetMute
        canSetVolume = output.canSetVolume
        macVolume = output.volume
    }

    /// Everything the words need, gathered once.
    func situation() -> LidSoundText.Situation {
        let candidates = library.candidates(settings.items)
        var next: String?
        if settings.mode == .inOrder, let pick = LidSoundLibrary.pick(from: candidates, mode: .inOrder, lastPickID: nil, nextIndex: settings.nextIndex) {
            next = pick.item.displayName
        }
        return LidSoundText.Situation(isOn: settings.isOn, shownCount: settings.shown.count, candidates: candidates.map(\.displayName),
                                      mode: settings.mode, whenMuted: settings.whenMuted, muted: isMuted, canUnmute: canUnmute,
                                      playing: playing, outputName: outputName, onOpen: settings.onOpen,
                                      capability: capability(), next: next, startDegrees: Int(startDegrees.rounded()))
    }

    // MARK: Doing it

    private func perform(_ command: LidSoundCue.Command?) {
        guard let command else { return }
        switch command {
        case .prepare:
            let candidates = library.candidates(settings.items)
            guard let pick = LidSoundLibrary.pick(from: candidates, mode: settings.mode, lastPickID: settings.lastPickID, nextIndex: settings.nextIndex) else {
                cue.finished(); return
            }
            guard let player = make(pick.item) else { cue.finished(); return }
            player.prepare()
            prepared = pick.item
            self.player = player
        case .play:
            if player == nil, prepared == nil { perform(.prepare); guard player != nil else { return } }
            guard let player, let item = prepared else { cue.finished(); return }
            guard lift(forPlaying: item) else { cue.finished(); dropPlayer(); return }
            player.play()
            playing = item.displayName
            cap(item)
            settings.lastPickID = item.id
            if settings.mode == .inOrder {
                let candidates = library.candidates(settings.items)
                if let index = candidates.firstIndex(where: { $0.id == item.id }) { settings.nextIndex = (index + 1) % max(candidates.count, 1) }
            }
            Log.sound.info("playing \(item.displayName, privacy: .public)")
        case .fade(let seconds):
            guard let player else { cue.finished(); return }
            player.setVolume(0, fade: seconds)
            fadeEnd?.cancel()
            fadeEnd = after(seconds) { [weak self] in self?.finished() }
        case .drop:
            dropPlayer()
        }
    }

    /// A sound outside a close: the page's previews and the opening. One at a time: a
    /// close that begins while a preview plays takes over.
    private func playNow(_ item: LidSoundItem, reason: String, ready: SoundPlaying? = nil) {
        fadeEnd?.cancel()
        dropPlayer()
        cue.finished()
        guard let player = ready ?? make(item), lift(forPlaying: item) else { return }
        if ready == nil { player.prepare() }
        player.play()
        self.player = player
        prepared = item
        playing = item.displayName
        cap(item)
        Log.sound.info("playing \(item.displayName, privacy: .public) (\(reason, privacy: .public))")
    }

    private func make(_ item: LidSoundItem) -> SoundPlaying? {
        guard let url = library.url(for: item) else { return nil }
        do {
            let player = try makePlayer(url)
            player.volume = settings.volumeMode == .ownLevel && output.canSetVolume ? 1 : Float(settings.volume)
            if item.clipStart > 0 { player.seek(to: item.clipStart) }
            player.onFinish = { [weak self] in self?.finished() }
            return player
        } catch {
            library.markUnreadable(item)
            Log.sound.error("could not open \(item.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            objectWillChange.send()
            return nil
        }
    }

    /// Muted: with Stay quiet, nothing plays; with Unmute for it, the mute is lifted and owed
    /// back. The debt is written before the mute is touched, so a sleep in between still
    /// gets it repaid at the next launch.
    private func lift(forPlaying item: LidSoundItem) -> Bool {
        takeTheVolume()
        guard output.isMuted else { return true }
        guard settings.whenMuted == .unmute, output.canSetMute else {
            Log.sound.info("muted; staying quiet for \(item.displayName, privacy: .public)")
            return false
        }
        settings.muteToRestore = true
        settings.muteToRestoreDeviceUID = output.deviceUID
        liftedMute = output.setMuted(false)
        return liftedMute
    }

    /// A part stops at its end, and a long file after its thirty seconds, with the landing
    /// fade, however the lid is held. Whole short files end by themselves.
    private func cap(_ item: LidSoundItem) {
        capEnd?.cancel()
        capEnd = nil
        let length: TimeInterval
        if let end = item.clipEnd { length = min(max(0, end - item.clipStart), LidSoundLibrary.clipLength) }
        else if item.isLong { length = LidSoundLibrary.clipLength }
        else { return }
        capEnd = after(length) { [weak self] in
            guard let self, let player = self.player else { return }
            if let command = self.cue.capReached() { self.perform(command) }
            else { player.setVolume(0, fade: LidSoundCue.landFade); self.fadeEnd = self.after(LidSoundCue.landFade) { [weak self] in self?.finished() } }
        }
    }

    /// "Its own level": the Mac's volume is set to the dial for the sound. The old value is
    /// written down first, so a sleep in between still gets it put back at the next launch.
    private func takeTheVolume() {
        guard settings.volumeMode == .ownLevel, output.canSetVolume, let current = output.volume else { return }
        let wanted = Float(settings.volume)
        guard abs(current - wanted) > 0.005 else { return }
        if settings.volumeToRestore == nil {
            settings.volumeToRestore = Double(current)
            settings.muteToRestoreDeviceUID = settings.muteToRestoreDeviceUID ?? output.deviceUID
        }
        output.setVolume(wanted)
        Log.sound.info("volume set to \(Int(wanted * 100)) % for the sound")
    }

    private func finished() {
        capEnd?.cancel()
        capEnd = nil
        fadeEnd?.cancel()
        fadeEnd = nil
        cue.finished()
        dropPlayer()
        restoreMuteIfOwed()
    }

    private func dropPlayer() {
        capEnd?.cancel()
        capEnd = nil
        playing = nil
        prepared = nil
        guard let player else { return }
        self.player = nil
        player.onFinish = nil
        // `stop` blocks for a moment while the hardware is released: never on the main
        // thread during a close.
        DispatchQueue.global(qos: .utility).async { player.stop() }
    }

    /// Whatever "Unmute for it" or "Its own level" changed on the output, put back: on the
    /// same device only; another device is left alone and the debt forgiven.
    private func restoreMuteIfOwed() {
        guard settings.muteToRestore || settings.volumeToRestore != nil else { return }
        let sameDevice = settings.muteToRestoreDeviceUID == nil || settings.muteToRestoreDeviceUID == output.deviceUID
        if let volume = settings.volumeToRestore {
            if sameDevice { output.setVolume(Float(volume)); Log.sound.info("volume put back to \(Int(volume * 100)) %") }
            else { Log.sound.notice("volume was set on another output; leaving this one alone") }
        }
        if settings.muteToRestore {
            if sameDevice { output.setMuted(true); Log.sound.info("mute put back") }
            else { Log.sound.notice("mute was lifted on another output; leaving this one alone") }
        }
        settings.muteToRestore = false
        settings.volumeToRestore = nil
        settings.muteToRestoreDeviceUID = nil
        liftedMute = false
    }
}
