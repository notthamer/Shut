import Combine
import Foundation

/// Live values for one parameter struct, persisted to UserDefaults.
///
/// The panel binds its controls to `values`; every change is saved and forwarded
/// to `onChange`, which the host app uses to push params into the renderer.
@MainActor
public final class TunerStore<P: TunableParameters>: ObservableObject {
    @Published public var values: P {
        didSet {
            guard values != oldValue else { return }
            persist()
            onChange?(values)
        }
    }

    /// Name of the preset the current values came from, or nil once edited.
    @Published public private(set) var activePresetName: String?

    public var onChange: ((P) -> Void)?
    public let presets: PresetStore
    public let builtInPresets: [Preset]

    private let defaults: UserDefaults
    private var defaultsKey: String { "tuner.\(P.tunerID)" }
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - presets: where user presets live (shared between stores of one app).
    ///   - builtIns: presets that ship with the app, shown first and never deletable.
    public init(presets: PresetStore, builtIns: [(String, P)] = [], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.presets = presets
        self.builtInPresets = builtIns.compactMap { name, values in
            Preset(name: name, tunerID: P.tunerID, values: values, builtIn: true)
        }
        if let data = defaults.data(forKey: "tuner.\(P.tunerID)"),
           let saved = try? JSONDecoder().decode(P.self, from: data) {
            values = saved
        } else {
            values = P.defaults
        }
        activePresetName = defaults.string(forKey: "tuner.\(P.tunerID).preset")
        // Clear the preset name when the user edits values by hand.
        cancellable = $values.dropFirst().sink { [weak self] _ in
            guard let self, !self.applyingPreset else { return }
            self.setActivePreset(nil)
        }
    }

    private var applyingPreset = false

    private func persist() {
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private func setActivePreset(_ name: String?) {
        activePresetName = name
        defaults.set(name, forKey: "\(defaultsKey).preset")
    }

    // MARK: Reset

    public func resetAll() {
        values = P.defaults
    }

    /// Resets only the controls in one folder of the schema.
    public func reset(folder index: Int) {
        guard P.schema.folders.indices.contains(index) else { return }
        var next = values
        for control in P.schema.folders[index].controls {
            control.copyValue(from: P.defaults, into: &next)
        }
        values = next
    }

    // MARK: JSON

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Accepts either a bare parameter object or a full preset file.
    @discardableResult
    public func apply(json: String) -> Bool {
        let data = Data(json.utf8)
        if let preset = try? JSONDecoder().decode(Preset.self, from: data), preset.tunerID == P.tunerID {
            return apply(preset: preset)
        }
        guard let parsed = try? JSONDecoder().decode(P.self, from: data) else { return false }
        values = parsed
        return true
    }

    // MARK: Presets

    /// Built-ins first, then the user's, sorted by name.
    public var allPresets: [Preset] {
        builtInPresets + presets.list(tunerID: P.tunerID)
    }

    @discardableResult
    public func apply(preset: Preset) -> Bool {
        guard let parsed = preset.decode(P.self) else { return false }
        applyingPreset = true
        values = parsed
        applyingPreset = false
        setActivePreset(preset.name)
        return true
    }

    @discardableResult
    public func savePreset(named name: String) -> Preset? {
        guard let preset = Preset(name: name, tunerID: P.tunerID, values: values, builtIn: false) else { return nil }
        do {
            try presets.save(preset)
            setActivePreset(name)
            objectWillChange.send()
            return preset
        } catch {
            return nil
        }
    }

    public func duplicatePreset(_ preset: Preset) {
        var name = preset.name + " copy"
        var n = 2
        while allPresets.contains(where: { $0.name == name }) { name = "\(preset.name) copy \(n)"; n += 1 }
        let copy = Preset(name: name, tunerID: preset.tunerID, valuesJSON: preset.valuesJSON, builtIn: false)
        try? presets.save(copy)
        objectWillChange.send()
    }

    public func deletePreset(_ preset: Preset) {
        guard !preset.builtIn else { return }
        try? presets.delete(preset)
        if activePresetName == preset.name { setActivePreset(nil) }
        objectWillChange.send()
    }
}
