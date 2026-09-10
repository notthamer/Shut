import AppKit
import LidSensor
import TransitionKit
import Tuner

/// Entry point shared by the Xcode app target and the SwiftPM `sinkhole`
/// executable. Both call `SinkholeApp.run()` and nothing else.
public enum SinkholeApp {
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
        try write(BuiltInPresets.notchDrain)
        try write(BuiltInPresets.frost)
        return written
    }

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
