import Foundation
import LidSensor

/// When the sound starts, fades and stops, as a pure function of the hinge and of the two
/// moments the lid controller reports. No I/O, so every path is a unit test.
///
/// The hinge, not the overlay's driver, is the fade source: a style's curve can read 0.9
/// while the lid is still half open, and "near shut" is about the physical lid. The
/// sound starts when the overlay appears (`closeBeginning`), or, with Lid effects off and
/// no overlay, when the hinge crosses the same threshold the overlay would have used.
struct LidSoundCue: Equatable {
    /// `spent`: this close's sound has played; nothing more until the lid comes back up.
    /// (Without it, a Mac awake with the lid down, held by Stay awake or taking a while to
    /// sleep, replayed the sound every 0.3 s from the hinge: play, land-fade, play again.)
    enum Phase: Equatable { case idle, prepared, playing, fading, spent }
    enum Command: Equatable {
        case prepare
        case play
        case fade(TimeInterval)
        case drop
    }

    private(set) var phase: Phase = .idle
    /// Lid effects is off, so nothing else will say when the close begins.
    var playsOnHinge = false
    /// A continuous hinge: the fade can land with the lid. Lid-state-only Macs report 0 or 1,
    /// and fading at "1" would end the sound the moment it started.
    var landFades = true
    /// The sound's own start, in degrees above shut; nil starts it with the screen effect.
    /// Needs a real angle: without one (an edge-only Mac) the effect's start stands in.
    var startAngle: Double?
    private var peak = 0.0

    /// The same thresholds the overlay uses (`AppController.armAt`, `showAt`, `hideBelow`).
    static let armAt = 0.003
    static let showAt = 0.012
    /// A few degrees above shut: the fade starts here and lands with the lid.
    static let landAt = 0.9
    static let topAt = 0.004
    /// Lifted back to a quarter of the band: the next close is a new close (the lid does not
    /// have to go all the way up).
    static let liftedAt = 0.25
    /// The lid came back up this much from its lowest point: the user changed their mind.
    static let liftBy = 0.05
    static let landFade: TimeInterval = 0.3
    static let liftFade: TimeInterval = 0.15

    mutating func hinge(progress p: Double, direction: HingeDirection, angle: Double? = nil) -> Command? {
        switch phase {
        case .idle:
            guard p > Self.armAt, direction != .opening else { return nil }
            phase = .prepared
            peak = p
            return .prepare
        case .prepared:
            if let startAngle, let angle {
                if angle <= startAngle, direction != .opening { phase = .playing; peak = p; return .play }
            } else if playsOnHinge, p >= Self.showAt { phase = .playing; peak = p; return .play }
            if p <= Self.topAt / 2, direction != .closing { phase = .idle; return .drop }
            return nil
        case .playing:
            peak = max(peak, p)
            if landFades, p >= Self.landAt { phase = .fading; return .fade(Self.landFade) }
            if direction == .opening, p < peak - Self.liftBy { phase = .fading; return .fade(Self.liftFade) }
            return nil
        case .fading:
            return nil   // a second fade never restarts the clock
        case .spent:
            if p <= Self.liftedAt { phase = .idle }
            return nil
        }
    }

    /// From the lid controller: the overlay is appearing. With an angle of its own the sound
    /// waits for that instead (`startsAtOwnAngle`: the hinge has a real angle to compare).
    mutating func closeBeginning(startsAtOwnAngle: Bool = false) -> Command? {
        switch phase {
        case .idle, .prepared:
            if startsAtOwnAngle { if phase == .idle { phase = .prepared; return .prepare }; return nil }
            phase = .playing; return .play
        case .playing, .fading, .spent: return nil
        }
    }

    /// From the lid controller: the close ended without the lid shutting (reopened to the
    /// top, the sensor went quiet, the display left, the feature was switched off).
    mutating func closeEnded() -> Command? {
        switch phase {
        case .prepared: phase = .idle; return .drop
        case .playing: phase = .fading; return .fade(Self.liftFade)
        case .spent: phase = .idle; return nil
        case .idle, .fading: return nil
        }
    }

    /// A long file has played its thirty seconds: fade, if it is still going.
    mutating func capReached() -> Command? {
        guard phase == .playing else { return nil }
        phase = .fading
        return .fade(Self.landFade)
    }

    /// The player ended by itself, or the fade's clock ran out. A close's sound is then spent
    /// until the lid comes back up; anything else (a preview, a dropped pick) is simply over.
    mutating func finished() {
        phase = phase == .playing || phase == .fading ? .spent : .idle
        peak = 0
    }

    /// The lid opened for real (a wake, a reopen to the top): whatever was spent is forgotten.
    mutating func reset() {
        phase = .idle
        peak = 0
    }
}
