#!/usr/bin/env swift
// Generates every bundled sound for Lid sound, so the feature works before anyone adds a
// file of their own. Pure Swift and Foundation: every sample is computed here, nothing is
// recorded or borrowed, so no licence applies. Deterministic (seeded generators), so running
// it again writes the same bytes.
//
//   swift scripts/make-sounds.swift        -> Sources/ShutApp/Resources/Sounds/*
//
// The first three (Click, Breath, Hum) are written as WAV, as they were in 0.4.0. Everything
// after them goes through afconvert (part of macOS) to AAC in an .m4a, so sixty sounds add a
// few hundred kilobytes to the download, not a few megabytes. Every clip is 48 kHz mono,
// peak-normalised to -6 dBFS with a 5 ms raised-cosine edge at both ends so nothing ever
// clicks that was not meant to.
//
// The sounds are built from a few parts: a `voice` (a wave whose pitch and loudness are
// functions of time, so a glide or a wobble is one line), `hiss` (noise through a low-pass),
// `ring` (noise through a resonator: a knock, a scratch, breath), and `place`, which lays
// clips on a timeline and adds them. Each sound's function says what it is trying to be.
import Foundation

let sampleRate = 48_000.0
let twoPi = 2 * Double.pi

func seconds(_ s: Double) -> Int { Int((s * sampleRate).rounded()) }

// MARK: Parts

/// xorshift64*, seeded: the "noise" in every sound is the same every run.
struct Noise {
    var state: UInt64
    init(state: UInt64 = 0x9E37_79B9_7F4A_7C15) { self.state = state == 0 ? 1 : state }
    mutating func next() -> Double {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        let bits = state &* 2_685_821_657_736_338_717
        return Double(bits >> 11) / Double(1 << 53) * 2 - 1   // -1 ... 1
    }
}

/// A one-pole low-pass: the simplest filter that sounds like a thing getting softer.
struct LowPass {
    private var y = 0.0
    mutating func step(_ x: Double, cutoff: Double) -> Double {
        let a = 1 - exp(-twoPi * cutoff / sampleRate)
        y += a * (x - y)
        return y
    }
}

/// A two-pole resonator: rings at `centre`, and `width` (Hz) says how fast the ring dies.
/// Narrow rings long, like a bell; wide barely colours, like a room.
struct Resonator {
    private var y1 = 0.0, y2 = 0.0
    mutating func step(_ x: Double, centre: Double, width: Double) -> Double {
        let r = exp(-Double.pi * width / sampleRate)
        let y = x * (1 - r) + 2 * r * cos(twoPi * centre / sampleRate) * y1 - r * r * y2
        y2 = y1; y1 = y
        return y
    }
}

func sine(_ p: Double) -> Double { sin(twoPi * p) }
func square(_ p: Double) -> Double { p - floor(p) < 0.5 ? 1 : -1 }
func saw(_ p: Double) -> Double { 2 * (p - floor(p)) - 1 }
func triangle(_ p: Double) -> Double { 1 - 4 * abs(p - floor(p) - 0.5) }

/// A pitched voice: the phase follows `pitch(t)`, so a glide or a vibrato is just a function
/// of time, and `amp(t)` is how loud it is at each moment.
func voice(_ duration: Double, wave: (Double) -> Double = sine, pitch: (Double) -> Double, amp: (Double) -> Double) -> [Double] {
    var phase = 0.0
    return (0..<seconds(duration)).map { i in
        let t = Double(i) / sampleRate
        let s = wave(phase) * amp(t)
        phase += pitch(t) / sampleRate
        return s
    }
}

/// Noise through a low-pass whose cutoff may move: wind, breath, a thud.
func hiss(_ duration: Double, seed: UInt64, cutoff: (Double) -> Double, amp: (Double) -> Double) -> [Double] {
    var noise = Noise(state: seed), low = LowPass()
    return (0..<seconds(duration)).map { i in
        let t = Double(i) / sampleRate
        return low.step(noise.next(), cutoff: cutoff(t)) * amp(t)
    }
}

/// Noise through a resonator whose centre may move: a knock, a scratch, air in a pipe.
func ring(_ duration: Double, seed: UInt64, centre: (Double) -> Double, width: Double, amp: (Double) -> Double) -> [Double] {
    var noise = Noise(state: seed), resonator = Resonator()
    return (0..<seconds(duration)).map { i in
        let t = Double(i) / sampleRate
        return resonator.step(noise.next(), centre: centre(t), width: width) * amp(t)
    }
}

/// A pitch that slides from `a` to `b` over `over` seconds and holds. Exponential, since the
/// ear hears a slide as even when the ratio moves evenly, not the difference.
func slide(_ a: Double, _ b: Double, over: Double) -> (Double) -> Double {
    { t in a * pow(b / a, min(1, max(0, t / over))) }
}
/// Loud at once, then dying: `tau` seconds to a third.
func decay(_ tau: Double) -> (Double) -> Double { { t in exp(-t / tau) } }
/// Up over `attack`, full, and down over `release` at the end of `length`.
func envelope(attack: Double, release: Double, length: Double) -> (Double) -> Double {
    { t in max(0, min(1, t / max(attack, 1e-6), (length - t) / max(release, 1e-6))) }
}

func gain(_ samples: [Double], _ g: Double) -> [Double] { samples.map { $0 * g } }
/// Everything above `cutoff` taken down: a wall between the sound and the ear.
func soften(_ samples: [Double], cutoff: Double) -> [Double] {
    var low = LowPass()
    return samples.map { low.step($0, cutoff: cutoff) }
}
/// Everything below `cutoff` taken down: what is left of a sound heard through a door.
func thin(_ samples: [Double], cutoff: Double) -> [Double] {
    var low = LowPass()
    return samples.map { $0 - low.step($0, cutoff: cutoff) }
}
/// Clips on a timeline, added: `(at, samples)`.
func place(_ parts: [(Double, [Double])]) -> [Double] {
    let length = parts.map { seconds($0.0) + $0.1.count }.max() ?? 0
    var out = [Double](repeating: 0, count: length)
    for (at, samples) in parts {
        let start = seconds(at)
        for (i, s) in samples.enumerated() { out[start + i] += s }
    }
    return out
}

/// One short bright knock: resonated noise, over in 30 ms. The tooth of a zipper, the
/// blade of a shutter, a key hitting its stop.
func tick(_ seed: UInt64, _ centre: Double) -> [Double] {
    ring(0.03, seed: seed, centre: { _ in centre }, width: 500, amp: decay(0.005))
}
/// A music-box note: a sine with two high, slightly off-tune partials, struck and left to ring.
func musicBox(_ pitch: Double, _ length: Double = 0.9) -> [Double] {
    voice(length, wave: { sine($0) + 0.35 * sine(4 * $0) + 0.15 * sine(7.1 * $0) }, pitch: { _ in pitch },
          amp: { t in decay(0.28)(t) * min(1, t / 0.002) })
}
/// A snare hit: a burst of noise with a short low knock under it.
func snare(_ seed: UInt64) -> [Double] {
    place([(0, hiss(0.14, seed: seed, cutoff: { _ in 5_000 }, amp: decay(0.03))),
           (0, gain(voice(0.08, pitch: slide(200, 150, over: 0.05), amp: decay(0.03)), 0.6))])
}
/// A cymbal: bright noise, left to shimmer.
func cymbal(_ seed: UInt64) -> [Double] {
    thin(hiss(0.8, seed: seed, cutoff: { _ in 12_000 }, amp: decay(0.2)), cutoff: 4_000)
}
/// A tom: a sine that drops in pitch as the skin settles.
func tom(_ pitch: Double, _ seed: UInt64) -> [Double] {
    place([(0, voice(0.3, pitch: slide(pitch, pitch * 0.55, over: 0.12), amp: decay(0.1))),
           (0, gain(hiss(0.02, seed: seed, cutoff: { _ in 2_000 }, amp: decay(0.004)), 0.5))])
}
/// A brass note: a saw through a filter that closes as the note goes on, with a slow vibrato.
func brass(_ pitch: Double, _ length: Double, release: Double, cutoff: (Double, Double) = (3_000, 1_200)) -> [Double] {
    var low = LowPass()
    let raw = voice(length, wave: saw, pitch: { t in pitch * (1 + 0.006 * sin(twoPi * 5 * t)) },
                    amp: envelope(attack: 0.02, release: release, length: length))
    return raw.enumerated().map { i, s in low.step(s, cutoff: cutoff.0 + (cutoff.1 - cutoff.0) * Double(i) / Double(raw.count)) }
}
/// A tune laid out one note per slot, each note a part the manifest can point at.
func tune(_ pitches: [Double], slot: Double) -> [Double] {
    place(pitches.enumerated().map { i, pitch in (Double(i) * slot, musicBox(pitch, slot - 0.05)) })
}

// MARK: Starters (in the list from the first launch)

/// A soft knock: a short burst of filtered noise under a fast decay, with a damped sine so it
/// has a pitch to it, like a lid landing on felt.
func click() -> [Double] {
    var noise = Noise(), low = LowPass()
    let n = seconds(0.06)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        let decay = exp(-t / 0.012)
        let burst = low.step(noise.next(), cutoff: 4_000) * decay
        let ring = sin(2 * .pi * 1_800 * t) * exp(-t / 0.02) * 0.5
        return burst + ring
    }
}

/// An exhale: white noise through a low-pass whose cutoff sweeps down, with a slow swell
/// and a slower release.
func breath() -> [Double] {
    var noise = Noise(state: 0x2545_F491_4F6C_DD1D), low = LowPass()
    let n = seconds(0.7)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        let envelope = t < 0.15 ? t / 0.15 : max(0, 1 - (t - 0.15) / 0.4)
        let cutoff = 3_000 - (3_000 - 600) * min(1, t / 0.7)
        return low.step(noise.next(), cutoff: cutoff) * envelope
    }
}

/// Two notes: a sine on A3 that crosses to E4 part way through, softly in and out.
func hum() -> [Double] {
    let n = seconds(0.8)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        let cross = min(1, max(0, (t - 0.3) / 0.1))
        let a = sin(2 * .pi * 220 * t) * (1 - cross)
        let e = sin(2 * .pi * 330 * t) * cross
        let envelope = min(1, t / 0.08) * min(1, (0.8 - t) / 0.25)
        return (a + e) * envelope * 0.8
    }
}

/// A drop into something thick: a sine that falls two octaves in a tenth of a second, over
/// a soft thump.
func blob() -> [Double] {
    place([(0, voice(0.22, pitch: slide(640, 140, over: 0.12), amp: decay(0.07))),
           (0, gain(voice(0.12, pitch: { _ in 90 }, amp: decay(0.04)), 0.6))])
}

/// A bubble bursting: a chirp that is over before the ear can place its pitch.
func pop() -> [Double] {
    place([(0, voice(0.06, pitch: slide(1_400, 300, over: 0.025), amp: decay(0.014))),
           (0, gain(hiss(0.01, seed: 7, cutoff: { _ in 6_000 }, amp: decay(0.003)), 0.8))])
}

/// A spring: a bright tone whose pitch wobbles, the wobble dying as the spring settles.
func boing() -> [Double] {
    voice(0.9, wave: { triangle($0) + 0.3 * saw(2 * $0) },
          pitch: { t in 170 * (1 + 0.7 * exp(-t / 0.3) * sin(twoPi * 11 * t)) },
          amp: { t in decay(0.3)(t) * min(1, t / 0.005) })
}

/// Two square notes a fourth apart, the second left to ring: the sound a coin made in 1985.
func coin() -> [Double] {
    gain(place([(0, voice(0.08, wave: square, pitch: { _ in 988 }, amp: { _ in 1 })),
                (0.08, voice(0.4, wave: square, pitch: { _ in 1_319 }, amp: decay(0.15)))]), 0.5)
}

/// A cathode-ray tube switched off: the relay's thunk, the picture collapsing to a dot as a
/// whistle falls out of hearing, and a static that fades with it.
func crtOff() -> [Double] {
    let thunk = place([(0, hiss(0.08, seed: 3, cutoff: { _ in 250 }, amp: decay(0.02))),
                       (0, voice(0.1, pitch: { _ in 55 }, amp: decay(0.05)))])
    let whistle = voice(0.45, pitch: slide(3_200, 60, over: 0.4), amp: { t in decay(0.14)(t) * min(1, t / 0.01) })
    let dust = hiss(0.5, seed: 11, cutoff: { _ in 5_000 }, amp: { t in 0.15 * decay(0.2)(t) })
    return place([(0, thunk), (0.02, gain(whistle, 0.7)), (0, dust)])
}

// MARK: Pops

/// A pebble into a pond: a lower, slower Blob, and the small bubble that comes up after.
func plop() -> [Double] {
    place([(0, voice(0.3, pitch: slide(420, 70, over: 0.2), amp: decay(0.1))),
           (0.16, gain(voice(0.12, pitch: slide(300, 700, over: 0.1), amp: decay(0.04)), 0.5))])
}

/// A cartoon water drop: the pitch goes up, not down.
func bloop() -> [Double] {
    voice(0.2, pitch: slide(220, 950, over: 0.15), amp: { t in decay(0.07)(t) * min(1, t / 0.004) })
}

/// Three small bubbles, each a little higher than the last.
func bubble() -> [Double] {
    func one(_ pitch: Double) -> [Double] { voice(0.1, pitch: slide(pitch * 0.6, pitch, over: 0.05), amp: decay(0.03)) }
    return place([(0, one(500)), (0.09, one(700)), (0.2, one(950))])
}

/// A cork leaving a bottle: a sharp burst, the neck's hollow note, and a chirp of air.
func cork() -> [Double] {
    place([(0, hiss(0.015, seed: 5, cutoff: { _ in 8_000 }, amp: decay(0.004))),
           (0, gain(ring(0.2, seed: 6, centre: { _ in 380 }, width: 25, amp: decay(0.06)), 1.5)),
           (0, gain(voice(0.05, pitch: slide(900, 350, over: 0.03), amp: decay(0.015)), 0.6))])
}

/// A raindrop: a tick where it lands and the rising note of the ripple.
func drip() -> [Double] {
    place([(0, voice(0.04, pitch: slide(2_200, 900, over: 0.03), amp: decay(0.012))),
           (0.02, gain(voice(0.25, pitch: slide(450, 650, over: 0.2), amp: { t in decay(0.09)(t) * min(1, t / 0.01) }), 0.7))])
}

/// Something wet pressed: resonated noise sliding down with a wobble in it.
func squelch() -> [Double] {
    ring(0.3, seed: 8, centre: { t in 1_500 * pow(0.2, t / 0.3) * (1 + 0.3 * sin(twoPi * 25 * t)) }, width: 120,
         amp: envelope(attack: 0.02, release: 0.15, length: 0.3))
}

// MARK: Toys

/// A slide whistle on the way down: a tone two octaves high falling for as long as a lid
/// takes to close, with the breath that drives it.
func slideWhistle() -> [Double] {
    let pitch = slide(1_500, 350, over: 0.6)
    let shape = envelope(attack: 0.03, release: 0.08, length: 0.65)
    return place([(0, voice(0.65, wave: { sine($0) + 0.15 * sine(2 * $0) }, pitch: pitch, amp: shape)),
                  (0, ring(0.65, seed: 9, centre: pitch, width: 200, amp: { t in 0.25 * shape(t) }))])
}

/// A hollow wooden knock with a comic low note under it.
func bonk() -> [Double] {
    place([(0, hiss(0.03, seed: 12, cutoff: { _ in 900 }, amp: decay(0.008))),
           (0, gain(voice(0.35, pitch: slide(260, 110, over: 0.04), amp: decay(0.12)), 0.9))])
}

/// A rubber duck squeezed: two nasal notes, up and then down.
func squeak() -> [Double] {
    func note(_ from: Double, _ to: Double, _ length: Double) -> [Double] {
        var mouth = Resonator()
        let raw = voice(length, wave: saw, pitch: slide(from, to, over: length), amp: envelope(attack: 0.02, release: 0.04, length: length))
        return raw.map { mouth.step($0, centre: 2_400, width: 400) }
    }
    return place([(0, note(850, 1_400, 0.14)), (0.16, note(1_250, 750, 0.16))])
}

/// Four notes, each a semitone under the last, the filter closing over each ("wah"), the
/// last one trembling as it dies.
func sadTrombone() -> [Double] {
    let notes: [(pitch: Double, length: Double)] = [(233.1, 0.28), (220, 0.28), (207.7, 0.28), (196, 0.75)]
    var parts: [(Double, [Double])] = []
    var at = 0.0
    for (i, note) in notes.enumerated() {
        let last = i == notes.count - 1
        var low = LowPass()
        let raw = voice(note.length, wave: saw,
                        pitch: { t in note.pitch * (1 + (last ? 0.02 * sin(twoPi * 5.5 * t) * min(1, t / 0.2) : 0)) },
                        amp: envelope(attack: 0.02, release: last ? 0.3 : 0.05, length: note.length))
        parts.append((at, raw.enumerated().map { i, s in low.step(s, cutoff: 250 + 1_800 * pow(0.25, Double(i) / sampleRate / note.length)) }))
        at += note.length + 0.03
    }
    return gain(place(parts), 0.5)
}

/// A kazoo: a saw with a buzzing membrane in front of it and a nasal resonance.
func kazoo() -> [Double] {
    var membrane = Resonator()
    let shape = envelope(attack: 0.03, release: 0.08, length: 0.45)
    let raw = voice(0.45, wave: saw, pitch: { t in 330 * (1 + 0.01 * sin(twoPi * 6 * t)) },
                    amp: { t in shape(t) * (0.7 + 0.3 * square(55 * t)) })
    return raw.map { $0 * 0.5 + membrane.step($0, centre: 1_600, width: 300) }
}

/// A clown's horn: two reedy notes, not quite in tune with each other.
func honk() -> [Double] {
    let shape = envelope(attack: 0.01, release: 0.03, length: 0.3)
    return soften(place([(0, voice(0.3, wave: saw, pitch: { _ in 290 }, amp: shape)),
                         (0, voice(0.3, wave: saw, pitch: { _ in 435 }, amp: shape))]), cutoff: 2_500)
}

/// A spring door stop flicked: a metallic note whose wobble starts fast and slows as it
/// settles.
func doorStop() -> [Double] {
    var wobble = 0.0
    return (0..<seconds(1.1)).map { i in
        let t = Double(i) / sampleRate
        wobble += (4 + 22 * exp(-t / 0.5)) / sampleRate          // the wobble's own phase, slowing
        let pitch = 520 * (1 + 0.08 * exp(-t / 0.4) * sin(twoPi * wobble))
        let p = pitch * t
        return (sine(p) + 0.5 * sine(2.76 * p) + 0.25 * sine(5.4 * p)) * decay(0.35)(t) * min(1, t / 0.003)
    }
}

// MARK: Machines

/// A machine losing power: its hum sags in pitch and dies.
func powerDown() -> [Double] {
    soften(voice(0.9, wave: { saw($0) * 0.5 + sine($0) }, pitch: slide(110, 18, over: 0.85),
                 amp: envelope(attack: 0.02, release: 0.3, length: 0.9)), cutoff: 600)
}

/// A vault door: a heavy clunk, the metal's ring, and the hiss of air as it seals.
func vault() -> [Double] {
    place([(0, hiss(0.12, seed: 14, cutoff: { _ in 180 }, amp: decay(0.03))),
           (0, voice(0.2, pitch: { _ in 48 }, amp: decay(0.08))),
           (0, gain(ring(0.3, seed: 15, centre: { _ in 1_900 }, width: 60, amp: decay(0.05)), 0.4)),
           (0.15, hiss(0.5, seed: 16, cutoff: { _ in 4_000 }, amp: { t in 0.3 * envelope(attack: 0.05, release: 0.3, length: 0.5)(t) }))])
}

/// A car door: a firm thud and the rattle of the window in its frame.
func carDoor() -> [Double] {
    place([(0, hiss(0.1, seed: 17, cutoff: { _ in 140 }, amp: decay(0.025))),
           (0, voice(0.15, pitch: slide(90, 50, over: 0.1), amp: decay(0.05))),
           (0.035, gain(tick(18, 2_200), 0.5)), (0.07, gain(tick(19, 1_700), 0.5)), (0.1, gain(tick(20, 2_600), 0.5))])
}

/// A camera: the shutter opening and closing, two clicks a frame apart.
func camera() -> [Double] {
    place([(0, tick(21, 3_200)), (0.085, tick(22, 2_600)),
           (0.085, hiss(0.02, seed: 23, cutoff: { _ in 3_000 }, amp: decay(0.006)))])
}

/// A typewriter: a key's clack and the bell at the end of the line.
func typewriter() -> [Double] {
    place([(0, hiss(0.03, seed: 24, cutoff: { _ in 3_500 }, amp: decay(0.006))), (0, tick(25, 1_200)),
           (0.05, gain(voice(0.6, wave: { sine($0) + 0.4 * sine(2.7 * $0) }, pitch: { _ in 2_500 }, amp: decay(0.18)), 0.5))])
}

/// A cash register: the drawer's clack and two bell notes, "cha-ching".
func cashRegister() -> [Double] {
    func bell(_ pitch: Double) -> [Double] {
        voice(0.5, wave: { sine($0) + 0.5 * sine(2.4 * $0) + 0.2 * sine(4.1 * $0) }, pitch: { _ in pitch }, amp: decay(0.15))
    }
    return place([(0, hiss(0.04, seed: 26, cutoff: { _ in 2_500 }, amp: decay(0.008))),
                  (0.04, gain(bell(2_093), 0.4)), (0.17, gain(bell(2_637), 0.4))])
}

/// A zip closing: a click per tooth, closer together as the pull speeds up, each a little
/// higher than the last.
func zipper() -> [Double] {
    var parts: [(Double, [Double])] = []
    var at = 0.0, i: UInt64 = 100
    while at < 0.42 {
        parts.append((at, gain(tick(i, 1_200 + 1_800 * at / 0.42), 0.35)))
        at += 0.014 - 0.007 * at / 0.42
        i += 1
    }
    return place(parts)
}

/// A suitcase clasp: a light click, then the firmer one that holds.
func latch() -> [Double] {
    place([(0, gain(tick(30, 2_800), 0.6)), (0.06, tick(31, 1_500)),
           (0.06, hiss(0.03, seed: 32, cutoff: { _ in 1_200 }, amp: decay(0.008)))])
}

/// A kettle's hiss, rising, cut off at the switch.
func steam() -> [Double] {
    let raw = hiss(0.6, seed: 33, cutoff: { _ in 9_000 }, amp: { t in min(1, t / 0.25) * (t < 0.55 ? 1 : max(0, (0.6 - t) / 0.05)) })
    return place([(0, thin(raw, cutoff: 1_500)), (0.55, gain(tick(34, 2_000), 0.5))])
}

/// An elevator arriving: one clear bell.
func ding() -> [Double] {
    voice(0.8, wave: { sine($0) + 0.3 * sine(2 * $0) + 0.15 * sine(3.01 * $0) }, pitch: { _ in 1_047 },
          amp: { t in decay(0.25)(t) * min(1, t / 0.002) })
}

// MARK: Retro (square waves, the way a 1980s chip made them)

/// A jump: a square wave sliding up.
func jump() -> [Double] {
    voice(0.2, wave: square, pitch: slide(180, 900, over: 0.15), amp: { t in 0.5 * envelope(attack: 0.005, release: 0.05, length: 0.2)(t) })
}

/// Four notes down the scale, the last one held: no more lives.
func gameOver() -> [Double] {
    let notes: [(Double, Double)] = [(523.3, 0.16), (440, 0.16), (349.2, 0.16), (261.6, 0.4)]
    var parts: [(Double, [Double])] = []
    var at = 0.0
    for (pitch, length) in notes {
        parts.append((at, voice(length, wave: square, pitch: { _ in pitch },
                                amp: { t in 0.5 * envelope(attack: 0.005, release: length > 0.2 ? 0.2 : 0.03, length: length)(t) })))
        at += length + 0.02
    }
    return place(parts)
}

/// A chip crashing: short square bursts at pitches nobody chose, some missing.
func glitch() -> [Double] {
    var noise = Noise(state: 0xDEAD_BEEF_1234_5678)
    var parts: [(Double, [Double])] = []
    for i in 0..<14 {
        let pitch = 150 * pow(2, (noise.next() + 1) * 2)   // 150 … 2400 Hz
        if noise.next() > -0.3 {
            parts.append((Double(i) * 0.022, voice(0.018, wave: square, pitch: { _ in pitch }, amp: { _ in 0.5 })))
        }
    }
    return place(parts)
}

/// A warp drive winding down: a saw falling four octaves with a tremble in it.
func warp() -> [Double] {
    voice(0.55, wave: saw, pitch: slide(900, 50, over: 0.5),
          amp: { t in (0.6 + 0.4 * sine(28 * t)) * envelope(attack: 0.01, release: 0.1, length: 0.55)(t) })
}

/// A dial-up handshake, abridged: the answer tone, two chirps trading places, the hiss of data.
func modem() -> [Double] {
    var parts: [(Double, [Double])] = [(0, voice(0.18, pitch: { _ in 2_100 }, amp: envelope(attack: 0.01, release: 0.01, length: 0.18)))]
    var at = 0.22
    for i in 0..<4 {
        parts.append((at, voice(0.07, pitch: { _ in i % 2 == 0 ? 1_200 : 2_250 }, amp: envelope(attack: 0.005, release: 0.005, length: 0.07))))
        at += 0.08
    }
    parts.append((at + 0.03, hiss(0.35, seed: 40, cutoff: { _ in 3_500 }, amp: { t in 0.6 * envelope(attack: 0.01, release: 0.1, length: 0.35)(t) })))
    return gain(place(parts), 0.5)
}

/// "73" in Morse, radio code for best regards, at twenty words a minute.
func morse() -> [Double] {
    let dit = 0.06
    func beep(_ length: Double) -> [Double] { voice(length, pitch: { _ in 700 }, amp: envelope(attack: 0.004, release: 0.004, length: length)) }
    var parts: [(Double, [Double])] = []
    var at = 0.0
    for symbol in "--... ...--" {
        switch symbol {
        case "-": parts.append((at, beep(3 * dit))); at += 4 * dit
        case ".": parts.append((at, beep(dit))); at += 2 * dit
        default: at += 2 * dit    // with the dit already waited, three between letters
        }
    }
    return gain(place(parts), 0.6)
}

/// A laser: a saw and a square falling together, with a fast warble.
func laser() -> [Double] {
    voice(0.16, wave: { saw($0) * 0.5 + square($0) * 0.5 },
          pitch: { t in slide(2_400, 180, over: 0.14)(t) * (1 + 0.05 * sin(twoPi * 90 * t)) },
          amp: { t in 0.5 * envelope(attack: 0.003, release: 0.04, length: 0.16)(t) })
}

/// Five notes up a major chord, the last one held: a level cleared.
func levelUp() -> [Double] {
    let notes = [261.6, 329.6, 392, 523.3, 659.3]
    return place(notes.enumerated().map { i, pitch in
        let last = i == notes.count - 1
        let length = last ? 0.3 : 0.06
        return (Double(i) * 0.065, voice(length, wave: square, pitch: { _ in pitch },
                                         amp: { t in 0.45 * envelope(attack: 0.003, release: last ? 0.15 : 0.01, length: length)(t) }))
    })
}

// MARK: Night

/// A yawn: a voice rising and falling through an open mouth, with breath around it.
func yawn() -> [Double] {
    var mouth = Resonator(), throat = Resonator()
    let swell: (Double) -> Double = { t in pow(sin(Double.pi * t / 1.0), 1.5) }
    let raw = place([(0, voice(1.0, wave: saw, pitch: { t in 130 + 90 * sin(Double.pi * t) }, amp: swell)),
                     (0, hiss(1.0, seed: 50, cutoff: { _ in 2_500 }, amp: { t in 0.12 * swell(t) }))])
    return raw.enumerated().map { i, s in
        let t = Double(i) / sampleRate
        return mouth.step(s, centre: 700 + 500 * sin(Double.pi * t), width: 150) + 0.5 * throat.step(s, centre: 1_200, width: 200)
    }
}

/// A snore: low noise fluttering at the back of a throat, in and out.
func snore() -> [Double] {
    hiss(0.9, seed: 51, cutoff: { _ in 500 }, amp: { t in pow(sin(Double.pi * t / 0.9), 1.2) * (0.35 + 0.65 * max(0, sine(26 * t))) })
}

/// Four music-box notes, stepping down.
func lullaby() -> [Double] {
    place(zip([784, 659.3, 587.3, 523.3], [0, 0.22, 0.44, 0.66]).map { pitch, at in (at, musicBox(pitch)) })
}

/// A wind chime: five high notes struck as the air moves them, left to ring together.
func windChime() -> [Double] {
    place(zip([1_760, 2_093, 2_349, 2_794, 2_093], [0, 0.11, 0.29, 0.4, 0.62]).map { pitch, at in
        (at, gain(voice(1.0, wave: { sine($0) + 0.3 * sine(2.76 * $0) }, pitch: { _ in pitch },
                        amp: { t in decay(0.35)(t) * min(1, t / 0.002) }), 0.5))
    })
}

/// A gong: six partials that do not line up as a chord, the low ones outlasting the high,
/// with a slow shimmer.
func gong() -> [Double] {
    let partials: [(pitch: Double, level: Double, tau: Double)] =
        [(82, 1.0, 1.4), (131, 0.7, 1.1), (193, 0.5, 0.9), (262, 0.4, 0.7), (357, 0.3, 0.5), (523, 0.2, 0.35)]
    return place([(0, gain(hiss(0.05, seed: 52, cutoff: { _ in 1_500 }, amp: decay(0.01)), 0.5))] + partials.map { partial in
        (0, voice(1.7, pitch: { t in partial.pitch * (1 + 0.003 * sin(twoPi * 3 * t)) },
                  amp: { t in partial.level * decay(partial.tau)(t) * min(1, t / 0.02) }))
    })
}

/// An owl: two soft hoots, the second longer, with air in the tone.
func owl() -> [Double] {
    func hoot(_ length: Double, seed: UInt64) -> [Double] {
        let shape = envelope(attack: 0.05, release: 0.08, length: length)
        return place([(0, voice(length, wave: { sine($0) + 0.2 * sine(2 * $0) }, pitch: { t in 390 - 40 * t / length }, amp: shape)),
                      (0, ring(length, seed: seed, centre: { _ in 400 }, width: 100, amp: { t in 0.3 * shape(t) }))])
    }
    return place([(0, hoot(0.22, seed: 53)), (0.3, hoot(0.3, seed: 54))])
}

/// Crickets: a chirp is three quick pulses of a high tone; one every quarter second, fading.
func crickets() -> [Double] {
    var parts: [(Double, [Double])] = []
    for chirp in 0..<5 {
        for pulse in 0..<3 {
            parts.append((Double(chirp) * 0.25 + Double(pulse) * 0.03,
                          voice(0.018, pitch: { _ in 4_300 }, amp: { t in 0.35 * (1 - Double(chirp) / 6) * envelope(attack: 0.004, release: 0.006, length: 0.018)(t) })))
        }
    }
    return place(parts)
}

/// A candle blown out: the puff, and the flame going.
func candle() -> [Double] {
    place([(0, hiss(0.15, seed: 55, cutoff: { _ in 1_800 }, amp: envelope(attack: 0.03, release: 0.08, length: 0.15))),
           (0.1, hiss(0.3, seed: 56, cutoff: slide(1_200, 300, over: 0.3), amp: { t in 0.6 * envelope(attack: 0.02, release: 0.2, length: 0.3)(t) }))])
}

// MARK: Encore

/// Applause: hundreds of claps, none alike, each a short bright burst at its own moment and
/// level, thickest in the middle, heard from the back of the room.
func applause() -> [Double] {
    var noise = Noise(state: 0x1234_5678_9ABC_DEF1)
    var out = [Double](repeating: 0, count: seconds(1.9))
    var t = 0.0
    while t < 1.8 {
        let start = seconds(t), level = 0.5 + 0.5 * noise.next()
        for k in 0..<seconds(0.012) where start + k < out.count {
            out[start + k] += noise.next() * level * exp(-Double(k) / sampleRate / 0.003)
        }
        let density = 20 + 180 * sin(Double.pi * min(1, t / 1.8))   // claps per second
        t += (0.5 + (noise.next() + 1) * 0.5) / density
    }
    var room = Resonator()
    return soften(out.map { room.step($0, centre: 1_500, width: 1_200) * 3 + $0 * 0.3 }, cutoff: 5_000)
}

/// "Ta-da": a pickup note and a major chord that lands, in brass.
func tada() -> [Double] {
    gain(place([(0, brass(392, 0.16, release: 0.03))] + [523.3, 659.3, 784, 1_046.5].map { (0.18, brass($0, 0.9, release: 0.25)) }), 0.3)
}

/// A drum roll: snare hits closer and closer together, louder as they go, and the crash.
func drumRoll() -> [Double] {
    var parts: [(Double, [Double])] = []
    var at = 0.0, k: UInt64 = 200
    while at < 1.3 {
        parts.append((at, gain(snare(k), 0.5 + 0.4 * at / 1.3)))
        at += 0.055 - 0.028 * at / 1.3
        k += 1
    }
    parts.append((1.32, snare(300)))
    parts.append((1.32, cymbal(301)))
    return place(parts)
}

/// "Ba-dum-tss": two toms, the snare, the cymbal. The joke was that bad.
func baDumTss() -> [Double] {
    place([(0, tom(240, 302)), (0.13, tom(180, 303)), (0.16, snare(304)), (0.3, cymbal(305))])
}

/// Three low brass notes, the third a step up and held with a tremble: the one that means
/// "and then…".
func dunDunDun() -> [Double] {
    func note(_ pitch: Double, _ length: Double) -> [Double] {
        var low = LowPass()
        let raw = voice(length, wave: { saw($0) + 0.5 * saw(0.5 * $0) },
                        pitch: { t in pitch * (1 + 0.012 * sin(twoPi * 6 * t) * min(1, t / 0.3)) },
                        amp: envelope(attack: 0.03, release: length > 0.5 ? 0.45 : 0.05, length: length))
        return raw.map { low.step($0, cutoff: 900) }
    }
    return gain(place([(0, note(146.8, 0.28)), (0.33, note(146.8, 0.28)), (0.66, note(155.6, 1.1))]), 0.4)
}

/// A record scratch: the needle dragged back, then forward, the pitch following the hand.
func recordScratch() -> [Double] {
    place([(0, ring(0.22, seed: 60, centre: { t in 500 * pow(5, 1 - t / 0.22) }, width: 300, amp: envelope(attack: 0.01, release: 0.03, length: 0.22))),
           (0.24, ring(0.15, seed: 61, centre: { t in 500 * pow(4, t / 0.15) }, width: 300, amp: envelope(attack: 0.01, release: 0.03, length: 0.15)))])
}

/// A cinema boom: a sine too low to name, falling, driven hard so it has an edge, with a
/// thud on top.
func boom() -> [Double] {
    let sub = voice(0.7, pitch: slide(75, 32, over: 0.5), amp: { t in decay(0.3)(t) * min(1, t / 0.005) })
    return place([(0, sub.map { tanh(3 * $0) * 0.8 }), (0, hiss(0.06, seed: 62, cutoff: { _ in 220 }, amp: decay(0.015)))])
}

/// The two-note wolf whistle: up, a breath, then up and away down, with a little air in it.
func whistle() -> [Double] {
    func note(_ length: Double, pitch: @escaping (Double) -> Double, seed: UInt64, release: Double) -> [Double] {
        let shape = envelope(attack: 0.02, release: release, length: length)
        return place([(0, voice(length, pitch: pitch, amp: shape)),
                      (0, ring(length, seed: seed, centre: pitch, width: 150, amp: { t in 0.2 * shape(t) }))])
    }
    let first = note(0.25, pitch: slide(900, 1_900, over: 0.25), seed: 63, release: 0.03)
    let second = note(0.45, pitch: { t in t < 0.1 ? slide(1_700, 2_100, over: 0.1)(t) : slide(2_100, 700, over: 0.35)(t - 0.1) }, seed: 64, release: 0.12)
    return place([(0, first), (0.3, second)])
}

// MARK: Tune (one note per close, with "In order")

/// Beethoven's Ode to Joy, the first phrase, fifteen notes: E E F G G F E D C C D E E D D.
func odeToJoy() -> [Double] {
    tune([659.3, 659.3, 698.5, 784, 784, 698.5, 659.3, 587.3, 523.3, 523.3, 587.3, 659.3, 659.3, 587.3, 587.3], slot: 0.6)
}

// MARK: Writing

/// A raised-cosine edge at both ends, then the peak to -6 dBFS (edges first, or a clip
/// whose loudest moment is its first would come out quiet).
func finish(_ samples: [Double]) -> [Double] {
    let edge = seconds(0.005)
    let shaped = samples.enumerated().map { i, s in
        let fromStart = Double(i) / Double(edge), fromEnd = Double(samples.count - 1 - i) / Double(edge)
        let window = min(1, max(0, min(fromStart, fromEnd)))
        return s * (0.5 - 0.5 * cos(.pi * window))
    }
    let peak = shaped.map(abs).max() ?? 1
    let gain = peak > 0 ? 0.5 / peak : 1
    return shaped.map { $0 * gain }
}

/// RIFF/WAVE, 16-bit PCM, little-endian, written by hand: eight lines, no framework.
func wav(_ samples: [Double]) -> Data {
    var data = Data()
    func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes)); data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
    put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); put(bytes)
    for s in samples { put(Int16(max(-1, min(1, s)) * 32_767)) }
    return data
}

/// WAV to AAC in an .m4a through afconvert, which every Mac has. 96 kb/s is more than a
/// sound under two seconds needs; a tune's parts are cut on the decoded samples, so the
/// format does not move them.
func encode(_ wavURL: URL, to m4aURL: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    task.arguments = ["-f", "m4af", "-d", "aac", "-b", "96000", "-q", "127", wavURL.path, m4aURL.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { throw NSError(domain: "make-sounds", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "afconvert failed for \(m4aURL.lastPathComponent)"]) }
}

let asWav: [(String, () -> [Double])] = [("Click", click), ("Breath", breath), ("Hum", hum)]
let asM4a: [(String, () -> [Double])] = [
    // Starters
    ("Blob", blob), ("Pop", pop), ("Boing", boing), ("Coin", coin), ("CRTOff", crtOff),
    // Pops
    ("Plop", plop), ("Bloop", bloop), ("Bubble", bubble), ("Cork", cork), ("Drip", drip), ("Squelch", squelch),
    // Toys
    ("SlideWhistle", slideWhistle), ("Bonk", bonk), ("Squeak", squeak), ("SadTrombone", sadTrombone), ("Kazoo", kazoo), ("Honk", honk), ("DoorStop", doorStop),
    // Machines
    ("PowerDown", powerDown), ("Vault", vault), ("CarDoor", carDoor), ("Camera", camera), ("Typewriter", typewriter),
    ("CashRegister", cashRegister), ("Zipper", zipper), ("Latch", latch), ("Steam", steam), ("Ding", ding),
    // Retro
    ("Jump", jump), ("GameOver", gameOver), ("Glitch", glitch), ("Warp", warp), ("Modem", modem), ("Morse", morse), ("Laser", laser), ("LevelUp", levelUp),
    // Night
    ("Yawn", yawn), ("Snore", snore), ("Lullaby", lullaby), ("WindChime", windChime), ("Gong", gong), ("Owl", owl), ("Crickets", crickets), ("Candle", candle),
    // Encore
    ("Applause", applause), ("TaDa", tada), ("DrumRoll", drumRoll), ("BaDumTss", baDumTss), ("DunDunDun", dunDunDun),
    ("RecordScratch", recordScratch), ("Boom", boom), ("Whistle", whistle),
    // Tune
    ("OdeToJoy", odeToJoy),
]

let out = URL(fileURLWithPath: "Sources/ShutApp/Resources/Sounds")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("make-sounds-\(ProcessInfo.processInfo.processIdentifier)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func report(_ name: String, _ samples: [Double], _ url: URL) throws {
    let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
    print(String(format: "%-18@ %5.2f s  %7d bytes", name, Double(samples.count) / sampleRate, bytes))
}
for (name, make) in asWav {
    let samples = finish(make())
    let url = out.appendingPathComponent("\(name).wav")
    try wav(samples).write(to: url)
    try report("\(name).wav", samples, url)
}
for (name, make) in asM4a {
    let samples = finish(make())
    let temp = scratch.appendingPathComponent("\(name).wav")
    try wav(samples).write(to: temp)
    let url = out.appendingPathComponent("\(name).m4a")
    try? FileManager.default.removeItem(at: url)
    try encode(temp, to: url)
    try report("\(name).m4a", samples, url)
}
