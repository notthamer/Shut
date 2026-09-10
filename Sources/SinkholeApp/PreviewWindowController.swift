import AppKit
import SwiftUI

/// Standalone preview window (M1). From M3 the same PreviewArea lives inside
/// Tuner; this window stays as a lightweight fallback.
@MainActor
final class PreviewWindowController {
    private var window: NSWindow?
    private let model: PreviewModel
    private let registry: TransitionRegistry

    init(model: PreviewModel, registry: TransitionRegistry) {
        self.model = model
        self.registry = registry
    }

    func show() {
        if window == nil {
            let screen = BuiltInDisplayAspect.ratio
            let content = PreviewArea(model: model, registry: registry, aspect: screen)
                .padding(16)
                .frame(minWidth: 520, minHeight: 420)
            let hosting = NSHostingController(rootView: content)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Sinkhole Preview"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 640, height: 500))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !model.hasSnapshot { model.capture() }
    }
}

enum BuiltInDisplayAspect {
    static var ratio: CGFloat {
        guard let f = TransitionKit.BuiltInDisplay.screen?.frame, f.height > 0 else { return 16.0 / 10.0 }
        return f.width / f.height
    }
}

import TransitionKit
