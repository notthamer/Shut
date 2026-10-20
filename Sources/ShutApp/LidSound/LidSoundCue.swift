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
    enum Phase: Equatable { case idle, prepared, playing, fading }
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
    private var peak = 0.0

    /// The same thresholds the overlay uses (`AppController.armAt`, `showAt`, `hideBelow`).
    static let armAt = 0.003
    static let showAt = 0.012
    /// A few degrees above shut: the fade starts here and lands with the lid.
    static let landAt = 0.9
    static let topAt = 0.004
    /// The lid came back up this much from its lowest point: the user changed their mind.
    static let liftBy = 0.05
    static let landFade: TimeInterval = 0.3
    static let liftFade: TimeInterval = 0.15

    mutating func hinge(progress p: Double, direction: HingeDirection) -> Command? {
        switch phase {
        case .idle:
            guard p > Self.armAt, direction != .opening else { return nil }
            phase = .prepared
            peak = p
            return .prepare
        case .prepared:
            if playsOnHinge, p >= Self.showAt { phase = .playing; peak = p; return .play }
            if p <= Self.topAt / 2, direction != .closing { phase = .idle; return .drop }
            return nil
        case .playing:
            peak = max(peak, p)
            if landFades, p >= Self.landAt { phase = .fading; return .fade(Self.landFade) }
            if direction == .opening, p < peak - Self.liftBy { phase = .fading; return .fade(Self.liftFade) }
            return nil
        case .fading:
            return nil   // a second fade never restarts the clock
        }
    }

    /// From the lid controller: the overlay is appearing.
    mutating func closeBeginning() -> Command? {
        switch phase {
        case .idle, .prepared: phase = .playing; return .play
        case .playing, .fading: return nil
        }
    }

    /// From the lid controller: the close ended without the lid shutting (reopened to the
    /// top, the sensor went quiet, the display left, the feature was switched off).
    mutating func closeEnded() -> Command? {
        switch phase {
        case .prepared: phase = .idle; return .drop
        case .playing: phase = .fading; return .fade(Self.liftFade)
        case .idle, .fading: return nil
        }
    }

    /// The player ended by itself, or the fade's clock ran out.
    mutating func finished() {
        phase = .idle
        peak = 0
    }
}
