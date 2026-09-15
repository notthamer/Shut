import SwiftUI
import UniformTypeIdentifiers

/// The panel body: title, toolbar (versions + Copy), preview slot, folders, an
/// extra slot for a second store's folders, and a footer. Generic over the
/// parameter struct and whatever preview the host supplies.
public struct TunerPanelView<P: TunableParameters, Preview: View, Extra: View>: View {
    @ObservedObject var store: TunerStore<P>
    let title: String
    let preview: Preview
    let extra: Extra
    let onCollapse: (() -> Void)?

    @Environment(\.tunerTheme) private var theme
    @State private var flash: String?
    /// Non-nil while the user is typing a name for the current values.
    @State private var presetNameDraft: String?

    public init(store: TunerStore<P>, title: String = P.tunerDisplayName, onCollapse: (() -> Void)? = nil,
                @ViewBuilder preview: () -> Preview, @ViewBuilder extra: () -> Extra) {
        self.store = store
        self.title = title
        self.onCollapse = onCollapse
        self.preview = preview()
        self.extra = extra()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !(preview is EmptyView) {
                        preview
                    }
                    TunerFoldersView(store: store)
                    extra
                    footer
                }
                .padding(.horizontal, TunerTheme.paddingH)
                .padding(.vertical, TunerTheme.paddingV)
            }
        }
        .onDrop(of: [UTType.json, UTType.fileURL, UTType.plainText], isTargeted: nil) { handleDrop($0) }
        .overlay(alignment: .top) {
            if let flash {
                Text(flash)
                    .font(TunerTheme.caption)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(theme.buttonDark))
                    .padding(.top, 52)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tunerThemed()
    }

    // MARK: Header: title row + toolbar

    private var header: some View {
        VStack(spacing: TunerTheme.rowGap) {
            HStack {
                Text(title).font(TunerTheme.heading).tracking(TunerTheme.headingTracking).foregroundStyle(theme.ink)
                Spacer()
                if let onCollapse {
                    PanelIconButton(systemName: "slider.horizontal.3", action: onCollapse)
                        .help("Collapse the panel")
                }
            }
            .padding(.top, 2)
            .background(WindowDragHandle())   // the title row is the grip
            HStack(spacing: TunerTheme.rowGap) {
                VersionsMenu(store: store, flash: { showFlash($0) }, onSaveAs: { presetNameDraft = store.nextVersionName() })
                CopyButton { copyJSON() }
            }
            if presetNameDraft != nil {
                PresetNameField(text: Binding(get: { presetNameDraft ?? "" }, set: { presetNameDraft = $0 }),
                                onSave: { savePreset(named: $0) },
                                onCancel: { presetNameDraft = nil })
            }
        }
        .padding(.horizontal, TunerTheme.paddingH)
        .padding(.top, TunerTheme.paddingV)
        .padding(.bottom, TunerTheme.paddingV)
        // The one place the spectrum appears: a thin line under the header.
        .overlay(alignment: .bottom) { SpectrumLine(height: 2) }
    }

    private var footer: some View {
        HStack(spacing: TunerTheme.rowGap) {
            ActionRow("Paste JSON") { pasteJSON() }
            ActionRow("Reset all") { store.resetAll() }
        }
        .padding(.top, 4)
    }

    // MARK: Presets

    /// Saves the current values under the typed name. Built-in names are
    /// refused; an existing name of the user's own is replaced.
    private func savePreset(named raw: String) {
        let outcome = store.saveVersion(named: raw)
        if outcome == .saved || outcome == .replaced { presetNameDraft = nil }
        showFlash(saveMessage(outcome, name: raw))
    }

    // MARK: Clipboard

    private func copyJSON() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.json, forType: .string)
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
        withAnimation(TunerTheme.quick) { flash = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(TunerTheme.quick) { flash = nil } }
    }
}

public extension TunerPanelView where Extra == EmptyView {
    init(store: TunerStore<P>, title: String = P.tunerDisplayName, onCollapse: (() -> Void)? = nil,
         @ViewBuilder preview: () -> Preview) {
        self.init(store: store, title: title, onCollapse: onCollapse, preview: preview, extra: { EmptyView() })
    }
}

public extension TunerPanelView where Preview == EmptyView, Extra == EmptyView {
    init(store: TunerStore<P>, title: String = P.tunerDisplayName, onCollapse: (() -> Void)? = nil) {
        self.init(store: store, title: title, onCollapse: onCollapse, preview: { EmptyView() }, extra: { EmptyView() })
    }
}

// MARK: - Toolbar pieces

/// The one inverted element in the panel: text-root background, panel-coloured
/// glyph. Cross-fades to a checkmark for 1.5 s after copying.
/// A full-width header row can't scale without looking wrong, so its press
/// feedback is a fill that appears on mouse-down.
struct FolderHeaderStyle: ButtonStyle {
    @Environment(\.tunerTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .tunerAnimation(TunerTheme.ease, value: configuration.isPressed)
    }
}

struct CopyButton: View {
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var copied = false

    var body: some View {
        Button {
            action()
            withAnimation(TunerTheme.easeOut(0.16)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(TunerTheme.easeOut(0.16)) { copied = false } }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: TunerTheme.rowHeight, height: TunerTheme.rowHeight)
                .background(Circle().fill(theme.buttonDark))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help("Copy these values as JSON (⇧⌘C)")
        .accessibilityLabel("Copy JSON")
    }
}

struct PanelIconButton: View {
    let systemName: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hover ? theme.textRoot : theme.textLabel)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

/// Full-width versions dropdown. "Default" restores the base values; saved
/// versions can be selected; "Save as…" asks the host for a name field so the
/// user names the version rather than getting "Version 2". Backed by a system
/// menu so it presents reliably from a borderless panel; deleting a version is
/// in a "Delete" submenu.
struct VersionsMenu<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    let flash: (String) -> Void
    let onSaveAs: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    private var currentName: String { store.activePresetName ?? "Default" }

    var body: some View {
        Menu {
            Button { store.resetAll() } label: {
                Label("Default", systemImage: store.activePresetName == nil ? "checkmark" : "")
            }
            ForEach(store.allPresets) { preset in
                Button { store.apply(preset: preset) } label: {
                    Label(preset.name, systemImage: store.activePresetName == preset.name ? "checkmark" : "")
                }
            }
            Divider()
            Button("Save as…") { onSaveAs() }
            let deletable = store.allPresets.filter { !$0.builtIn }
            if !deletable.isEmpty {
                Menu("Delete") {
                    ForEach(deletable) { preset in
                        Button(preset.name, role: .destructive) { store.deletePreset(preset) }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentName).font(TunerTheme.body).foregroundStyle(theme.ink).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textLabel)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: TunerTheme.rowHeight)
            .background(Capsule().fill(hover ? theme.linen : theme.card))
            .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
            .tunerAnimation(TunerTheme.ease, value: hover)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .onHover { hover = $0 }
        .accessibilityLabel("Versions")
    }
}

// MARK: - Folders

/// The schema's folders, each a collapsible group with a per-folder Reset.
/// Usable on its own for a secondary store inside another panel or a host UI.
public struct TunerFoldersView<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    /// Leave out the featured dials: for a host that already shows them above.
    let excludingFeatured: Bool
    @State private var open: Set<Int>

    public init(store: TunerStore<P>, excludingFeatured: Bool = false) {
        self.store = store
        self.excludingFeatured = excludingFeatured
        _open = State(initialValue: Set(P.schema.folders.enumerated().compactMap { $0.element.collapsed ? nil : $0.offset }))
    }

    private func controls(of folder: TunerFolder<P>) -> [TunerControl<P>] {
        excludingFeatured ? folder.controls.filter { !$0.isFeatured } : folder.controls
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(P.schema.folders.enumerated()), id: \.offset) { index, folder in
                let rows = controls(of: folder)
                if !rows.isEmpty {
                    FolderView(title: folder.name,
                               number: String(format: "%02d", index + 1),
                               isOpen: Binding(get: { open.contains(index) },
                                               set: { if $0 { open.insert(index) } else { open.remove(index) } }),
                               onReset: { store.reset(folder: index) }) {
                        VStack(spacing: TunerTheme.rowGap) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, control in
                                ControlRowView(store: store, control: control)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One line of feedback for a save attempt, shared by the panel and the host.
func saveMessage<P>(_ outcome: TunerStore<P>.SaveOutcome, name raw: String) -> String {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch outcome {
    case .saved: return "Saved \(name)"
    case .replaced: return "Replaced \(name)"
    case .emptyName: return "Give it a name"
    case .builtInName: return "\(name) is built in; pick another name"
    case .failed: return "Could not save"
    }
}

/// A chapter: a hairline, a numbered eyebrow with Reset as a text link, and
/// the rows. Open and close is a crossfade.
struct FolderView<Content: View>: View {
    let title: String
    var number: String? = nil
    @Binding var isOpen: Bool
    let onReset: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.tunerTheme) private var theme
    @State private var resetHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Eyebrow(title, number: number)
                    Spacer()
                    Button(action: onReset) {
                        Text("Reset")
                            .font(TunerTheme.bodySmall)
                            .foregroundStyle(resetHover ? theme.ink : theme.inkTertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .onHover { resetHover = $0 }
                    .tunerAnimation(TunerTheme.ease, value: resetHover)
                    .help("Put this group back to its defaults")
                }
                .frame(height: TunerTheme.rowHeight + 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(FolderHeaderStyle())
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) { isOpen.toggle(); return .handled }
            .onKeyPress(.space) { isOpen.toggle(); return .handled }

            if isOpen {
                content()
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .tunerAnimation(TunerTheme.ease, value: isOpen)
    }
}

/// One-line name entry shown under the toolbar while saving a version. Return
/// saves, Escape cancels. The suggested name is pre-selected so typing replaces it.
struct PresetNameField: View {
    @Binding var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.tunerTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: TunerTheme.rowGap) {
            TextField("Name this version", text: $text)
                .textFieldStyle(.plain)
                .font(TunerTheme.body)
                .foregroundStyle(theme.ink)
                .focused($focused)
                .onSubmit { onSave(text) }
                .onExitCommand { onCancel() }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: TunerTheme.rowHeight)
                .background(Capsule().fill(theme.linen))
                .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
            Button("Save") { onSave(text) }
                .buttonStyle(PressStyle())
                .font(TunerTheme.body)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: TunerTheme.rowHeight)
                .background(Capsule().fill(theme.buttonDark))
            Button("Cancel") { onCancel() }
                .buttonStyle(PressStyle())
                .font(TunerTheme.body)
                .foregroundStyle(theme.textLabel)
                .padding(.horizontal, 4)
                .frame(height: TunerTheme.rowHeight)
        }
        .onAppear {
            focused = true
            // Select the suggestion so typing replaces it.
            DispatchQueue.main.async { NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSText }?.selectAll(nil) }
        }
    }
}
