import AppKit
import SwiftUI

/// Presents the popover from the status item. AppKit `NSPopover` rather than a
/// SwiftUI scene, so size and position are ours to control.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: PopoverModel
    private let dock: DockPresence

    init(model: PopoverModel, dock: DockPresence) {
        self.model = model
        self.dock = dock
        super.init()
        let hosting = NSHostingController(rootView: PopoverView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func popoverDidShow(_ notification: Notification) { dock.retain("popover") }
    func popoverDidClose(_ notification: Notification) { dock.release("popover") }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { close() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton) {
        model.preview.followLid = false
        if !model.preview.hasSnapshot { model.preview.capture() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Accessory app + transient popover otherwise swallows the first click.
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { popover.performClose(nil) }
}
