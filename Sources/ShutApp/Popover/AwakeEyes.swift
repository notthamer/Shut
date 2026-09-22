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

        /// Open eyes promise one thing: closing the lid keeps the Mac awake. A warning that
        /// comes with a sleeping lid shuts them.
        init(_ dot: AwakeText.Dot, isOn: Bool, lidSleeps: Bool = false) {
            switch dot {
            case .warning: self = lidSleeps ? .shut : .awake
            case .holding: self = .awake
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
    /// False inside a button: a label should not blink.
    var animated = true
    /// A soft "z z z" rising from sleeping eyes. For the large eyes on the page, which have
    /// room beside them; in a tab the letters would sit on the tab's name.
    var dreams = false
    /// Awake eyes that look at the pointer while it is near: the sprite has one frame for
    /// each corner, so the look is to whichever quarter the pointer is in. For the big eyes
    /// on the page; the small ones in a tab are too small to be looked at.
    var follows = false
    /// How far around the eyes "near" reaches, in points.
    static let reach: CGFloat = 56
    @State private var gaze: Frame?
    @Environment(\.tunerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !animated || reduceMotion || mood == .shut || mood == .asleep {
                image(Self.restingFrame(mood))
            } else {
                // Only a face that moves needs a clock, and only while it is on screen.
                TimelineView(.periodic(from: .now, by: 0.15)) { context in
                    let timed = Self.frame(mood, at: context.date.timeIntervalSinceReferenceDate)
                    // A look at the pointer still blinks.
                    image(gaze.map { timed == .blink ? .blink : $0 } ?? timed)
                }
            }
        }
        .frame(width: 16 * pixel, height: Self.rows * pixel)
        .overlay {
            if follows, animated, !reduceMotion, mood == .awake {
                // A wider, invisible ring around the eyes tracks the pointer; it changes no layout.
                let width = 16 * pixel + 2 * Self.reach, height = Self.rows * pixel + 2 * Self.reach
                Color.clear.frame(width: width, height: height).contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point): gaze = Self.gaze(dx: point.x - width / 2, dy: point.y - height / 2)
                        case .ended: gaze = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if dreams, mood == .shut || mood == .asleep {
                // Half the size of the eyes' pixels, kept to whole device pixels so they stay crisp:
                // an aside beside the face, not a second face.
                SleepingZs(pixel: max((pixel).rounded() / 2, 1), tint: tint ?? theme.ink, still: !animated || reduceMotion)
                    .offset(x: 17 * pixel, y: 1 * pixel)
            }
        }
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

    /// The corner the pointer is in, from the eyes' centre. Down is the bigger y (SwiftUI's).
    static func gaze(dx: CGFloat, dy: CGFloat) -> Frame {
        dy < 0 ? (dx < 0 ? .upLeft : .upRight) : (dx < 0 ? .downLeft : .downRight)
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

/// Three pixel z's beside sleeping eyes, each a little higher and fainter than the last.
/// Very soft: they are an aside, not a status. They come one by one and fade together on a
/// four-second loop; nothing moves (only opacity changes), and Reduce Motion holds them still.
struct SleepingZs: View {
    let pixel: CGFloat
    let tint: Color
    let still: Bool

    /// A four-by-four z: two bars and the diagonal between them. (Three by three has no room
    /// for the diagonal and reads as a capital I.)
    private static let glyph: [CGPoint] = [(0, 0), (1, 0), (2, 0), (3, 0), (2, 1), (1, 2), (0, 3), (1, 3), (2, 3), (3, 3)]
        .map { CGPoint(x: $0.0, y: $0.1) }
    /// Where each z sits, in sprite pixels, and how strong it may get.
    private static let places: [(x: CGFloat, y: CGFloat, strength: Double)] = [(0, 7, 0.30), (5, 3, 0.22), (10, -1, 0.14)]

    var body: some View {
        if still {
            letters(visible: 3)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                letters(visible: Self.visible(at: context.date.timeIntervalSinceReferenceDate))
            }
        }
    }

    /// 0, 1, 2, 3 letters, then none again: one every 0.8 s, all held, all gone.
    static func visible(at time: TimeInterval) -> Int {
        switch time.truncatingRemainder(dividingBy: 4) {
        case ..<0.5: return 0
        case ..<1.3: return 1
        case ..<2.1: return 2
        case ..<3.4: return 3
        default: return 0
        }
    }

    private func letters(visible: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.places.enumerated()), id: \.offset) { index, place in
                Path { path in
                    for point in Self.glyph {
                        path.addRect(CGRect(x: (place.x + point.x) * pixel, y: (place.y + point.y) * pixel, width: pixel, height: pixel))
                    }
                }
                .fill(tint)
                .opacity(index < visible ? place.strength : 0)
                .animation(.easeInOut(duration: 0.6), value: visible)
            }
        }
        .frame(width: 14 * pixel, height: 11 * pixel, alignment: .topLeading)
        .allowsHitTesting(false)
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
