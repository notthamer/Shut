import AppKit
import Combine
import SwiftUI
import TransitionKit
import Tuner

/// The status item and its menu. The angle readout only updates while the menu
/// is open, so an idle app does no menu work at all.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    var statusButton: NSStatusBarButton? { statusItem.button }
    private let menu = NSMenu()
    private let controller: AppController
    private let settings: AppSettings
    private let registry: TransitionRegistry
    private var angleTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let enableItem = NSMenuItem(title: "Enable Shut", action: #selector(toggleEnabled), keyEquivalent: "")
    private let angleItem = NSMenuItem(title: "Lid angle: —", action: nil, keyEquivalent: "")
    private let transitionMenu = NSMenu()
    private let presetMenu = NSMenu()
    private let presetItem = NSMenuItem(title: "Preset", action: nil, keyEquivalent: "")
    private let awakeStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let letItSleepItem = NSMenuItem(title: "Let It Sleep Now", action: #selector(letItSleep), keyEquivalent: "")
    private let stayAwakeItem = NSMenuItem(title: "Stay Awake with the Lid Shut", action: #selector(toggleStayAwake), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Screen Recording…", action: #selector(openPermission), keyEquivalent: "")

    /// Wired by the app once the Tuner host exists.
    var openTuner: (() -> Void)?
    /// "Check for Updates…", built by the app so the menu never imports Sparkle.
    var updateItem: NSMenuItem? { didSet { if let updateItem { menu.insertItem(updateItem, at: menu.index(of: quitItem)) } } }
    private let quitItem = NSMenuItem(title: "Quit Shut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    var showPermissionWindow: (() -> Void)?
    var presetMenuProvider: (() -> [NSMenuItem])?
    var launchAtLoginItem: NSMenuItem?
    /// Left click on the icon. The menu stays on right click for keyboard users.
    var togglePopover: ((NSStatusBarButton) -> Void)?
    /// The first switch-on needs the consent sheet, which lives in the panel.
    var showAwakePage: (() -> Void)?
    /// "What's New…": the card an update shows once, on request.
    var showWhatsNew: (() -> Void)?

    /// Set once by the app. The mark carries a small badge that says what the lid will do,
    /// in the one place that is always on screen: a dot while holding, a ring while winding
    /// down, Saffron when a limit is near or has spoken. It follows the controller's changes
    /// as events, never a timer.
    var stayAwake: StayAwakeController? {
        didSet {
            guard let stayAwake else { return }
            stayAwake.objectWillChange
                .receive(on: RunLoop.main)   // willChange: read the new values on the next turn
                .map { [weak stayAwake] _ -> Badge in
                    guard let stayAwake else { return Badge(dot: .idle, toolTip: "Shut") }
                    let arbiter = stayAwake.arbiter
                    let dot = AwakeText.badge(state: arbiter.state, conditions: arbiter.conditions, limits: arbiter.limits)
                    // The headline has no running time in it, so a tooltip set now stays true.
                    let headline = AwakeText.hero(state: arbiter.state, reasons: arbiter.reasons, conditions: arbiter.conditions,
                                                  limits: arbiter.limits, now: Date()).headline
                    return Badge(dot: dot, toolTip: arbiter.limits.isOn ? "Shut · \(headline)" : "Shut")
                }
                .removeDuplicates()
                .sink { [weak self] badge in self?.show(badge) }
                .store(in: &cancellables)
        }
    }

    private struct Badge: Equatable {
        let dot: AwakeText.Dot
        let toolTip: String
    }

    private func show(_ badge: Badge) {
        guard let button = statusItem.button, let mark = AppAssets.menuBarIcon else { return }
        button.toolTip = badge.toolTip
        button.image = Self.image(mark: mark, dot: badge.dot)
    }

    /// The mark with its badge. Dot and ring stay template images, so the menu bar tints
    /// them. Saffron cannot be a template: there the mark is filled with `labelColor`
    /// inside the drawing handler, which AppKit runs again whenever the menu bar turns
    /// light or dark.
    static func image(mark: NSImage, dot: AwakeText.Dot) -> NSImage {
        guard dot != .idle else { return mark }
        let image = NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect)
            if dot == .warning {
                NSColor.labelColor.setFill()
                rect.fill(using: .sourceIn)
            }
            let spot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 5.5, height: 5.5)
            // A sliver of nothing around the badge, so it reads as a badge and not as
            // part of the mark it overlaps.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: spot.insetBy(dx: -1.25, dy: -1.25)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            switch dot {
            case .idle: break
            case .holding:
                NSColor.black.setFill()
                NSBezierPath(ovalIn: spot).fill()
            case .winding:
                NSColor.black.setStroke()
                let ring = NSBezierPath(ovalIn: spot.insetBy(dx: 0.6, dy: 0.6))
                ring.lineWidth = 1.2
                ring.stroke()
            case .warning:
                NSColor(TunerTheme.saffron).setFill()
                NSBezierPath(ovalIn: spot.insetBy(dx: -0.5, dy: -0.5)).fill()
                NSColor.labelColor.withAlphaComponent(0.55).setStroke()
                let edge = NSBezierPath(ovalIn: spot.insetBy(dx: -0.5, dy: -0.5))
                edge.lineWidth = 0.75
                edge.stroke()
            }
            return true
        }
        image.isTemplate = dot != .warning
        switch dot {
        case .idle: break
        case .holding: image.accessibilityDescription = "Shut, keeping the Mac awake"
        case .winding: image.accessibilityDescription = "Shut, about to let the Mac sleep"
        case .warning: image.accessibilityDescription = "Shut, not keeping the Mac awake: a limit was reached or is near"
        }
        return image
    }

    init(controller: AppController, settings: AppSettings, registry: TransitionRegistry) {
        self.controller = controller
        self.settings = settings
        self.registry = registry
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = AppAssets.menuBarIcon ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Shut")
            button.image?.isTemplate = true
            button.image?.accessibilityDescription = "Shut"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        buildMenu()

        settings.$isEnabled.sink { [weak self] on in self?.enableItem.state = on ? .on : .off }.store(in: &cancellables)
        registry.$current.sink { [weak self] _ in self?.rebuildTransitionMenu() }.store(in: &cancellables)
    }

    private func buildMenu() {
        enableItem.target = self
        menu.addItem(enableItem)
        angleItem.isEnabled = false
        menu.addItem(angleItem)
        menu.addItem(.separator())

        awakeStatusItem.isEnabled = false
        menu.addItem(awakeStatusItem)
        letItSleepItem.target = self
        menu.addItem(letItSleepItem)
        stayAwakeItem.target = self
        menu.addItem(stayAwakeItem)
        menu.addItem(.separator())

        let transitionItem = NSMenuItem(title: "Transition", action: nil, keyEquivalent: "")
        transitionItem.submenu = transitionMenu
        menu.addItem(transitionItem)
        rebuildTransitionMenu()

        presetItem.submenu = presetMenu
        menu.addItem(presetItem)

        let tunerItem = NSMenuItem(title: "Open Tuner", action: #selector(openTunerAction), keyEquivalent: "t")
        tunerItem.keyEquivalentModifierMask = [.control, .option]
        tunerItem.target = self
        menu.addItem(tunerItem)
        menu.addItem(.separator())

        permissionItem.target = self
        menu.addItem(permissionItem)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        launchAtLoginItem = login
        menu.addItem(login)
        menu.addItem(.separator())

        // Only in a packaged app: the notes are put there by scripts/build.sh.
        if WhatsNew.bundled() != nil || WhatsNewTour.slides(for: InstanceVersion.current.short) != nil {
            let news = NSMenuItem(title: "What’s New in Shut \(InstanceVersion.current.short)…", action: #selector(openWhatsNew), keyEquivalent: "")
            news.target = self
            menu.addItem(news)
        }
        menu.addItem(quitItem)
    }

    private func rebuildTransitionMenu() {
        transitionMenu.removeAllItems()
        for t in registry.all {
            let item = NSMenuItem(title: t.displayName, action: #selector(selectTransition(_:)), keyEquivalent: "")
            item.representedObject = t.id
            item.target = self
            item.state = t.id == registry.current.id ? .on : .off
            transitionMenu.addItem(item)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick || togglePopover == nil {
            // Attach the menu just long enough to pop it, so left clicks stay ours.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover?(sender)
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem.isHidden = ScreenRecordingPermission.isGranted
        launchAtLoginItem?.state = LaunchAtLogin.isEnabled ? .on : .off
        if let stayAwake {
            let status = stayAwake.status
            let on = stayAwake.settings.isOn && stayAwake.settings.hasConsented
            awakeStatusItem.title = status.sentence
            awakeStatusItem.isHidden = !on
            letItSleepItem.isHidden = status.action != .letItSleep
            stayAwakeItem.state = on ? .on : .off
            stayAwakeItem.isHidden = !stayAwake.hasLid
        }
        presetMenu.removeAllItems()
        let items = presetMenuProvider?() ?? []
        presetItem.isHidden = items.isEmpty
        items.forEach { presetMenu.addItem($0) }
        updateAngle()
        angleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateAngle() }
        }
        angleTimer?.tolerance = 0.05
        RunLoop.main.add(angleTimer!, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) {
        angleTimer?.invalidate()
        angleTimer = nil
    }

    private func updateAngle() {
        angleItem.isHidden = !settings.showAngleInMenu
        switch controller.sensor.capability {
        case .continuousAngle:
            if let angle = controller.sensor.angle {
                angleItem.title = String(format: "Lid angle: %.0f°  (%@)", angle, controller.state.rawValue)
            }
        case .lidStateOnly:
            angleItem.title = "Lid: open/close events only  (\(controller.state.rawValue))"
        case .unsupported:
            angleItem.title = "No lid sensor on this Mac"
        }
        if registry.isSubstituting {
            angleItem.title += "  · playing Fade until Screen Recording is granted"
        }
    }

    // MARK: Actions

    @objc private func toggleEnabled() { settings.isEnabled.toggle() }
    @objc private func openTunerAction() { openTuner?() }
    @objc private func openPermission() {
        if let showPermissionWindow { showPermissionWindow() } else { ScreenRecordingPermission.openSystemSettings() }
    }
    @objc private func selectTransition(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        registry.select(id: id)
        settings.transitionID = id
    }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }
    @objc private func openWhatsNew() { showWhatsNew?() }
    @objc private func letItSleep() { stayAwake?.perform(.letItSleep) }
    @objc private func toggleStayAwake() {
        guard let stayAwake else { return }
        if stayAwake.needsConsent { showAwakePage?() } else { stayAwake.settings.isOn.toggle() }
    }
}
