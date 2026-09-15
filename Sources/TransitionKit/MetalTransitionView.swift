import AppKit
import Metal
import QuartzCore

/// An NSView backed by a CAMetalLayer that draws one transition frame on demand.
///
/// It doesn't own a display link. The overlay drives it from a CADisplayLink at
/// the screen's refresh rate; the preview redraws when a slider moves. Either
/// way, `render()` is the only entry point.
public final class MetalTransitionView: NSView {
    public let renderer: TransitionRenderer
    public var transition: AnyTransition
    public var progress: Double = 0
    public var context: RenderContext

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    public init(renderer: TransitionRenderer, transition: AnyTransition, context: RenderContext) {
        self.renderer = renderer
        self.transition = transition
        self.context = context
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = TransitionRenderer.pixelFormat
        // Tagged sRGB: untagged content would be stretched on a P3 display.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
        layer.isOpaque = !isTransparent
        layer.backgroundColor = isTransparent ? nil : NSColor.black.cgColor
        return layer
    }

    /// Transparent mode: the layer and view report non-opaque and the pass clears
    /// to alpha 0, so mask styles composite over the live desktop.
    public var isTransparent = false {
        didSet {
            guard isTransparent != oldValue, let layer = layer as? CAMetalLayer else { return }
            layer.isOpaque = !isTransparent
            layer.backgroundColor = isTransparent ? nil : NSColor.black.cgColor
        }
    }

    public override var isOpaque: Bool { !isTransparent }

    public override func layout() {
        super.layout()
        updateDrawableSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            metalLayer.contentsScale = scale
        }
    }

    /// When true the view ignores the snapshot and paints solid black.
    public var isBlackedOut = false

    /// At most two frames in flight. `nextDrawable()` blocks the calling thread
    /// when the compositor is behind (a browser hammering the GPU, for instance),
    /// and this runs on the main thread, so rather than wait we drop the frame:
    /// the next display-link tick draws the newest progress anyway.
    private let inFlight = DispatchSemaphore(value: 2)

    /// Draws the current progress (or black). Never blocks: skipped if a frame
    /// can't start this instant.
    public func render() {
        guard bounds.width > 0 else { return }
        updateDrawableSize()
        guard !isBlackedOut, renderer.snapshot != nil || !transition.needsSnapshot || isBlackedOut else {
            if isBlackedOut { drawBlackFrame() }
            return
        }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable() else { inFlight.signal(); return }
        let semaphore = inFlight
        if !renderer.draw(to: drawable, transition: transition, progress: progress, context: context,
                          onComplete: { semaphore.signal() }) {
            semaphore.signal()
        }
    }

    private func drawBlackFrame() {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable() else { inFlight.signal(); return }
        let semaphore = inFlight
        renderer.drawBlack(to: drawable, onComplete: { semaphore.signal() })
    }
}
