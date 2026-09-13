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
                    .background(Capsule().fill(TunerTheme.inkBase))
                    .shadow(color: TunerTheme.inkBase.opacity(0.22), radius: 6, y: 3)
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
                Text(title).font(TunerTheme.rootTitle).foregroundStyle(theme.textRoot)
                Spacer()
                if let onCollapse {
                    PanelIconButton(systemName: "slider.horizontal.3", action: onCollapse)
                        .help("Collapse the panel")
                }
            }
            .padding(.top, 2)
            .background(WindowDragHandle())   // the title row is the grip
            HStack(spacing: TunerTheme.rowGap) {
                VersionsMenu(store: store) { showFlash($0) }
                CopyButton { copyJSON() }
            }
        }
        .padding(.horizontal, TunerTheme.paddingH)
        .padding(.top, TunerTheme.paddingV)
        .padding(.bottom, TunerTheme.paddingV)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: TunerTheme.rowGap) {
            ActionRow("Paste JSON") { pasteJSON() }
            ActionRow("Reset all") { store.resetAll() }
        }
        .padding(.top, 4)
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
            .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous)
                .fill(configuration.isPressed ? theme.inset : .clear)
                .padding(.horizontal, -6))
            .tunerAnimation(TunerTheme.press, value: configuration.isPressed)
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
                .background(Circle().fill(TunerTheme.inkBase))
                .overlay(alignment: .top) {
                    Circle().fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                        .mask(Circle().strokeBorder(lineWidth: 1.5))
                }
                .shadow(color: TunerTheme.inkBase.opacity(0.22), radius: 6, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
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
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .onHover { hover = $0 }
    }
}

/// Full-width versions dropdown. "Default" restores the base values; saved
/// versions can be selected; "New version" saves the current values. Backed by
/// a system menu so it presents reliably from a borderless panel; deleting a
/// version is in a "Delete" submenu.
struct VersionsMenu<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    let flash: (String) -> Void
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
            Button("New version") {
                let name = store.nextVersionName()
                if store.savePreset(named: name) != nil { flash("Saved \(name)") }
            }
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
                Text(currentName).font(TunerTheme.label).foregroundStyle(theme.textPrimary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textLabel)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: TunerTheme.rowHeight)
            .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(hover ? theme.raisedHover : .clear))
            .glassSurface(.raised)
            .contentShape(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous))
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
    @State private var open: Set<Int>

    public init(store: TunerStore<P>) {
        self.store = store
        _open = State(initialValue: Set(P.schema.folders.enumerated().compactMap { $0.element.collapsed ? nil : $0.offset }))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(P.schema.folders.enumerated()), id: \.offset) { index, folder in
                FolderView(title: folder.name,
                           isOpen: Binding(get: { open.contains(index) },
                                           set: { if $0 { open.insert(index) } else { open.remove(index) } }),
                           onReset: { store.reset(folder: index) }) {
                    VStack(spacing: TunerTheme.rowGap) {
                        ForEach(Array(folder.controls.enumerated()), id: \.offset) { _, control in
                            ControlRowView(store: store, control: control)
                        }
                    }
                }
            }
        }
    }
}

/// Title, chevron that turns when open, hairline rules, Reset on the right.
struct FolderView<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    let onReset: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.tunerTheme) private var theme
    @State private var resetHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header is a button so it answers on mouse-down; Reset is its own
            // button inside it, and wins the click when it is the target.
            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Eyebrow(title)
                    Spacer()
                    Button(action: onReset) {
                        Text("Reset")
                            .font(TunerTheme.caption)
                            .foregroundStyle(resetHover ? theme.textPrimary : theme.textTertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .onHover { resetHover = $0 }
                    .help("Put this group back to its defaults")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textLabel)
                        .opacity(0.6)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .frame(height: TunerTheme.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(FolderHeaderStyle())
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) { isOpen.toggle(); return .handled }
            .onKeyPress(.space) { isOpen.toggle(); return .handled }

            if isOpen {
                content()
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .glassSurface(.raised, radius: TunerTheme.cardRadius)
        .tunerMotion(TunerTheme.easeOut(0.22), value: isOpen)
    }
}
