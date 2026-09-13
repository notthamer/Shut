import AppKit
import SwiftUI
import Tuner

/// The same UI as the menu bar popover, as a proper window: it has traffic
/// lights, moves by its background, minimizes to the Dock, and remembers where
/// it was. Opened from the Dock icon, the popover's window button, or the
/// welcome screen; the menu bar item keeps offering the quick popover.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: PopoverModel
    private let dock: DockPresence
    private var window: NSWindow?
    /// Called before the window comes up, so the popover can get out of the way.
    var onShow: (() -> Void)?

    init(model: PopoverModel, dock: DockPresence) {
        self.model = model
        self.dock = dock
    }

    var isShown: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    func show() {
        let w = window ?? makeWindow()
        window = w
        onShow?()
        model.preview.followLid = false
        model.preview.capture()
        dock.retain("window")
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    private func makeWindow() -> NSWindow {
        let hosting = FirstMouseHostingView(rootView: AnyView(PopoverView(model: model, hostedInWindow: true)))
        hosting.sizingOptions = [.intrinsicContentSize]
        // The title bar is transparent and the header already leaves room for
        // the traffic lights, so the content must not also be inset below the
        // title bar: that pushed the whole panel down and clipped the footer.
        hosting.safeAreaRegions = []
        let size = NSSize(width: PopoverView.width, height: hosting.fittingSize.height)

        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Shut"
        w.appearance = TunerTheme.appearance
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        // The chrome draws the rounded glass; the window itself stays clear so
        // its corners match the popover's.
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.collectionBehavior = [.fullScreenNone]
        w.delegate = self

        let chrome = PanelChrome(frame: NSRect(origin: .zero, size: size))
        chrome.install(hosting)
        w.contentView = chrome
        // Remember where it was, never how big: the size always fits the content.
        w.setFrameAutosaveName("ShutMainWindow")
        if !w.setFrameUsingName("ShutMainWindow") { w.center() }
        let top = w.frame.maxY
        w.setContentSize(size)
        w.setFrameTopLeftPoint(NSPoint(x: w.frame.minX, y: top))
        return w
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        model.preview.stop()
        dock.release("window")
    }

    func windowDidMiniaturize(_ notification: Notification) {
        model.preview.stop()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        model.preview.capture()
    }
}

/// A minimal main menu so the standard shortcuts work in the window: ⌘W, ⌘M,
/// ⌘H, ⌘Q, and Edit commands for the Tuner's text fields.
enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About Shut", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Shut", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Shut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}
