import AppKit
import SwiftUI
import Tuner

/// The face of Stay awake: a pair of cartoon pixel eyes with brows, sixteen by twelve. Open means the Mac
/// will stay awake with the lid shut; closed means the lid sleeps it. One glance answers
/// the only question the feature has, before a word is read.
///
/// The sheet (`Resources/eyes.png`) holds six frames side by side: looking down-left,
/// down-right, up-right and up-left (there is no straight-ahead frame; these eyes are
/// always looking at something), shut with the brows dropped, and asleep. It is one colour on transparency, so only the inked pixels
/// are kept and each is drawn as a square in the theme's ink: crisp at any size.
struct AwakeEyes: View {
    enum Mood: Equatable {
        /// Holding the lid: open, with a glance around and a blink now and then.
        case awake
        /// The work has ended and the Mac will sleep soon: heavy lids.
        case drowsy
        /// Nothing to stay awake for: shut.
        case shut
        /// Switched off, or the user let it sleep: sound asleep.
        case asleep

        init(_ dot: AwakeText.Dot, isOn: Bool) {
            switch dot {
            case .holding, .warning: self = .awake
            case .winding: self = .drowsy
            case .idle: self = isOn ? .shut : .asleep
            }
        }
    }

    /// The first six are the sheet's frames, in its order. `blink` is made here: the shut
    /// eyes under the brows of the open ones.
    enum Frame: Int { case downLeft, downRight, upRight, upLeft, shut, asleep, blink }
    static let rows: CGFloat = 12
    /// The sheet's rows 0...3 hold the brows (and the top edge of an open eye, which no
    /// shut frame has).
    private static let browRows: ClosedRange<CGFloat> = 0...3

    /// Brows belong to a Mac that is awake. With the eyes shut for good they float over
    /// two lines and read as an equals sign, so the sleeping frames lose them. A blink is
    /// still an awake face: it keeps the brows exactly where the open eyes have them, so
    /// nothing jumps for the sixth of a second it lasts.
    static func pixels(_ frame: Frame) -> [CGPoint] {
        let sheet = AppAssets.eyes
        func lids(_ index: Int) -> [CGPoint] { (sheet[safe: index] ?? []).filter { !browRows.contains($0.y) } }
        switch frame {
        case .shut: return lids(Frame.shut.rawValue)
        case .asleep: return lids(Frame.asleep.rawValue)
        case .blink: return lids(Frame.shut.rawValue) + (sheet[safe: Frame.downRight.rawValue] ?? []).filter { $0.y <= 1 }
        default: return sheet[safe: frame.rawValue] ?? []
        }
    }

    let mood: Mood
    /// Points per sprite pixel: 1.5 in the bar, 2.5 on the Awake page. Halves are fine:
    /// on a Retina panel they are whole device pixels.
    var pixel: CGFloat = 1.5
    var tint: Color? = nil
    @Environment(\.tunerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || mood == .shut || mood == .asleep {
                image(Self.restingFrame(mood))
            } else {
                // Only a face that moves needs a clock, and only while it is on screen.
                TimelineView(.periodic(from: .now, by: 0.15)) { context in
                    image(Self.frame(mood, at: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .frame(width: 16 * pixel, height: Self.rows * pixel)
        .accessibilityHidden(true)   // the sentence beside it says the same thing
    }

    /// Every inked pixel of the frame as its own square, so nothing is ever smoothed.
    private func image(_ frame: Frame) -> some View {
        let inked = Self.pixels(frame)
        let lift = Self.lift(frame)
        return Path { path in
            for point in inked {
                path.addRect(CGRect(x: point.x * pixel, y: (point.y - lift) * pixel, width: pixel, height: pixel))
            }
        }
        .fill(tint ?? theme.ink)
    }

    /// Sleeping eyes are two short lines low in a frame that was laid out around open eyes
    /// and brows; lifted to the middle, they sit in their capsule instead of sinking in it.
    /// A blink is not lifted: it happens in place.
    static func lift(_ frame: Frame) -> CGFloat {
        guard frame == .shut || frame == .asleep else { return 0 }
        let ys = pixels(frame).map(\.y)
        guard let top = ys.min(), let bottom = ys.max() else { return 0 }
        return ((top + bottom + 1) / 2 - rows / 2).rounded()
    }

    static func restingFrame(_ mood: Mood) -> Frame {
        switch mood {
        // Down and to the right: in the bar and on the page, that is where the words are.
        case .awake: return .downRight
        case .drowsy: return .blink      // winding down, but still awake: brows stay
        case .shut: return .shut
        case .asleep: return .asleep
        }
    }

    /// The little performance, as a pure function of time so it can be tested and never
    /// drifts. Awake: six seconds, mostly a steady look at the words, one slow roll of the
    /// eyes around the other three corners, one blink. Drowsy: four seconds, eyes that
    /// open for a moment and give up.
    static func frame(_ mood: Mood, at time: TimeInterval) -> Frame {
        switch mood {
        case .awake:
            switch time.truncatingRemainder(dividingBy: 6) {
            case 3.0..<3.4: return .upRight
            case 3.4..<3.8: return .upLeft
            case 3.8..<4.2: return .downLeft
            case 5.4..<5.55: return .blink
            default: return .downRight
            }
        case .drowsy:
            return time.truncatingRemainder(dividingBy: 4) < 0.9 ? .downLeft : .blink
        case .shut, .asleep:
            return restingFrame(mood)
        }
    }
}

/// The eyes on a small capsule whose colour is the status: Lime while holding, Saffron
/// when a limit is near or has spoken, Linen while winding down, bare when idle.
struct AwakeFace: View {
    let dot: AwakeText.Dot
    let isOn: Bool
    var pixel: CGFloat = 1.5
    @Environment(\.tunerTheme) private var theme

    var body: some View {
        AwakeEyes(mood: .init(dot, isOn: isOn), pixel: pixel, tint: dot == .idle ? theme.inkTertiary : theme.ink)
            // Room to breathe: the brows were touching the rim.
            .padding(.horizontal, 7 * pixel / 1.5).padding(.vertical, 4 * pixel / 1.5)
            .background(Capsule().fill(fill))
            // Idle keeps its outline, or shut eyes are two stray dashes on the paper.
            .overlay(Capsule().strokeBorder(dot == .idle ? theme.inkTertiary.opacity(0.7) : theme.ink.opacity(0.85), lineWidth: 1))
            .tunerAnimation(TunerTheme.ease, value: dot)
    }

    private var fill: Color {
        switch dot {
        case .idle: return .clear
        case .holding: return TunerTheme.limeWash
        case .winding: return theme.linen
        case .warning: return TunerTheme.saffron
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
