import AppKit
import Combine
import SwiftUI
import Tuner

/// Presents the main panel under the status item as a floating, borderless
/// window with a 14-pt radius, hairline border and soft shadow, dropping in with
/// a short spring. No system arrow, no bezel: the same chrome as Tuner.
extension NSWindow {
    /// The Lid effects page and the Stay awake page are not the same height. When the page
    /// changes, the window takes the new height with its top edge where it was: it hangs from
    /// the menu bar, or from where the user put it, and grows or shrinks downwards. No
    /// animation: the content crossfades, and a window sliding under it would be motion the
    /// interface does not otherwise have.
    func fitHeight(to hosting: NSView) {
        hosting.layoutSubtreeIfNeeded()
        let height = hosting.fittingSize.height
        guard height > 0, abs(height - (contentView?.frame.height ?? 0)) > 0.5 else { return }
        let top = frame.maxY
        setContentSize(NSSize(width: contentView?.frame.width ?? frame.width, height: height))
        setFrameTopLeftPoint(NSPoint(x: frame.minX, y: top))
    }
}

@MainActor
final class PopoverController {
    private let model: PopoverModel
    private let dock: DockPresence
    private var panel: NSPanel?
    private var chrome: PanelChrome?
    private var hosting: NSView?
    private var monitors: [Any] = []
    private weak var anchorButton: NSStatusBarButton?
    private var pageWatch: AnyCancellable?

    init(model: PopoverModel, dock: DockPresence) {
        self.model = model
        self.dock = dock
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown { close() } else { show(relativeTo: button) }
    }

    /// 8 pt under the status item, centred on it, clamped to the screen. Without a status
    /// item (it can be hidden by a full menu bar): the top right corner, where it would be.
    static func origin(for size: NSSize, under button: NSStatusBarButton?) -> NSPoint {
        if let button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            return NSPoint(x: min(max(rect.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8),
                           y: rect.minY - 8 - size.height)
        }
        let screen = NSScreen.main?.visibleFrame ?? .zero
        return NSPoint(x: screen.maxX - size.width - 8, y: screen.maxY - 8 - size.height)
    }

    func show(relativeTo button: NSStatusBarButton) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        anchorButton = button
        model.preview.followLid = false
        // Always fresh: the desktop behind the panel is what the effect will play on.
        model.preview.capture()

        panel.setFrameOrigin(Self.origin(for: panel.frame.size, under: button))

        button.highlight(true)
        dock.retain("popover")
        installMonitors()

        // The panel fades in over 0.2 s. Nothing moves or scales.
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
    static func duration(_ seconds: Double) -> Double { seconds * TunerTheme.motionScale }


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
        // The panel follows the page's height. `$page` fires before the value is in place, so
        // the fit happens on the next turn, once SwiftUI has laid the new page out.
        pageWatch = model.$contentHeight.removeDuplicates().sink { [weak panel, weak hosting] _ in
            DispatchQueue.main.async { if let panel, let hosting { panel.fitHeight(to: hosting) } }
        }
        return panel
    }

    /// Runs a modal file panel without the click-outside monitors closing the
    /// popover; they come back afterwards if the panel is still up.
    func holdingOpen(_ work: () -> Void) {
        guard isShown else { work(); return }
        removeMonitors()
        work()
        if isShown { installMonitors() }
    }

    /// Click anywhere outside, or Escape, closes the panel, like a menu.
    private func installMonitors() {
        removeMonitors()
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
        if let global { monitors.append(global) }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.close(animated: false); return nil }   // Escape
            if event.type != .keyDown, event.window !== panel {
                // A click on the status item itself is handled by the button (toggle).
                if let button = self.anchorButton, event.window === button.window { return event }
                self.close()
            }
            return event
        })
        if let local { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
