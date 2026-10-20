#!/usr/bin/env swift
// Generates the three starter sounds for Lid sound, so the feature works before anyone adds
// a file of their own. Pure Swift and Foundation: every sample is computed here, nothing is
// recorded or borrowed, so no licence applies. Deterministic (a seeded generator), so
// running it again writes the same bytes.
//
//   swift scripts/make-sounds.swift        -> Sources/ShutApp/Resources/Sounds/{Click,Breath,Hum}.wav
//
// Each clip is under a second, 48 kHz mono 16-bit PCM, peak-normalised to -6 dBFS with a
// 5 ms raised-cosine edge at both ends so nothing ever clicks that was not meant to.
import Foundation

let sampleRate = 48_000.0

/// xorshift64*, seeded: the "noise" in Click and Breath is the same every run.
struct Noise {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
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
        let a = 1 - exp(-2 * .pi * cutoff / sampleRate)
        y += a * (x - y)
        return y
    }
}

func seconds(_ s: Double) -> Int { Int(s * sampleRate) }

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

let out = URL(fileURLWithPath: "Sources/ShutApp/Resources/Sounds")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, make) in [("Click", click), ("Breath", breath), ("Hum", hum)] {
    let samples = finish(make())
    let url = out.appendingPathComponent("\(name).wav")
    try wav(samples).write(to: url)
    let peak = samples.map(abs).max() ?? 0
    print(String(format: "%@.wav  %.2f s  peak %.2f  %d bytes", name, Double(samples.count) / sampleRate, peak, samples.count * 2 + 44))
}
