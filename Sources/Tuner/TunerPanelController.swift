import AppKit
import SwiftUI

/// Hosts any SwiftUI content in a floating, non-activating panel with a
/// collapsible body. Toggle it from a menu item or the ⌃⌥T hot key.
@MainActor
public final class TunerPanelController {
    public let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private var hotKey: HotKey?
    private var hiddenForTransition = false
    private var wasVisibleBeforeTransition = false
    private var collapsed = false
    private var expandedHeight: CGFloat = 640

    public static let defaultSize = NSSize(width: 420, height: 640)

    public init(title: String, content: AnyView) {
        hosting = NSHostingView(rootView: content)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.title = title
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.contentView = hosting
        panel.minSize = NSSize(width: 360, height: 120)

        let toolbarButton = NSButton(title: "Collapse", target: self, action: #selector(toggleCollapsed))
        toolbarButton.bezelStyle = .accessoryBarAction
        toolbarButton.controlSize = .small
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = toolbarButton
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)
        collapseButton = toolbarButton

        positionNearTopRight()
    }

    private var collapseButton: NSButton?

    public func setContent(_ content: AnyView) {
        hosting.rootView = content
    }

    public var isVisible: Bool { panel.isVisible }

    public func show() {
        panel.orderFront(nil)
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    /// The host calls this when a real lid transition starts and ends, so the
    /// panel never appears inside a screen capture or on top of the drain.
    public func setHiddenForTransition(_ hidden: Bool) {
        if hidden {
            guard !hiddenForTransition else { return }
            hiddenForTransition = true
            wasVisibleBeforeTransition = panel.isVisible
            if wasVisibleBeforeTransition { hide() }
        } else {
            guard hiddenForTransition else { return }
            hiddenForTransition = false
            if wasVisibleBeforeTransition { show() }
        }
    }

    /// Registers a system-wide hot key (default ⌃⌥T) that toggles the panel.
    public func registerHotKey(keyCode: UInt32 = HotKey.keyT, modifiers: UInt32 = HotKey.controlOption) {
        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in self?.toggle() }
    }

    @objc private func toggleCollapsed() {
        collapsed.toggle()
        var frame = panel.frame
        if collapsed {
            expandedHeight = frame.height
            let newHeight = panel.frame.height - (panel.contentView?.frame.height ?? 0)  // title bar only
            frame.origin.y += frame.height - newHeight
            frame.size.height = newHeight
            collapseButton?.title = "Expand"
        } else {
            frame.origin.y -= expandedHeight - frame.height
            frame.size.height = expandedHeight
            collapseButton?.title = "Collapse"
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func positionNearTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - Self.defaultSize.width - 24,
                             y: visible.maxY - Self.defaultSize.height - 24)
        panel.setFrameOrigin(origin)
    }
}
