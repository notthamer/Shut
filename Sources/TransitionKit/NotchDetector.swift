import AppKit

/// Where the sink is. Everything in snapshot pixels, top-left origin.
public struct SinkGeometry: Equatable {
    public var sinkPoint: SIMD2<Float>
    public var notchSize: SIMD2<Float>
    public var isVirtual: Bool
}

/// Finds the notch on the built-in display.
///
/// macOS 12+ exposes the two "safe" menu bar regions either side of the notch as
/// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. When both exist, the notch
/// is the gap between them and the sink is the middle of its bottom edge. On a
/// Mac without a notch both areas are zero rects, and we fall back to a virtual
/// pill at the top centre so the drain still has somewhere to go.
public enum NotchDetector {
    /// Virtual notch dimensions in points, roughly a 14" MacBook Pro notch.
    public static let virtualNotchSize = CGSize(width: 180, height: 32)

    public static func geometry(for screen: NSScreen?, offset: CGPoint = .zero) -> SinkGeometry {
        guard let screen else {
            return SinkGeometry(sinkPoint: SIMD2(0, 0), notchSize: .zero, isVirtual: true)
        }
        let scale = Float(screen.backingScaleFactor)
        let frame = screen.frame
        let left = screen.auxiliaryTopLeftArea ?? .zero
        let right = screen.auxiliaryTopRightArea ?? .zero
        let hasNotch = left.width > 0 && right.width > 0

        let notchWidthPt: CGFloat
        let notchHeightPt: CGFloat
        let centerXPt: CGFloat
        if hasNotch {
            notchWidthPt = right.minX - left.maxX
            notchHeightPt = left.height
            centerXPt = (left.maxX + right.minX) / 2 - frame.minX
        } else {
            notchWidthPt = virtualNotchSize.width
            notchHeightPt = virtualNotchSize.height
            centerXPt = frame.width / 2
        }
        // Convert from AppKit's bottom-left origin to the shader's top-left origin.
        let sinkX = (centerXPt + offset.x) * CGFloat(scale)
        let sinkY = (notchHeightPt + offset.y) * CGFloat(scale)
        return SinkGeometry(
            sinkPoint: SIMD2(Float(sinkX), Float(sinkY)),
            notchSize: SIMD2(Float(notchWidthPt) * scale, Float(notchHeightPt) * scale),
            isVirtual: !hasNotch
        )
    }
}
