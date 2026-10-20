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
        /// Where the sound starts, in degrees above shut; nil when the page has no sensor to say.
        var startDegrees: Int? = nil
        /// The Mac waits for the sound before it sleeps.
        var playsToEnd = false
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
        if s.capability == .lidStateOnly {
            parts.append("This Mac only reports the lid shut, so the sound starts then and sleep may cut it short.")
        } else if let degrees = s.startDegrees {
            parts.append(s.playsToEnd ? "It starts as the lid passes \(degrees)° and plays to the end; your Mac sleeps right after."
                                      : "It starts as the lid passes \(degrees)° and ends as it lands.")
        } else {
            parts.append(s.playsToEnd ? "It starts as the lid comes down and plays to the end; your Mac sleeps right after."
                                      : "It starts as the lid comes down and ends as it lands.")
        }
        if s.candidates.count > 1 {
            parts.append(s.mode == .random ? "A different one each time." : "Next: \(s.next ?? first).")
        }
        if s.muted, s.whenMuted == .unmute { parts.append("Your Mac is muted; Shut unmutes for the sound and mutes again after.") }
        if s.onOpen { parts.append("Opening plays one too.") }
        if let output = s.outputName { parts.append(outputLine(deviceName: output)) }
        return Copy(headline: headline, detail: parts.joined(separator: " "))
    }

    /// The folded Settings row: the two things worth knowing without opening it.
    static func settingsSummary(onOpen: Bool, whenMuted: LidSoundSettings.WhenMuted, volumeMode: LidSoundSettings.VolumeMode = .ownLevel) -> String {
        var parts = [onOpen ? "A sound on open too" : "Silent on open", whenMuted == .unmute ? "unmutes for it" : "stays quiet when muted"]
        if volumeMode == .shareOfMac { parts.append("follows the Mac's volume") }
        return parts.joined(separator: " · ")
    }

    /// Under the Volume dial: what the number means.
    static func volumeAbout(_ mode: LidSoundSettings.VolumeMode, macVolume: Float?) -> String {
        switch mode {
        case .shareOfMac:
            let mac = macVolume.map { " (\(Int(($0 * 100).rounded())) % now)" } ?? ""
            return "Of your Mac's volume\(mac)."
        case .ownLevel:
            return "Your Mac is set to this for it, then put back."
        }
    }
    static let shareOfMacAbout = "Its own level: Shut sets your Mac's volume to the dial for the sound and puts it back when it ends. Of the Mac's: a share of your Mac's volume as it is, so the lid follows the Mac, and a quiet Mac means a quiet lid."
    static let noVolumeControl = "This output has no volume Shut can set, so the dial is a share of it either way."

    /// "0.8 s", "2.4 s", "12 s", "3 min 20 s": one decimal under ten seconds, none above.
    static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 10 { return String(format: "%.1f s", seconds) }
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole) s" }
        return whole % 60 == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(whole % 60) s"
    }

    /// A place in a file, as a clock reads: "0:07", "1:12".
    static func clockText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// After a long file came in: it will be clipped, and where to do that.
    static func longNote(name: String, seconds: TimeInterval) -> String {
        "\(name) is \(durationText(seconds)) long: the lid plays up to \(Int(LidSoundLibrary.clipLength)) s of it, from where you choose (Clip, in its row)."
    }

    /// A cut's default name: the sound and the part, "Rain · 0:03–0:07".
    static func cutName(of source: String, from: TimeInterval, to: TimeInterval) -> String {
        "\(source) · \(clockText(from))–\(clockText(to))"
    }
    static let cutAbout = "Drag the edges around the part you want, give it a name, and add it as a sound of its own. Cut as many parts from one file as you like; they share the file."
    static func cutRefusal(_ error: LidSoundLibrary.CutError) -> String {
        switch error {
        case .tooShort: return "A part is half a second at least."
        case .outside: return "That part is outside the file."
        }
    }
    static let playsToEndAbout = "Your Mac waits for the sound, then sleeps at once. Off: a short fade as the lid lands, whatever the length."
    static let findPartsAbout = "Shut looks for the silences and marks a part between each. Name them, then add them all at once."
    static func partsFound(_ count: Int) -> String {
        count <= 1 ? "No silence to split at: it is one part. Drag the edges instead." : "\(count) parts, by the silence between them. Name them, then add."
    }
    static func partName(_ index: Int) -> String { "Part \(index + 1)" }
    static let clipAbout = "Plays from here, for \(Int(LidSoundLibrary.clipLength)) s at most. How much is heard depends on where the lid starts it and how fast it closes."

    static func outputLine(deviceName: String) -> String { "Through \(deviceName)." }

    // MARK: Import refusals, in plain words

    static func refusal(_ error: LidSoundLibrary.ImportError, name: String, duplicateOf: String? = nil) -> String {
        switch error {
        case .unreadable: return "Shut could not read \(name)."
        case .tooLong(let seconds): return "\(name) is \(durationText(seconds)) long. Sounds are \(Int(LidSoundLibrary.longest / 60)) minutes at most."
        case .duplicate: return "\(duplicateOf ?? name) is already in the list."
        case .copyFailed: return "Shut could not copy \(name) into its Sounds folder."
        }
    }

    static let addHint = "mp3, m4a, wav or aiff. Or drop files here. A long one plays from where you choose."
    static let endsWithTheLid = "The sound ends with the lid: a short fade as it lands, whatever its length. Starts at, above, sets how early it begins."
    static func startsWithEffectAbout(_ degrees: Int) -> String { "Where the screen effect starts: \(degrees)°, from Speed on Lid effects." }
    static let ownStartAbout = "Its own angle, whatever the screen effect does."
    static let onOpenAbout = "A sound as the desktop pours back in, after you unlock."
    static let unmuteAbout = "Unmute for it: the sound plays, and mute comes back when it ends."
}
