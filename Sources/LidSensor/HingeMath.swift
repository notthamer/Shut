import Foundation

@inlinable func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

@inlinable func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Maps `value` from `range` into 0...1, clamped. Returns 0 for a degenerate range.
@inlinable func normalize(_ value: Double, in range: ClosedRange<Double>) -> Double {
    let span = range.upperBound - range.lowerBound
    guard span > .ulpOfOne else { return 0 }
    return clamp((value - range.lowerBound) / span, 0, 1)
}
