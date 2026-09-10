import SwiftUI
import UniformTypeIdentifiers

/// The panel body: preview slot, presets bar, one collapsible folder per schema
/// folder, and JSON actions. Generic over the parameter struct and whatever
/// preview the host app supplies.
public struct TunerPanelView<P: TunableParameters, Preview: View>: View {
    @ObservedObject var store: TunerStore<P>
    let preview: Preview
    @State private var expanded: Set<Int>
    @State private var newPresetName = ""
    @State private var showingSave = false
    @State private var flash: String?

    public init(store: TunerStore<P>, @ViewBuilder preview: () -> Preview) {
        self.store = store
        self.preview = preview()
        _expanded = State(initialValue: Set(P.schema.folders.indices))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                preview

                presetsBar

                ForEach(Array(P.schema.folders.enumerated()), id: \.offset) { index, folder in
                    folderView(index: index, folder: folder)
                }

                footer
            }
            .padding(14)
        }
        .onDrop(of: [UTType.json, UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: Presets

    private var presetsBar: some View {
        HStack(spacing: 6) {
            Picker("Preset", selection: Binding(
                get: { store.activePresetName ?? "" },
                set: { name in
                    if let preset = store.allPresets.first(where: { $0.name == name }) { store.apply(preset: preset) }
                })) {
                Text(store.activePresetName == nil ? "Custom" : "").tag("")
                ForEach(store.allPresets) { preset in
                    Text(preset.builtIn ? "\(preset.name)" : "\(preset.name) ·").tag(preset.name)
                }
            }
            .controlSize(.small)

            Button { showingSave = true } label: { Image(systemName: "square.and.arrow.down") }
                .help("Save preset")
                .popover(isPresented: $showingSave) { savePopover }

            Menu {
                if let current = store.allPresets.first(where: { $0.name == store.activePresetName }) {
                    Button("Duplicate “\(current.name)”") { store.duplicatePreset(current) }
                    Button("Delete “\(current.name)”", role: .destructive) { store.deletePreset(current) }
                        .disabled(current.builtIn)
                    Divider()
                }
                Button("Copy JSON") { copyJSON() }
                Button("Paste JSON") { pasteJSON() }
                Divider()
                Button("Reset all to defaults") { store.resetAll() }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
        .overlay(alignment: .trailing) {
            if let flash {
                Text(flash).font(.caption).padding(4).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity)
            }
        }
    }

    private var savePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save preset").font(.headline)
            TextField("Name", text: $newPresetName).frame(width: 200)
            HStack {
                Spacer()
                Button("Cancel") { showingSave = false }
                Button("Save") {
                    let name = newPresetName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    store.savePreset(named: name)
                    newPresetName = ""
                    showingSave = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    // MARK: Folders

    @ViewBuilder
    private func folderView(index: Int, folder: TunerFolder<P>) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(index) },
            set: { if $0 { expanded.insert(index) } else { expanded.remove(index) } }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(folder.controls.enumerated()), id: \.offset) { _, control in
                    controlView(control)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(folder.name).font(.headline)
                Spacer()
                Button("Reset") { store.reset(folder: index) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func controlView(_ control: TunerControl<P>) -> some View {
        switch control {
        case .slider(let spec): SliderControlView(values: $store.values, spec: spec)
        case .toggle(let spec): ToggleControlView(values: $store.values, spec: spec)
        case .color(let spec): ColorControlView(values: $store.values, spec: spec)
        case .spring(let spec): SpringEditorView(values: $store.values, spec: spec)
        case .bezier(let spec): BezierEditorView(values: $store.values, spec: spec)
        case .segmented(let spec): SegmentedControlView(values: $store.values, spec: spec)
        case .action(let spec): ActionButtonView(values: $store.values, spec: spec)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Copy JSON") { copyJSON() }
            Button("Paste JSON") { pasteJSON() }
            Spacer()
            Text("Drop a preset .json here to import").font(.caption).foregroundStyle(.tertiary)
        }
        .controlSize(.small)
    }

    private func copyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.json, forType: .string)
        showFlash("Copied")
    }

    private func pasteJSON() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return showFlash("Clipboard is empty") }
        showFlash(store.apply(json: text) ? "Applied" : "Not a \(P.tunerDisplayName) JSON")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                    Task { @MainActor in showFlash(store.apply(json: text) ? "Imported" : "Not a \(P.tunerDisplayName) preset") }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text = (item as? String) ?? (item as? Data).map { String(decoding: $0, as: UTF8.self) }
                    guard let text else { return }
                    Task { @MainActor in showFlash(store.apply(json: text) ? "Imported" : "Not valid JSON") }
                }
                return true
            }
        }
        return false
    }

    private func showFlash(_ text: String) {
        withAnimation { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { flash = nil } }
    }
}
