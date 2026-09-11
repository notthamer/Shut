import AppKit
import SwiftUI
import Tuner
import TransitionKit

/// Bridges Tuner to the app: one store per transition, the floating panel, the
/// preview slot, built-in presets, and the menu bar preset picker.
@MainActor
final class TunerHost {
    private let registry: TransitionRegistry
    private let previewModel: PreviewModel
    private let controller: AppController
    private let settings: AppSettings
    private let presets = PresetStore(appName: "Shut")
    private var panel: TunerPanelController?
    private var cancellable: Any?

    let sinkhole: TunerStore<SinkholeParams>
    let fade: TunerStore<FadeParams>
    let frost: TunerStore<FrostParams>
    let trigger: TunerStore<TriggerParams>

    init(registry: TransitionRegistry, previewModel: PreviewModel, controller: AppController, settings: AppSettings) {
        self.registry = registry
        self.previewModel = previewModel
        self.controller = controller
        self.settings = settings

        sinkhole = TunerStore(presets: presets, builtIns: BuiltInPresets.sinkhole)
        fade = TunerStore(presets: presets, builtIns: [])
        frost = TunerStore(presets: presets, builtIns: BuiltInPresets.frost)
        trigger = TunerStore(presets: presets, builtIns: [("Default", TriggerParams())])

        bind(sinkhole, to: SinkholeTransition.self)
        bind(fade, to: FadeTransition.self)
        bind(frost, to: FrostTransition.self)

        applyTrigger(trigger.values)
        trigger.onChange = { [weak self] values in self?.applyTrigger(values) }

        controller.onTransitionVisibilityChanged = { [weak self] playing in
            self?.panel?.setHiddenForTransition(playing)
        }
        cancellable = registry.$current.sink { [weak self] _ in self?.refreshContent() }
    }

    private func applyTrigger(_ t: TriggerParams) {
        settings.startAngle = t.startAngle
        settings.endAngle = t.endAngle
        settings.smoothing = t.smoothing
        controller.sensor.smoothing = t.smoothing
        controller.followLag = t.followLag
        controller.prediction = t.prediction
    }

    /// Pushes store values into the live transition object now and on every edit.
    private func bind<T: TransitionKit.Transition>(_ store: TunerStore<T.Params>, to type: T.Type) {
        guard let transition = registry.transition(id: T.id)?.base as? T else { return }
        transition.params = store.values
        store.onChange = { [weak self, weak transition] values in
            transition?.params = values
            self?.previewModel.paramsChanged()
        }
    }

    func toggle() {
        if panel == nil {
            let p = TunerPanelController(title: "Tuner", content: makeContent())
            p.registerHotKey()
            panel = p
        }
        panel?.toggle()
        if panel?.isVisible == true, !previewModel.hasSnapshot { previewModel.capture() }
    }

    private func refreshContent() {
        panel?.setContent(makeContent())
        panel?.panel.title = "Tuner · \(registry.current.displayName)"
    }

    private func makeContent() -> AnyView {
        let preview = PreviewArea(model: previewModel, registry: registry, aspect: BuiltInDisplayAspect.ratio)
        let triggerFolders = TunerFoldersView(store: trigger)
        switch registry.current.id {
        case SinkholeTransition.id:
            return AnyView(TunerPanelView(store: sinkhole, preview: { preview }, extra: { triggerFolders }))
        case FrostTransition.id:
            return AnyView(TunerPanelView(store: frost, preview: { preview }, extra: { triggerFolders }))
        default:
            return AnyView(TunerPanelView(store: fade, preview: { preview }, extra: { triggerFolders }))
        }
    }

    /// Menu bar "Preset" submenu for the current transition.
    func presetMenuItems() -> [NSMenuItem] {
        func items<P: TunableParameters>(_ store: TunerStore<P>) -> [NSMenuItem] {
            store.allPresets.map { preset in
                let item = NSMenuItem(title: preset.name, action: #selector(PresetMenuTarget.apply(_:)), keyEquivalent: "")
                item.target = PresetMenuTarget.shared
                item.representedObject = { store.apply(preset: preset) } as () -> Void
                item.state = store.activePresetName == preset.name ? .on : .off
                return item
            }
        }
        switch registry.current.id {
        case SinkholeTransition.id: return items(sinkhole)
        case FrostTransition.id: return items(frost)
        default: return items(fade)
        }
    }
}

/// NSMenuItem needs an Objective-C target; this one just runs the closure stored
/// on the item.
@MainActor
private final class PresetMenuTarget: NSObject {
    static let shared = PresetMenuTarget()
    @objc func apply(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
