import AVFAudio
import Foundation

/// What the controller needs from a player, so a test can hand it a fake.
protocol SoundPlaying: AnyObject {
    var volume: Float { get set }
    var duration: TimeInterval { get }
    /// Called on the main queue when the sound ends by itself.
    var onFinish: (() -> Void)? { get set }
    func prepare()
    func play()
    func setVolume(_ volume: Float, fade: TimeInterval)
    func stop()
}

/// `AVAudioPlayer`, which has everything a lid needs: an offset, a volume with a fade, and a
/// `prepareToPlay` that takes the audio hardware's wake-up out of the moment the lid moves.
final class AudioPlayer: NSObject, SoundPlaying, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var duration: TimeInterval { player.duration }
    func prepare() { player.prepareToPlay() }
    func play() { player.play() }
    func setVolume(_ volume: Float, fade: TimeInterval) { player.setVolume(volume, fadeDuration: fade) }
    /// Blocks briefly while the hardware is released: the controller calls it off the main thread.
    func stop() { player.stop() }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onFinish?() }
    }
}
