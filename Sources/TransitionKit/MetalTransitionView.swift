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
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    public override var isOpaque: Bool { true }

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

    /// Draws the current progress (or black). Cheap to call; skipped if there's
    /// nothing to draw or no drawable available this instant.
    public func render() {
        guard bounds.width > 0 else { return }
        updateDrawableSize()
        if isBlackedOut {
            guard let drawable = metalLayer.nextDrawable() else { return }
            renderer.drawBlack(to: drawable)
            return
        }
        guard renderer.snapshot != nil else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }
        renderer.draw(to: drawable, transition: transition, progress: progress, context: context)
    }
}
