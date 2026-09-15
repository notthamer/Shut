import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Presets and JSON for one store, on a host's own page: pick or name a
/// version, copy the values, export or import a file, paste or drop JSON.
/// Everything the floating panel can do with presets, without the panel.
public struct TunerShareView<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    /// Collapsed shows only the preset picker (and Save as…); expanded adds
    /// copy, export, import and the paste box. The host owns the switch so it
    /// can sit in the section header next to the eyebrow.
    @Binding var expanded: Bool
    /// Wraps the modal file panels so a host popover can hold itself open.
    let aroundModal: (() -> Void) -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var nameDraft: String?
    @State private var pasted = ""
    @State private var flash: String?
    @State private var dropTargeted = false

    public init(store: TunerStore<P>, expanded: Binding<Bool>, aroundModal: @escaping (() -> Void) -> Void = { $0() }) {
        self.store = store
        _expanded = expanded
        self.aroundModal = aroundModal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            VersionsMenu(store: store, flash: { show($0) }, onSaveAs: { nameDraft = store.nextVersionName() })
            if nameDraft != nil {
                PresetNameField(text: Binding(get: { nameDraft ?? "" }, set: { nameDraft = $0 }),
                                onSave: { save(named: $0) },
                                onCancel: { nameDraft = nil })
            }
            if expanded {
                HStack(spacing: TunerTheme.rowGap) {
                    ActionRow("Copy JSON") { copy() }
                    ActionRow("Export file…") { exportFile() }
                    ActionRow("Import file…") { importFile() }
                }
                JSONBox(text: $pasted, targeted: dropTargeted, apply: { applyPasted() }, clear: { pasted = "" })
                    .transition(.blurFade)
            }
            if expanded || flash != nil {
                Text(flash ?? "Paste a preset above, or drop a .json file anywhere here.")
                    .font(TunerTheme.caption)
                    .foregroundStyle(flash == nil ? theme.inkTertiary : theme.ink)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: expanded)
        .tunerAnimation(TunerTheme.ease, value: flash)
        // Dropping a file works whether or not the section is open.
        .onDrop(of: [UTType.json, UTType.fileURL, UTType.plainText], isTargeted: $dropTargeted) { handleDrop($0) }
    }

    // MARK: Actions

    private func save(named raw: String) {
        let outcome = store.saveVersion(named: raw)
        if outcome == .saved || outcome == .replaced { nameDraft = nil }
        show(saveMessage(outcome, name: raw))
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.presetFileText, forType: .string)
        show("Copied. Paste it anywhere: a message, a file, a pull request.")
    }

    private func applyPasted() {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return show("Nothing to apply") }
        if store.apply(json: text) {
            pasted = ""
            show("Applied. Save as… to keep it.")
        } else {
            show("Not a \(P.tunerDisplayName) preset")
        }
    }

    private var suggestedFileName: String {
        let base = (store.activePresetName ?? P.tunerDisplayName).lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return base + ".json"
    }

    private func exportFile() {
        aroundModal {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = suggestedFileName
            panel.title = "Export \(P.tunerDisplayName) preset"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try Data(store.presetFileText.utf8).write(to: url, options: .atomic)
                show("Exported \(url.lastPathComponent)")
            } catch {
                show("Could not write the file")
            }
        }
    }

    private func importFile() {
        aroundModal {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json, .plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.title = "Import \(P.tunerDisplayName) preset"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            apply(fileAt: url)
        }
    }

    private func apply(fileAt url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return show("Could not read the file") }
        show(store.apply(json: text) ? "Imported \(url.lastPathComponent). Save as… to keep it." : "Not a \(P.tunerDisplayName) preset")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in apply(fileAt: url) }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text = (item as? String) ?? (item as? Data).map { String(decoding: $0, as: UTF8.self) }
                    guard let text else { return }
                    Task { @MainActor in show(store.apply(json: text) ? "Applied. Save as… to keep it." : "Not valid JSON") }
                }
                return true
            }
        }
        return false
    }

    private func show(_ text: String) {
        withAnimation(TunerTheme.quick) { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { withAnimation(TunerTheme.quick) { if flash == text { flash = nil } } }
    }
}

/// A short monospaced box to paste or type a preset into, with Apply and Clear.
/// The border turns to ink while a file is dragged over the section.
struct JSONBox: View {
    @Binding var text: String
    let targeted: Bool
    let apply: () -> Void
    let clear: () -> Void
    @Environment(\.tunerTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TunerTheme.rowGap) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("{ \"name\": …, \"values\": { … } }")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.inkTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .frame(height: 84)
            .background(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous).fill(theme.linen))
            .overlay(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous)
                .strokeBorder(targeted || focused ? theme.ink : theme.border, lineWidth: 1))
            .tunerAnimation(TunerTheme.ease, value: targeted || focused)
            .onTapGesture { focused = true }
            if !text.isEmpty {
                HStack(spacing: TunerTheme.rowGap) {
                    ActionRow("Apply", action: apply)
                    ActionRow("Clear", action: clear)
                }
                .transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: text.isEmpty)
    }
}
