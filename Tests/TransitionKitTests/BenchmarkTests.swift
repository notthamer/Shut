import XCTest
import Metal
@testable import TransitionKit

/// Full-resolution frame cost for each transition, as the overlay would pay it on
/// a 14" MacBook Pro. Prints the numbers; asserts only a generous ceiling.
final class BenchmarkTests: XCTestCase {
    func testFullResolutionFrameTimes() throws {
        let w = 3024, h = 1964
        let renderer = try TransitionRenderer()
        // Synthetic snapshot: a gradient, never a real screen.
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            pixels[i] = UInt8(x * 255 / w); pixels[i + 1] = UInt8(y * 255 / h); pixels[i + 2] = 128; pixels[i + 3] = 255
        } }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]; desc.storageMode = .shared
        let snapshot = renderer.device.makeTexture(descriptor: desc)!
        snapshot.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        renderer.setSnapshot(texture: snapshot)

        let targetDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        targetDesc.usage = [.renderTarget]; targetDesc.storageMode = .private
        let target = renderer.device.makeTexture(descriptor: targetDesc)!
        let context = RenderContext(snapshotSize: SIMD2(Float(w), Float(h)), sinkPoint: SIMD2(1512, 64),
                                    notchSize: SIMD2(360, 64), usesVirtualNotch: false, scale: 2)

        for transition in [AnyTransition(SinkholeTransition()), AnyTransition(FrostTransition()), AnyTransition(FadeTransition())] {
            renderer.render(to: target, transition: transition, progress: 0.4, context: context)  // warm up + prepare
            let frames = 60
            let start = CACurrentMediaTime()
            for i in 0..<frames {
                renderer.render(to: target, transition: transition, progress: Double(i) / Double(frames), context: context)
            }
            let ms = (CACurrentMediaTime() - start) * 1000 / Double(frames)
            print(String(format: "BENCH %@: %.2f ms/frame at %dx%d (round trip incl. CPU wait)", transition.id, ms, w, h))
            XCTAssertLessThan(ms, 16, "\(transition.id) too slow for 60 Hz")
        }
    }
}
