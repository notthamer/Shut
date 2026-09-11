import XCTest
import AppKit
import Metal
@testable import TransitionKit

/// Renders each transition offscreen on a synthetic image (never a real screen
/// capture) and checks the broad shape of the output. Set SHUT_FRAME_DUMP to
/// a directory to also write PNGs for eyeballing.
final class RenderTests: XCTestCase {
    static let width = 756, height = 491  // 1/4 of a 14" MacBook Pro

    func makeSyntheticSnapshot() -> CGImage {
        let w = Self.width, h = Self.height
        let image = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            NSGradient(colors: [.systemBlue, .systemPurple, .systemOrange])!.draw(in: rect, angle: 30)
            for i in 0..<12 {
                let x = CGFloat(i) * rect.width / 12
                NSColor.white.withAlphaComponent(0.5).setFill()
                NSBezierPath(rect: NSRect(x: x, y: 0, width: 2, height: rect.height)).fill()
            }
            for i in 0..<8 {
                let y = CGFloat(i) * rect.height / 8
                NSColor.white.withAlphaComponent(0.5).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: rect.width, height: 2)).fill()
            }
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.width * 0.6, y: rect.height * 0.3, width: 120, height: 120)).fill()
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: w, height: h)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    func renderFrames(_ transition: AnyTransition, progresses: [Double]) throws -> [(Double, [UInt8])] {
        let renderer = try TransitionRenderer()
        try renderer.setSnapshot(makeSyntheticSnapshot())
        let w = Self.width, h = Self.height
        let context = RenderContext(snapshotSize: SIMD2(Float(w), Float(h)),
                                    sinkPoint: SIMD2(Float(w) / 2, 18), notchSize: SIMD2(90, 18),
                                    usesVirtualNotch: true, scale: 0.5)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: TransitionRenderer.pixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        let target = renderer.device.makeTexture(descriptor: desc)!

        var out: [(Double, [UInt8])] = []
        for p in progresses {
            renderer.render(to: target, transition: transition, progress: p, context: context)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            out.append((p, bytes))
            dump(bytes, name: "\(transition.id)-\(String(format: "%.2f", p))")
        }
        return out
    }

    func meanBrightness(_ bytes: [UInt8]) -> Double {
        var sum = 0
        var i = 0
        while i < bytes.count { sum += Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2]); i += 4 }
        return Double(sum) / Double(bytes.count / 4 * 3) / 255
    }

    func dump(_ bytes: [UInt8], name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"] else { return }
        let w = Self.width, h = Self.height
        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testFadeGoesToBlack() throws {
        let frames = try renderFrames(AnyTransition(FadeTransition()), progresses: [0, 0.5, 1])
        XCTAssertGreaterThan(meanBrightness(frames[0].1), 0.3)
        XCTAssertLessThan(meanBrightness(frames[2].1), 0.01)
    }

    func testSinkholeStartsIntactAndEndsBlack() throws {
        let frames = try renderFrames(AnyTransition(SinkholeTransition()), progresses: [0, 0.25, 0.5, 0.75, 1, -0.06, 0.05, 0.15, 0.35, 0.6])
        let b = frames.map { meanBrightness($0.1) }
        XCTAssertGreaterThan(b[0], 0.3, "p = 0 shows the snapshot untouched")
        XCTAssertGreaterThan(b[0], b[1], "brightness falls as content drains")
        XCTAssertGreaterThan(b[1], b[2])
        XCTAssertGreaterThan(b[2], b[3])
        XCTAssertLessThan(b[4], 0.01, "p = 1 is black")
        XCTAssertGreaterThan(b[5], 0.3, "pour-out overshoot still shows the snapshot")
    }
}

extension RenderTests {
    func testFrostBlursFromTopAndEndsBlack() throws {
        let frames = try renderFrames(AnyTransition(FrostTransition()), progresses: [0, 0.35, 0.7, 1])
        let b = frames.map { meanBrightness($0.1) }
        XCTAssertGreaterThan(b[0], 0.3)
        XCTAssertGreaterThan(b[1], b[2], "darkens after darknessStart")
        XCTAssertLessThan(b[3], 0.01, "p = 1 is black")
    }
}
