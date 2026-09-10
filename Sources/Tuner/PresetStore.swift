import Foundation

/// A named snapshot of one parameter struct. The values are kept as raw JSON so
/// `Preset` itself needs no generic parameter and can be listed for any tuner.
public struct Preset: Codable, Equatable, Identifiable {
    public var name: String
    public var tunerID: String
    public var valuesJSON: Data
    public var builtIn: Bool

    public var id: String { "\(tunerID)/\(name)/\(builtIn)" }

    public init(name: String, tunerID: String, valuesJSON: Data, builtIn: Bool) {
        self.name = name
        self.tunerID = tunerID
        self.valuesJSON = valuesJSON
        self.builtIn = builtIn
    }

    public init?<P: Encodable>(name: String, tunerID: String, values: P, builtIn: Bool) {
        guard let data = try? JSONEncoder().encode(values) else { return nil }
        self.init(name: name, tunerID: tunerID, valuesJSON: data, builtIn: builtIn)
    }

    public func decode<P: Decodable>(_ type: P.Type) -> P? {
        try? JSONDecoder().decode(P.self, from: valuesJSON)
    }

    // On disk a preset is { "name", "transition", "values": {...} } so files are
    // readable and hand-editable, and the community can submit them by PR.
    private enum CodingKeys: String, CodingKey { case name, transition, values }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        tunerID = try c.decode(String.self, forKey: .transition)
        let raw = try c.decode(JSONValue.self, forKey: .values)
        valuesJSON = try JSONEncoder().encode(raw)
        builtIn = false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(tunerID, forKey: .transition)
        try c.encode(try JSONDecoder().decode(JSONValue.self, from: valuesJSON), forKey: .values)
    }

    /// Pretty JSON for the clipboard or a file.
    public var fileText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// Minimal JSON tree so presets can carry arbitrary parameter objects.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

/// User presets on disk: `<Application Support>/<appName>/Presets/<tunerID>/<name>.json`.
public final class PresetStore {
    public let rootURL: URL

    public init(appName: String) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent(appName).appendingPathComponent("Presets")
    }

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    private func directory(for tunerID: String) -> URL {
        rootURL.appendingPathComponent(tunerID)
    }

    private func fileURL(for preset: Preset) -> URL {
        let safe = preset.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return directory(for: preset.tunerID).appendingPathComponent(safe).appendingPathExtension("json")
    }

    public func list(tunerID: String) -> [Preset] {
        let dir = directory(for: tunerID)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Preset? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Preset.self, from: data)
            }
            .filter { $0.tunerID == tunerID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ preset: Preset) throws {
        let dir = directory(for: preset.tunerID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(preset.fileText.utf8).write(to: fileURL(for: preset), options: .atomic)
    }

    public func delete(_ preset: Preset) throws {
        try FileManager.default.removeItem(at: fileURL(for: preset))
    }

    /// Reads a preset file dropped onto the panel.
    public static func load(from url: URL) -> Preset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Preset.self, from: data)
    }
}
