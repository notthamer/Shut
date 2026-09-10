import AppKit
import LidSensor
import TransitionKit

/// Entry point shared by the Xcode app target and the SwiftPM `sinkhole`
/// executable. Both call `SinkholeApp.run()` and nothing else.
public enum SinkholeApp {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
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
    private var previewWindow: PreviewWindowController!
    private var tunerHost: TunerHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        sensor = LidSensorMonitor(smoothing: settings.smoothing)
        registry = TransitionRegistry(transitions: TransitionCatalog.make(), currentID: settings.transitionID)

        do {
            renderer = try TransitionRenderer()
            previewModel = try PreviewModel(registry: registry, settings: settings, sensor: sensor)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Sinkhole can't start"
            alert.informativeText = "Metal is unavailable or the shaders failed to compile.\n\n\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        controller = AppController(settings: settings, sensor: sensor, registry: registry, renderer: renderer)
        menuBar = MenuBarController(controller: controller, settings: settings, registry: registry)
        previewWindow = PreviewWindowController(model: previewModel, registry: registry)
        menuBar.openPreview = { [weak self] in self?.previewWindow.show() }

        tunerHost = TunerHost(registry: registry, previewModel: previewModel, controller: controller, settings: settings)
        menuBar.openTuner = { [weak self] in self?.tunerHost?.toggle() }
        menuBar.presetMenuProvider = { [weak self] in self?.tunerHost?.presetMenuItems() ?? [] }

        if sensor.start() {
            Log.lid.info("lid sensor online")
        } else {
            Log.lid.warning("no lid sensor; Tuner and preview still work")
        }

        if !ScreenRecordingPermission.isGranted {
            // First launch: show the system prompt once. The menu keeps a shortcut
            // to System Settings for later.
            ScreenRecordingPermission.request()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.teardown(reason: "quit")
        sensor?.stop()
    }
}
