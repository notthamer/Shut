import Foundation
import LidSensor

/// Every sentence Lid sound says, in one place and pure, so the wording can be read and
/// tested like copy. The rule is the same as Stay awake's: the page always answers "what
/// will closing the lid do?" in the same words, and names the sound.
enum LidSoundText {
    /// What the page knows, gathered once per draw.
    struct Situation: Equatable {
        var isOn: Bool
        /// Every row on the page (hidden starters excluded).
        var shownCount: Int
        /// The sounds a close may pick from, in order; names only.
        var candidates: [String]
        var mode: LidSoundSettings.Mode
        var whenMuted: LidSoundSettings.WhenMuted
        var muted: Bool
        /// The output device's mute cannot be lifted (some Bluetooth and HDMI outputs).
        var canUnmute = true
        /// The sound playing right now, if one is.
        var playing: String? = nil
        var outputName: String? = nil
        var onOpen = false
        var capability: HingeCapability = .continuousAngle
        /// In order: the one the next close plays.
        var next: String? = nil
    }

    /// "Muted" is the fact that matters: with Stay quiet, no sound will come, whatever is set.
    static func silencedByMute(_ s: Situation) -> Bool { s.isOn && s.muted && (s.whenMuted == .stayQuiet || !s.canUnmute) }

    /// The tab's second line: the state in a few words.
    static func tabLine(_ s: Situation) -> String {
        guard s.isOn else { return "Off" }
        if let playing = s.playing { return "Playing \(playing)…" }
        if silencedByMute(s) { return "Muted" }
        if s.shownCount == 0 { return "No sounds yet" }
        guard let first = s.candidates.first else { return "No sound chosen" }
        if s.candidates.count == 1 { return s.capability == .lidStateOnly ? "\(first) · after the lid shuts" : "\(first) · On" }
        return "\(s.candidates.count) sounds · \(s.mode == .random ? "random" : "in order")"
    }

    struct Copy: Equatable {
        let headline: String
        let detail: String
    }

    static let silent = "Closing the lid is silent."

    /// The answer at the top of the page: what closing will do, and why.
    static func copy(_ s: Situation) -> Copy {
        guard s.isOn else {
            return Copy(headline: silent,
                        detail: "Switch it on and the lid plays a sound as it closes: it starts as the lid comes down and ends as it lands.")
        }
        if silencedByMute(s) {
            return Copy(headline: "Your Mac is muted, so closing is silent.",
                        detail: s.canUnmute ? "Unmute, or choose “Unmute for it” under Settings."
                                            : "This output has no mute switch Shut can lift, so unmute it yourself.")
        }
        if s.shownCount == 0 { return Copy(headline: silent, detail: "No sounds yet. Add one below.") }
        guard let first = s.candidates.first else { return Copy(headline: silent, detail: "No sound is switched on. Switch one on below.") }
        let headline: String
        if s.candidates.count == 1 {
            headline = "Closing the lid plays \(first)."
        } else if s.mode == .random {
            headline = "Closing the lid plays one of \(s.candidates.count) sounds."
        } else {
            headline = "Closing the lid plays \(s.candidates.count) sounds in turn."
        }
        var parts: [String] = []
        parts.append(s.capability == .lidStateOnly
                     ? "This Mac only reports the lid shut, so the sound starts then and sleep may cut it short."
                     : "It starts as the lid comes down and ends as it lands.")
        if s.candidates.count > 1 {
            parts.append(s.mode == .random ? "A different one each time." : "Next: \(s.next ?? first).")
        }
        if s.muted, s.whenMuted == .unmute { parts.append("Your Mac is muted; Shut unmutes for the sound and mutes again after.") }
        if s.onOpen { parts.append("Opening plays one too.") }
        if let output = s.outputName { parts.append(outputLine(deviceName: output)) }
        return Copy(headline: headline, detail: parts.joined(separator: " "))
    }

    /// The folded Settings row: the two things worth knowing without opening it.
    static func settingsSummary(onOpen: Bool, whenMuted: LidSoundSettings.WhenMuted) -> String {
        (onOpen ? "A sound on open too" : "Silent on open") + " · " + (whenMuted == .unmute ? "unmutes for it" : "stays quiet when muted")
    }

    /// "0.8 s", "2.4 s", "12 s": one decimal under ten seconds, none above.
    static func durationText(_ seconds: TimeInterval) -> String {
        seconds < 10 ? String(format: "%.1f s", seconds) : "\(Int(seconds.rounded())) s"
    }

    static func outputLine(deviceName: String) -> String { "Through \(deviceName)." }

    // MARK: Import refusals, in plain words

    static func refusal(_ error: LidSoundLibrary.ImportError, name: String, duplicateOf: String? = nil) -> String {
        switch error {
        case .unreadable: return "Shut could not read \(name)."
        case .tooLong(let seconds): return "\(name) is \(durationText(seconds)) long. Sounds are \(Int(LidSoundLibrary.longest)) seconds at most."
        case .duplicate: return "\(duplicateOf ?? name) is already in the list."
        case .copyFailed: return "Shut could not copy \(name) into its Sounds folder."
        }
    }

    static let addHint = "mp3, m4a, wav or aiff · \(Int(LidSoundLibrary.longest)) s at most. Or drop files here."
    static let endsWithTheLid = "The sound ends with the lid: a short fade as it lands, whatever its length. Speed, on Lid effects, sets how early it starts."
    static let onOpenAbout = "A sound as the desktop pours back in, after you unlock."
    static let unmuteAbout = "Unmute for it: the sound plays, and mute comes back when it ends."
}
