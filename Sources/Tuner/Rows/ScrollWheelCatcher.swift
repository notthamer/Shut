import AppKit
import SwiftUI

/// SwiftUI has no scroll-wheel event. Rows that want "scroll to nudge" put this
/// behind themselves; AppKit delivers the wheel to the deepest view under the
/// pointer, and this view is under the row's SwiftUI content, so the row's own
/// controls still get clicks first while the wheel lands here.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?
        override var acceptsFirstResponder: Bool { false }

        override func scrollWheel(with event: NSEvent) {
            guard abs(event.scrollingDeltaY) > 0.5 else { super.scrollWheel(with: event); return }
            onScroll?(event.scrollingDeltaY)
        }
    }
}
