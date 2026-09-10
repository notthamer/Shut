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
    private let presets = PresetStore(appName: "Sinkhole")
    private var panel: TunerPanelController?
    private var cancellable: Any?

    let notchDrain: TunerStore<NotchDrainParams>
    let fade: TunerStore<FadeParams>
    let frost: TunerStore<FrostParams>

    init(registry: TransitionRegistry, previewModel: PreviewModel, controller: AppController, settings: AppSettings) {
        self.registry = registry
        self.previewModel = previewModel
        self.controller = controller
        self.settings = settings

        notchDrain = TunerStore(presets: presets, builtIns: BuiltInPresets.notchDrain)
        fade = TunerStore(presets: presets, builtIns: [])
        frost = TunerStore(presets: presets, builtIns: BuiltInPresets.frost)

        bind(notchDrain, to: NotchDrainTransition.self)
        bind(fade, to: FadeTransition.self)
        bind(frost, to: FrostTransition.self)

        controller.onTransitionVisibilityChanged = { [weak self] playing in
            self?.panel?.setHiddenForTransition(playing)
        }
        cancellable = registry.$current.sink { [weak self] _ in self?.refreshContent() }
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
        switch registry.current.id {
        case NotchDrainTransition.id:
            return AnyView(TunerPanelView(store: notchDrain) { preview })
        case FrostTransition.id:
            return AnyView(TunerPanelView(store: frost) { preview })
        default:
            return AnyView(TunerPanelView(store: fade) { preview })
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
        case NotchDrainTransition.id: return items(notchDrain)
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
