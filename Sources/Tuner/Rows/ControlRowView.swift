import SwiftUI

/// Renders one schema control with the panel's rows. Used by the full panel and
/// by hosts that show a subset (a "Feel" section).
public struct ControlRowView<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    let control: TunerControl<P>

    public init(store: TunerStore<P>, control: TunerControl<P>) {
        self.store = store
        self.control = control
    }

    public var body: some View {
        switch control {
        case .slider(let spec):
            FillSliderRow(spec.label,
                          value: Binding(get: { spec.get(store.values) }, set: { spec.set(&store.values, $0) }),
                          in: spec.range, step: spec.step, decimals: spec.decimals, unit: spec.unit, help: spec.help,
                          reset: { store.reset(control: control) })
        case .toggle(let spec):
            ToggleRow(spec.label, isOn: Binding(get: { spec.get(store.values) }, set: { spec.set(&store.values, $0) }))
        case .color(let spec):
            ColorRow(spec.label, color: Binding(get: { spec.get(store.values) }, set: { spec.set(&store.values, $0) }))
        case .spring(let spec):
            SpringEditor(spec.label,
                         response: Binding(get: { spec.getResponse(store.values) }, set: { spec.setResponse(&store.values, $0) }),
                         damping: Binding(get: { spec.getDamping(store.values) }, set: { spec.setDamping(&store.values, $0) }),
                         responseRange: spec.responseRange, dampingRange: spec.dampingRange)
        case .bezier(let spec):
            EasingEditor(spec.label, curve: Binding(get: { spec.get(store.values) }, set: { spec.set(&store.values, $0) }))
        case .segmented(let spec):
            SegmentedRow(spec.label, options: spec.options,
                         selection: Binding(get: { spec.getIndex(store.values) }, set: { spec.setIndex(&store.values, $0) }))
        case .action(let spec):
            ActionRow(spec.label) { spec.run(&store.values) }
        }
    }
}
