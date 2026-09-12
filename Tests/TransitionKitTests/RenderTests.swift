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

    func meanAlpha(_ bytes: [UInt8]) -> Double {
        var sum = 0
        var i = 3
        while i < bytes.count { sum += Int(bytes[i]); i += 4 }
        return Double(sum) / Double(bytes.count / 4) / 255
    }

    func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        var i = 0
        while i < a.count { if i % 4 != 3 { sum += abs(Int(a[i]) - Int(b[i])) }; i += 1 }
        return Double(sum) / Double(a.count / 4 * 3) / 255
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
        // Fade is a transparent overlay: clear at 0, opaque black at 1.
        let frames = try renderFrames(AnyTransition(FadeTransition()), progresses: [0, 0.5, 1])
        XCTAssertLessThan(meanAlpha(frames[0].1), 0.01)
        XCTAssertGreaterThan(meanAlpha(frames[2].1), 0.99)
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


extension RenderTests {
    static let imageStyles: [AnyTransition] = [
        AnyTransition(FoldTransition()), AnyTransition(CreaseTransition()), AnyTransition(CurlTransition()),
        AnyTransition(RecedeTransition()), AnyTransition(SlideTransition()),
    ]
    static let maskStyles: [AnyTransition] = [
        AnyTransition(ApertureTransition()), AnyTransition(ShutterTransition()),
        AnyTransition(BlindsTransition()), AnyTransition(FadeTransition()),
    ]

    /// At progress 0 every snapshot style must show the snapshot untouched.
    func testImageStylesAreIdentityAtZero() throws {
        let reference = try renderFrames(AnyTransition(RecedeTransition()), progresses: [0])[0].1
        XCTAssertGreaterThan(meanBrightness(reference), 0.3)
        for style in Self.imageStyles {
            let frame = try renderFrames(style, progresses: [0])[0].1
            XCTAssertLessThan(meanAbsDiff(frame, reference), 1.5 / 255, "\(style.id) is not identity at 0")
            XCTAssertGreaterThan(meanAlpha(frame), 0.99, "\(style.id) must be opaque at 0")
        }
    }

    func testImageStylesDarkenMonotonicallyAndEndBlack() throws {
        for style in Self.imageStyles {
            let b = try renderFrames(style, progresses: [0, 0.25, 0.5, 0.75, 1]).map { meanBrightness($0.1) }
            for i in 1..<b.count {
                XCTAssertLessThanOrEqual(b[i], b[i - 1] + 0.01, "\(style.id) brightened between \(i - 1) and \(i)")
            }
            XCTAssertLessThan(b[4], 0.02, "\(style.id) must end black")
        }
    }

    /// Mask styles composite over the live desktop: clear at 0, opaque black at 1.
    func testMaskStylesSeeThrough() throws {
        for style in Self.maskStyles {
            let frames = try renderFrames(style, progresses: [0, 0.5, 1])
            XCTAssertLessThan(meanAlpha(frames[0].1), 0.01, "\(style.id) should be clear at 0")
            // The iris and blinds close quickly by design, so mid-travel can already
            // be mostly covered; the point is that it is neither clear nor sealed.
            let mid = meanAlpha(frames[1].1)
            XCTAssertTrue((0.02...0.98).contains(mid), "\(style.id) mid alpha \(mid)")
            XCTAssertGreaterThan(meanAlpha(frames[2].1), 0.99, "\(style.id) should be opaque at 1")
            XCTAssertLessThan(meanBrightness(frames[2].1), 0.01, "\(style.id) should be black at 1")
        }
    }

    /// Proves the placeholder-texture path: no snapshot was ever set.
    func testMaskStylesNeedNoSnapshot() throws {
        let renderer = try TransitionRenderer()
        let w = Self.width, h = Self.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: TransitionRenderer.pixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
        let target = renderer.device.makeTexture(descriptor: desc)!
        let context = RenderContext(snapshotSize: SIMD2(Float(w), Float(h)), sinkPoint: .zero, notchSize: .zero, usesVirtualNotch: true)
        renderer.render(to: target, transition: AnyTransition(ApertureTransition()), progress: 0.5, context: context)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let alpha = meanAlpha(bytes)
        XCTAssertTrue((0.02...0.98).contains(alpha), "aperture without a snapshot rendered alpha \(alpha)")
    }
}

@MainActor
final class ThumbnailTests: XCTestCase {
    func testPlaceholderDesktopDraws() throws {
        let image = try XCTUnwrap(PlaceholderDesktop.image())
        XCTAssertEqual(image.width, 1024); XCTAssertEqual(image.height, 640)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"] {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("placeholder-desktop.png"))
        }
    }

    func testThumbnailsCacheAndComposite() throws {
        let thumbnails = try TransitionThumbnailRenderer()
        let fold = AnyTransition(FoldTransition())
        let first = try XCTUnwrap(thumbnails.image(for: fold))
        let second = try XCTUnwrap(thumbnails.image(for: fold))
        XCTAssertTrue(first === second, "second call is served from the cache")
        XCTAssertEqual(first.width, TransitionThumbnailRenderer.size.width)

        let aperture = try XCTUnwrap(thumbnails.image(for: AnyTransition(ApertureTransition())))
        XCTAssertEqual(aperture.alphaInfo, .premultipliedFirst)
        if let dir = ProcessInfo.processInfo.environment["SHUT_FRAME_DUMP"] {
            for t in [fold, AnyTransition(ApertureTransition()), AnyTransition(SinkholeTransition()), AnyTransition(BlindsTransition())] {
                if let img = thumbnails.image(for: t) {
                    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("thumb-\(t.id).png"))
                }
            }
        }
        thumbnails.invalidate(id: fold.id)
        let third = try XCTUnwrap(thumbnails.image(for: fold))
        XCTAssertFalse(first === third, "invalidation drops the cached image")
    }
}
