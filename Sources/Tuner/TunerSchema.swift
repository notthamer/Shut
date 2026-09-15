import Foundation

// The declarative half of Tuner. A parameter struct describes its own controls
// with key paths; the panel (TunerPanelView) renders whatever the schema says.
// Nothing in this file imports SwiftUI so the schema can be used headlessly,
// for example by a CLI that validates presets.

/// A struct of tunable values. Conformers are plain `Codable` structs so presets
/// are just JSON of the struct.
public protocol TunableParameters: Codable, Equatable {
    /// Stable identifier used for UserDefaults keys and preset folders, e.g. "sinkhole".
    static var tunerID: String { get }
    /// Human-readable name shown in pickers.
    static var tunerDisplayName: String { get }
    /// The values a fresh install starts with.
    static var defaults: Self { get }
    /// The controls Tuner shows for this struct.
    static var schema: TunerSchema<Self> { get }
}

public struct TunerSchema<P> {
    public var folders: [TunerFolder<P>]
    public init(_ folders: [TunerFolder<P>]) { self.folders = folders }
}

public struct TunerFolder<P> {
    public var name: String
    public var controls: [TunerControl<P>]
    /// Start closed in the panel (the user can always open it).
    public var collapsed: Bool
    public init(_ name: String, collapsed: Bool = false, _ controls: [TunerControl<P>]) {
        self.name = name
        self.controls = controls
        self.collapsed = collapsed
    }
}

// MARK: - Value types that controls edit

/// RGBA in 0...1. Kept independent of SwiftUI so parameter structs stay Codable
/// and platform-neutral.
public struct TunerColor: Codable, Equatable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let white = TunerColor(red: 1, green: 1, blue: 1)
    public static let black = TunerColor(red: 0, green: 0, blue: 0)
}

/// A cubic Bézier easing curve from (0,0) to (1,1), like CSS `cubic-bezier`.
public struct TunerBezier: Codable, Equatable, Sendable {
    public var x1: Double, y1: Double, x2: Double, y2: Double
    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }
    public static let linear = TunerBezier(0, 0, 1, 1)
    public static let easeIn = TunerBezier(0.45, 0, 0.85, 0.55)
    public static let easeOut = TunerBezier(0.15, 0.45, 0.55, 1)
    public static let easeInOut = TunerBezier(0.42, 0, 0.58, 1)

    /// Evaluates y for a given x in 0...1.
    ///
    /// The curve is parametric in t, so we first solve x(t) = x with a few Newton
    /// steps (fast for well-behaved curves), then fall back to bisection if the
    /// derivative is tiny. This is the same approach browsers use.
    public func value(at x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x == 0 || x == 1 { return x }
        var t = x
        for _ in 0..<8 {
            let xt = sample(t, x1, x2) - x
            let dx = derivative(t, x1, x2)
            if abs(xt) < 1e-6 { return sample(t, y1, y2) }
            if abs(dx) < 1e-6 { break }
            t -= xt / dx
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<32 {
            let xt = sample(t, x1, x2)
            if abs(xt - x) < 1e-6 { break }
            if xt < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sample(t, y1, y2)
    }

    /// Bezier with P0 = 0 and P3 = 1 collapses to this polynomial.
    private func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * a + 6 * mt * t * (b - a) + 3 * t * t * (1 - b)
    }
}

// MARK: - Controls

/// One row in the panel. Controls read and write the parameter struct through
/// closures built from key paths, so the panel never needs to know concrete
/// property types.
public enum TunerControl<P> {
    case slider(SliderSpec<P>)
    case toggle(ToggleSpec<P>)
    case color(ColorSpec<P>)
    case spring(SpringSpec<P>)
    case bezier(BezierSpec<P>)
    case segmented(SegmentedSpec<P>)
    case action(ActionSpec<P>)

    /// True for the dials a host may surface in a compact "Feel" section.
    public var isFeatured: Bool {
        if case .slider(let s) = self { return s.featured }
        return false
    }

    public var label: String {
        switch self {
        case .slider(let s): return s.label
        case .toggle(let s): return s.label
        case .color(let s): return s.label
        case .spring(let s): return s.label
        case .bezier(let s): return s.label
        case .segmented(let s): return s.label
        case .action(let s): return s.label
        }
    }

    /// Copies this control's value(s) from `source` into `target`. Used for
    /// "Reset group", which resets only the controls in one folder.
    public func copyValue(from source: P, into target: inout P) {
        switch self {
        case .slider(let s): s.set(&target, s.get(source))
        case .toggle(let s): s.set(&target, s.get(source))
        case .color(let s): s.set(&target, s.get(source))
        case .spring(let s):
            s.setResponse(&target, s.getResponse(source))
            s.setDamping(&target, s.getDamping(source))
        case .bezier(let s): s.set(&target, s.get(source))
        case .segmented(let s): s.setIndex(&target, s.getIndex(source))
        case .action: break
        }
    }
}

public struct SliderSpec<P> {
    public var label: String
    public var range: ClosedRange<Double>
    public var step: Double?
    public var unit: String
    public var decimals: Int
    /// Surfaced in a host's compact "Feel" section; the full panel shows everything.
    public var featured: Bool
    /// One plain-English line about what the dial does to the picture.
    public var help: String
    public var get: (P) -> Double
    public var set: (inout P, Double) -> Void
}

public struct ToggleSpec<P> {
    public var label: String
    public var get: (P) -> Bool
    public var set: (inout P, Bool) -> Void
}

public struct ColorSpec<P> {
    public var label: String
    public var get: (P) -> TunerColor
    public var set: (inout P, TunerColor) -> Void
}

/// Response (seconds) and damping fraction, the same two knobs SwiftUI's
/// `.spring(response:dampingFraction:)` uses.
public struct SpringSpec<P> {
    public var label: String
    public var responseRange: ClosedRange<Double>
    public var dampingRange: ClosedRange<Double>
    public var getResponse: (P) -> Double
    public var setResponse: (inout P, Double) -> Void
    public var getDamping: (P) -> Double
    public var setDamping: (inout P, Double) -> Void
}

public struct BezierSpec<P> {
    public var label: String
    public var get: (P) -> TunerBezier
    public var set: (inout P, TunerBezier) -> Void
}

public struct SegmentedSpec<P> {
    public var label: String
    public var options: [String]
    public var getIndex: (P) -> Int
    public var setIndex: (inout P, Int) -> Void
}

public struct ActionSpec<P> {
    public var label: String
    public var run: (inout P) -> Void
}

// MARK: - Convenience constructors (this is the API parameter structs actually use)

public extension TunerControl {
    static func slider(_ keyPath: WritableKeyPath<P, Double>, _ label: String,
                       _ range: ClosedRange<Double>, step: Double? = nil,
                       unit: String = "", decimals: Int = 2,
                       featured: Bool = false, help: String = "") -> TunerControl {
        .slider(SliderSpec(label: label, range: range, step: step, unit: unit, decimals: decimals,
                           featured: featured, help: help,
                           get: { $0[keyPath: keyPath] },
                           set: { $0[keyPath: keyPath] = $1 }))
    }

    static func slider(_ keyPath: WritableKeyPath<P, Int>, _ label: String,
                       _ range: ClosedRange<Int>, unit: String = "",
                       featured: Bool = false, help: String = "") -> TunerControl {
        .slider(SliderSpec(label: label, range: Double(range.lowerBound)...Double(range.upperBound),
                           step: 1, unit: unit, decimals: 0, featured: featured, help: help,
                           get: { Double($0[keyPath: keyPath]) },
                           set: { $0[keyPath: keyPath] = Int($1.rounded()) }))
    }

    static func toggle(_ keyPath: WritableKeyPath<P, Bool>, _ label: String) -> TunerControl {
        .toggle(ToggleSpec(label: label, get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 }))
    }

    static func color(_ keyPath: WritableKeyPath<P, TunerColor>, _ label: String) -> TunerControl {
        .color(ColorSpec(label: label, get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 }))
    }

    static func spring(response: WritableKeyPath<P, Double>, damping: WritableKeyPath<P, Double>,
                       _ label: String,
                       responseRange: ClosedRange<Double> = 0.1...1.5,
                       dampingRange: ClosedRange<Double> = 0.3...1.0) -> TunerControl {
        .spring(SpringSpec(label: label, responseRange: responseRange, dampingRange: dampingRange,
                           getResponse: { $0[keyPath: response] },
                           setResponse: { $0[keyPath: response] = $1 },
                           getDamping: { $0[keyPath: damping] },
                           setDamping: { $0[keyPath: damping] = $1 }))
    }

    static func bezier(_ keyPath: WritableKeyPath<P, TunerBezier>, _ label: String) -> TunerControl {
        .bezier(BezierSpec(label: label, get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 }))
    }

    /// Segmented picker over any `CaseIterable` enum property.
    static func segmented<V: CaseIterable & Equatable>(_ keyPath: WritableKeyPath<P, V>, _ label: String,
                                                       labels: [String]? = nil) -> TunerControl {
        let cases = Array(V.allCases)
        let names = labels ?? cases.map { "\($0)".capitalized }
        return .segmented(SegmentedSpec(label: label, options: names,
                                        getIndex: { cases.firstIndex(of: $0[keyPath: keyPath]) ?? 0 },
                                        setIndex: { $0[keyPath: keyPath] = cases[max(0, min($1, cases.count - 1))] }))
    }

    static func action(_ label: String, _ run: @escaping (inout P) -> Void) -> TunerControl {
        .action(ActionSpec(label: label, run: run))
    }
}
