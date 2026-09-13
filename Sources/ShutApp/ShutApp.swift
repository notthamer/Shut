import AppKit
import Combine
import LidSensor
import SwiftUI
import TransitionKit
import Tuner

/// Entry point shared by the Xcode app target and the SwiftPM `shut`
/// executable. Both call `ShutApp.run()` and nothing else.
public enum ShutApp {
    /// Writes every built-in preset to `dir/<transition>/<name>.json`, the same
    /// format Tuner saves and the repo's presets/ folder uses.
    public static func exportBuiltInPresets(to dir: URL) throws -> [URL] {
        var written: [URL] = []
        func write<P: TunableParameters>(_ list: [(String, P)]) throws {
            let sub = dir.appendingPathComponent(P.tunerID)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for (name, values) in list {
                guard let preset = Preset(name: name, tunerID: P.tunerID, values: values, builtIn: true) else { continue }
                let file = sub.appendingPathComponent(name.lowercased().replacingOccurrences(of: " ", with: "-"))
                    .appendingPathExtension("json")
                try Data(preset.fileText.utf8).write(to: file, options: .atomic)
                written.append(file)
            }
        }
        try write(BuiltInPresets.sinkhole)
        try write(BuiltInPresets.frost)
        try write(BuiltInPresets.fold)
        return written
    }

    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.appearance = TunerTheme.appearance   // light glass, whatever the system appearance
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var sensor: LidSensorMonitor!
    private var registry: TransitionRegistry!
    private var renderer: TransitionRenderer!
    private var controller: AppController!
    private var menuBar: MenuBarController!
    private var previewModel: PreviewModel!
    private var tunerHost: TunerHost?
    private var thumbnails: TransitionThumbnailRenderer?
    private var popoverModel: PopoverModel!
    private var popover: PopoverController!
    private var mainWindow: MainWindowController!
    private let welcome = WelcomeWindow()
    private let dock = DockPresence()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies (one from Xcode, one relaunched) would each draw an overlay
        // and fight over the sensor. The newer one wins; the older one quits.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            for other in others {
                Log.app.warning("terminating older instance pid \(other.processIdentifier)")
                other.terminate()
            }
        }

        settings = AppSettings()
        sensor = LidSensorMonitor(smoothing: settings.smoothing, bandDegrees: settings.bandDegrees)
        registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: settings.transitionID)

        do {
            renderer = try TransitionRenderer()
            previewModel = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Shut can't start"
            alert.informativeText = "Metal is unavailable or the shaders failed to compile.\n\n\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        controller = AppController(settings: settings, sensor: sensor, registry: registry, renderer: renderer)
        menuBar = MenuBarController(controller: controller, settings: settings, registry: registry)

        tunerHost = TunerHost(registry: registry, previewModel: previewModel, controller: controller, settings: settings)
        menuBar.openTuner = { [weak self] in self?.tunerHost?.toggle() }
        menuBar.presetMenuProvider = { [weak self] in self?.tunerHost?.presetMenuItems() ?? [] }

        sensor.onRateChange = { rate in Log.lid.info("poll rate \(Int(rate)) Hz") }
        let capability = sensor.start()
        Log.lid.info("hinge capability: \(capability.rawValue, privacy: .public)")

        thumbnails = try? TransitionThumbnailRenderer()
        popoverModel = PopoverModel(settings: settings, registry: registry, preview: previewModel, sensor: sensor, thumbnails: thumbnails)
        popoverModel.play = { [weak self] in self?.popover.close(); self?.controller.playDemo() }
        popoverModel.openTuner = { [weak self] in self?.popover.close(); self?.tunerHost?.toggle() }
        popoverModel.allowScreenRecording = {
            ScreenRecordingPermission.request()
            ScreenRecordingPermission.openSystemSettings()
        }
        popoverModel.relaunch = { Relaunch.now() }
        popoverModel.setLaunchAtLogin = { on in if LaunchAtLogin.isEnabled != on { LaunchAtLogin.toggle() } }
        popoverModel.launchAtLogin = { LaunchAtLogin.isEnabled }
        popoverModel.featuredDials = { [weak self] id in self?.tunerHost?.featuredDials(for: id) ?? AnyView(EmptyView()) }
        popoverModel.resetStyle = { [weak self] id in self?.tunerHost?.resetStyle(id: id) }
        tunerHost?.onParamsChanged = { [weak self] id in self?.popoverModel.invalidateThumbnail(id: id) }
        popover = PopoverController(model: popoverModel, dock: dock)
        mainWindow = MainWindowController(model: popoverModel, dock: dock)
        mainWindow.onShow = { [weak self] in self?.popover.close() }
        popoverModel.openWindow = { [weak self] in self?.mainWindow.show() }
        MainMenu.install()
        dock.alwaysVisible = settings.showInDock
        settings.$showInDock.sink { [weak self] on in self?.dock.alwaysVisible = on }.store(in: &cancellables)
        tunerHost?.onPanelVisibility = { [weak self] visible in visible ? self?.dock.retain("tuner") : self?.dock.release("tuner") }
        welcome.onVisibilityChanged = { [weak self] visible in visible ? self?.dock.retain("welcome") : self?.dock.release("welcome") }
        menuBar.togglePopover = { [weak self] button in self?.popover.toggle(relativeTo: button) }
        menuBar.showPermissionWindow = { [weak self] in
            if let button = self?.menuBar.statusButton { self?.popover.show(relativeTo: button) }
        }

        // Zero prompts at launch. Permissions are explained in the popover, only
        // when a chosen style needs them.
        if !settings.hasCompletedFirstRun {
            welcome.show(capability: capability) { [weak self] in
                self?.settings.isEnabled = true
                self?.settings.hasCompletedFirstRun = true
                self?.mainWindow.show()
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Shut", action: #selector(dockOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let tune = NSMenuItem(title: "Tune everything…", action: #selector(dockTune), keyEquivalent: "")
        tune.target = self
        menu.addItem(tune)
        let toggle = NSMenuItem(title: settings.isEnabled ? "Pause" : "Resume", action: #selector(dockToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        return menu
    }

    @objc private func dockOpen() { mainWindow?.show() }
    @objc private func dockTune() { tunerHost?.toggle() }
    @objc private func dockToggle() { settings.isEnabled.toggle() }

    /// Clicking the Dock icon opens (or brings back) the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.teardown(reason: "quit")
        sensor?.stop()
    }
}
