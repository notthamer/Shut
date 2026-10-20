import AVFAudio
import Foundation

/// What the controller needs from a player, so a test can hand it a fake. Every call may
/// return before the work is done; nothing here is awaited on the main thread.
protocol SoundPlaying: AnyObject {
    var volume: Float { get set }
    /// Called on the main queue when the sound ends by itself.
    var onFinish: (() -> Void)? { get set }
    func prepare()
    /// Where to start from, in seconds; before `play`.
    func seek(to seconds: TimeInterval)
    func play()
    func setVolume(_ volume: Float, fade: TimeInterval)
    func stop()
}

/// `AVAudioPlayer`, which has everything a lid needs: a volume with a fade, and a
/// `prepareToPlay` that takes the audio hardware's wake-up out of the moment the lid moves.
///
/// Every call to it goes through one serial queue, never the main thread. Measured on a
/// MacBook Pro with AirPods: the first `play` after a wake blocked for fifteen seconds
/// while Bluetooth came back, and the opening animation froze behind it. The player itself
/// is made on that queue too, on first use, so a file is not even opened on the main thread.
final class AudioPlayer: NSObject, SoundPlaying, AVAudioPlayerDelegate {
    private static let queue = DispatchQueue(label: "app.shut.sound", qos: .userInteractive)
    private let url: URL
    private var player: AVAudioPlayer?
    private var pendingVolume: Float = 1
    var onFinish: (() -> Void)?

    /// Fails only for a file that is not there; a file Core Audio cannot read fails at the
    /// first use, on the queue, and plays nothing.
    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        self.url = url
        super.init()
    }

    /// On the queue: the player, made on first use.
    private func made() -> AVAudioPlayer? {
        if let player { return player }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.delegate = self
        player.volume = pendingVolume
        self.player = player
        return player
    }

    var volume: Float {
        get { pendingVolume }
        set { pendingVolume = newValue; Self.queue.async { [self] in player?.volume = newValue } }
    }
    func prepare() { Self.queue.async { [self] in made()?.prepareToPlay() } }
    func seek(to seconds: TimeInterval) { Self.queue.async { [self] in made()?.currentTime = seconds } }
    func play() { Self.queue.async { [self] in made()?.play() } }
    func setVolume(_ volume: Float, fade: TimeInterval) { Self.queue.async { [self] in player?.setVolume(volume, fadeDuration: fade) } }
    /// Blocks for a moment while the hardware is released; on the queue, nobody waits.
    func stop() { Self.queue.async { [self] in player?.stop(); player = nil } }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onFinish?() }
    }
}
