import AppKit

/// Bridges Tuner to the app. Filled in at M3; for M1/M2 it opens the preview.
@MainActor
final class TunerHost {
    private let previewModel: PreviewModel
    private let registry: TransitionRegistry
    private let controller: AppController
    private let settings: AppSettings
    private var previewWindow: PreviewWindowController

    init(registry: TransitionRegistry, previewModel: PreviewModel, controller: AppController, settings: AppSettings) {
        self.registry = registry
        self.previewModel = previewModel
        self.controller = controller
        self.settings = settings
        previewWindow = PreviewWindowController(model: previewModel, registry: registry)
    }

    func toggle() { previewWindow.show() }
    func presetMenuItems() -> [NSMenuItem] { [] }
}
