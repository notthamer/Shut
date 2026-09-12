import AppKit
import SwiftUI
import Tuner

/// Presents the main panel under the status item as a floating, borderless
/// window with a 14-pt radius, hairline border and soft shadow, dropping in with
/// a short spring. No system arrow, no bezel: the same chrome as Tuner.
@MainActor
final class PopoverController {
    private let model: PopoverModel
    private let dock: DockPresence
    private var panel: NSPanel?
    private var chrome: PanelChrome?
    private var monitors: [Any] = []
    private weak var anchorButton: NSStatusBarButton?

    init(model: PopoverModel, dock: DockPresence) {
        self.model = model
        self.dock = dock
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown { close() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        anchorButton = button
        model.preview.followLid = false
        if !model.preview.hasSnapshot { model.preview.capture() }

        // Sit 8 pt under the status item, centred on it, clamped to the screen.
        let size = panel.frame.size
        var origin = NSPoint(x: 0, y: 0)
        if let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            origin.x = min(max(rect.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = rect.minY - 8 - size.height
        }
        panel.setFrameOrigin(origin)

        button.highlight(true)
        dock.retain("popover")
        installMonitors()

        // Enter: fade + settle from 97 %, anchored at the top where it hangs from.
        chrome?.layer?.anchorPoint = CGPoint(x: 0.5, y: 1)
        chrome?.layer?.position = CGPoint(x: size.width / 2, y: size.height)
        panel.alphaValue = 0
        chrome?.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
        panel.orderFront(nil)
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            panel.animator().alphaValue = 1
        }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeScale(0.97, 0.97, 1)
        spring.toValue = CATransform3DIdentity
        spring.damping = 18; spring.stiffness = 260; spring.mass = 1
        spring.duration = spring.settlingDuration
        chrome?.layer?.add(spring, forKey: "enter")
        chrome?.layer?.transform = CATransform3DIdentity
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        anchorButton?.highlight(false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.dock.release("popover")
            }
        })
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: PopoverView.width, height: 0)
        let hosting = NSHostingView(rootView: AnyView(PopoverView(model: model)))
        hosting.sizingOptions = [.intrinsicContentSize]
        let fitted = hosting.fittingSize
        let frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: fitted.height))

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none

        let chrome = PanelChrome(frame: NSRect(origin: .zero, size: frame.size))
        hosting.frame = chrome.bounds
        hosting.autoresizingMask = [.width, .height]
        chrome.addSubview(hosting)
        panel.contentView = chrome
        self.chrome = chrome
        return panel
    }

    /// Click anywhere outside, or Escape, closes the panel, like a menu.
    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        } { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.close(); return nil }   // Escape
            if event.type != .keyDown, event.window !== panel {
                // A click on the status item itself is handled by the button (toggle).
                if let button = self.anchorButton, event.window === button.window { return event }
                self.close()
            }
            return event
        } { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
