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

    /// Everything the host needs per style, type-erased so eleven styles don't
    /// become an eleven-way switch.
    private struct Registration {
        let content: (PreviewArea, TunerFoldersView<TriggerParams>) -> AnyView
        let presetItems: () -> [NSMenuItem]
        let featured: () -> AnyView
        let reset: () -> Void
    }
    /// Set by the app so thumbnails refresh as dials move.
    var onParamsChanged: ((String) -> Void)?
    /// Set by the app to keep a Dock icon while the panel is visible.
    var onPanelVisibility: ((Bool) -> Void)?
    private var invalidateWork: DispatchWorkItem?
    private var registrations: [String: Registration] = [:]
    let trigger: TunerStore<TriggerParams>

    init(registry: TransitionRegistry, previewModel: PreviewModel, controller: AppController, settings: AppSettings) {
        self.registry = registry
        self.previewModel = previewModel
        self.controller = controller
        self.settings = settings

        trigger = TunerStore(presets: presets, builtIns: [("Default", TriggerParams())])

        register(SinkholeTransition.self, builtIns: BuiltInPresets.sinkhole)
        register(FrostTransition.self, builtIns: BuiltInPresets.frost)
        register(FoldTransition.self, builtIns: BuiltInPresets.fold)
        register(CurlTransition.self, builtIns: [])
        register(CreaseTransition.self, builtIns: [])
        register(RecedeTransition.self, builtIns: [])
        register(SlideTransition.self, builtIns: [])
        register(ApertureTransition.self, builtIns: [])
        register(ShutterTransition.self, builtIns: [])
        register(BlindsTransition.self, builtIns: [])
        register(FadeTransition.self, builtIns: [])

        applyTrigger(trigger.values)
        trigger.onChange = { [weak self] values in self?.applyTrigger(values) }

        controller.onTransitionVisibilityChanged = { [weak self] playing in
            self?.panel?.setHiddenForTransition(playing)
        }
        cancellable = registry.$current.sink { [weak self] _ in self?.refreshContent() }
    }

    private func applyTrigger(_ t: TriggerParams) {
        settings.bandDegrees = t.startAngle
        settings.smoothing = t.smoothing
        settings.animateOpening = t.animateOpening
        controller.sensor.bandDegrees = t.startAngle
        controller.sensor.smoothing = t.smoothing
        controller.followLag = t.glide
    }

    /// Creates the store for one style, pushes its values into the live
    /// transition now and on every edit, and records how to show it.
    private func register<T: TransitionKit.Transition>(_ type: T.Type, builtIns: [(String, T.Params)]) {
        let store = TunerStore<T.Params>(presets: presets, builtIns: builtIns)
        if let transition = registry.transition(id: T.id)?.base as? T {
            transition.params = store.values
            store.onChange = { [weak self, weak transition] values in
                transition?.params = values
                self?.previewModel.paramsChanged()
                self?.scheduleThumbnailRefresh(id: T.id)
            }
        }
        registrations[T.id] = Registration(
            content: { [weak self] preview, triggerFolders in
                AnyView(TunerPanelView(store: store, title: T.displayName,
                                       onCollapse: { self?.panel?.toggleCollapsed() },
                                       preview: { preview }, extra: { triggerFolders }))
            },
            presetItems: {
                store.allPresets.map { preset in
                    let item = NSMenuItem(title: preset.name, action: #selector(PresetMenuTarget.apply(_:)), keyEquivalent: "")
                    item.target = PresetMenuTarget.shared
                    item.representedObject = { store.apply(preset: preset) } as () -> Void
                    item.state = store.activePresetName == preset.name ? .on : .off
                    return item
                }
            },
            featured: {
                AnyView(VStack(spacing: TunerTheme.rowGap) {
                    ForEach(Array(store.featuredControls.enumerated()), id: \.offset) { _, control in
                        ControlRowView(store: store, control: control)
                    }
                })
            },
            reset: { store.resetAll() }
        )
    }

    /// Thumbnails re-render at most every 100 ms while a dial is dragged.
    private func scheduleThumbnailRefresh(id: String) {
        invalidateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onParamsChanged?(id) }
        invalidateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func featuredDials(for id: String) -> AnyView {
        registrations[id]?.featured() ?? AnyView(EmptyView())
    }

    func resetStyle(id: String) {
        registrations[id]?.reset()
    }

    /// Wide enough for a 16:10 preview above the dials.
    static let panelWidth: CGFloat = 360

    func toggle() {
        if panel == nil {
            let p = TunerPanelController(title: "Tune", content: makeContent(), width: Self.panelWidth)
            p.registerHotKey()
            p.onVisibilityChanged = { [weak self] visible in self?.onPanelVisibility?(visible) }
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
        guard let registration = registrations[registry.current.id] else { return AnyView(preview) }
        return registration.content(preview, triggerFolders)
    }

    /// Menu bar "Preset" submenu for the current transition.
    func presetMenuItems() -> [NSMenuItem] {
        registrations[registry.current.id]?.presetItems() ?? []
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
