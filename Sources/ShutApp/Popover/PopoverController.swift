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
    private var hosting: NSView?
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
        // Always fresh: the desktop behind the panel is what the effect will play on.
        model.preview.capture()

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

        // Dia motion: the panel fades in over 0.2 s. Nothing moves or scales.
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.duration(0.2)
            ctx.timingFunction = Self.ease
            panel.animator().alphaValue = 1
        }
    }

    /// Click-outside and the status item close with a short exit that mirrors
    /// the entrance. Escape closes instantly: keyboard actions never animate.
    func close(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        model.preview.stop()
        model.preview.followLid = false
        anchorButton?.highlight(false)
        guard animated else {
            panel.orderOut(nil)
            dock.release("popover")
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.duration(0.15)
            ctx.timingFunction = Self.ease
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.dock.release("popover")
            }
        })
    }

    private static let ease = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static func duration(_ seconds: Double) -> Double { seconds * TunerTheme.motionScale }


    private func makePanel() -> NSPanel {
        let size = NSSize(width: PopoverView.width, height: 0)
        let hosting = FirstMouseHostingView(rootView: AnyView(PopoverView(model: model)))
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting
        let fitted = hosting.fittingSize
        let frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: fitted.height))

        let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
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
        chrome.install(hosting)
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
            if event.type == .keyDown, event.keyCode == 53 { self.close(animated: false); return nil }   // Escape
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
