import TransitionKit
import Tuner

/// Presets that ship with the app. Mirrored as JSON in presets/ for the README.
enum BuiltInPresets {
    static var sinkhole: [(String, SinkholeParams)] {
        var gentle = SinkholeParams()
        gentle.falloff = 0.3
        gentle.twist = 0.15
        gentle.vortex = 0.5
        gentle.stretch = 0.4
        gentle.pull = 0.6
        gentle.blurStrength = 0.3
        gentle.darken = 0.4
        gentle.aberration = 0.5
        gentle.glow = 0.3
        gentle.sinkRadius = 28
        gentle.holeGrowth = 1
        gentle.pourOutDamping = 0.85
        gentle.overshoot = 0.03

        var blackHole = SinkholeParams()
        blackHole.falloff = 1.2
        blackHole.twist = 0.8
        blackHole.vortex = 1.8
        blackHole.stretch = 1.2
        blackHole.pull = 1.1
        blackHole.blurSamples = 12
        blackHole.blurStrength = 0.8
        blackHole.darken = 0.9
        blackHole.aberration = 5
        blackHole.glow = 0.7
        blackHole.glowColor = TunerColor(red: 0.6, green: 0.8, blue: 1.0)
        blackHole.sinkRadius = 60
        blackHole.holeGrowth = 3
        blackHole.commitThreshold = 0.6
        blackHole.pourOutDamping = 0.55
        blackHole.overshoot = 0.12

        return [("Gentle", gentle), ("Default", SinkholeParams()), ("Black Hole", blackHole)]
    }

    static var fold: [(String, FoldParams)] {
        var subtle = FoldParams()
        subtle.intensity = 0.6
        subtle.blur = 0.5
        subtle.washout = 0.5
        return [("Default", FoldParams()), ("Subtle", subtle)]
    }

    static var frost: [(String, FrostParams)] {
        var light = FrostParams()
        light.maxBlur = 24
        light.frostSpread = 0.9
        light.darknessStart = 0.5

        var deep = FrostParams()
        deep.maxBlur = 120
        deep.frostSpread = 0.3
        deep.darknessStart = 0.15
        deep.progressCurve = .easeIn

        return [("Light", light), ("Default", FrostParams()), ("Deep Freeze", deep)]
    }
}
