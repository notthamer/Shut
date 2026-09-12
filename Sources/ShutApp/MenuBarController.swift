import AppKit
import Combine
import TransitionKit

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
    private let permissionItem = NSMenuItem(title: "Grant Screen Recording…", action: #selector(openPermission), keyEquivalent: "")

    /// Wired by the app once the Tuner host exists.
    var openTuner: (() -> Void)?
    var showPermissionWindow: (() -> Void)?
    var presetMenuProvider: (() -> [NSMenuItem])?
    var launchAtLoginItem: NSMenuItem?
    /// Left click on the icon. The menu stays on right click for keyboard users.
    var togglePopover: ((NSStatusBarButton) -> Void)?

    init(controller: AppController, settings: AppSettings, registry: TransitionRegistry) {
        self.controller = controller
        self.settings = settings
        self.registry = registry
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Shut")
            button.image?.isTemplate = true
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

        let quit = NSMenuItem(title: "Quit Shut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
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
        presetMenu.removeAllItems()
        let items = presetMenuProvider?() ?? []
        presetItem.isHidden = items.isEmpty
        items.forEach { presetMenu.addItem($0) }
        updateAngle()
        angleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateAngle() }
        }
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
}
