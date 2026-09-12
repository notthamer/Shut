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
        .background(theme.panel)
        .onDrop(of: [UTType.json, UTType.fileURL, UTType.plainText], isTargeted: nil) { handleDrop($0) }
        .overlay(alignment: .top) {
            if let flash {
                Text(flash)
                    .font(TunerTheme.caption)
                    .foregroundStyle(theme.panel)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(theme.textRoot))
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
            HStack(spacing: TunerTheme.rowGap) {
                VersionsMenu(store: store) { showFlash($0) }
                CopyButton { copyJSON() }
            }
        }
        .padding(.horizontal, TunerTheme.paddingH)
        .padding(.top, TunerTheme.paddingV)
        .padding(.bottom, TunerTheme.paddingV)
        .background(theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.surfaceSubtle).frame(height: 1) }
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
struct CopyButton: View {
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var copied = false
    @State private var pressed = false

    var body: some View {
        Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.panel)
            .frame(width: TunerTheme.rowHeight, height: TunerTheme.rowHeight)
            .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(theme.textRoot))
            .scaleEffect(pressed ? 0.9 : 1)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    pressed = false
                    action()
                    withAnimation(.easeOut(duration: 0.08)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(.easeOut(duration: 0.08)) { copied = false } }
                })
            .tunerAnimation(TunerTheme.quick, value: pressed)
            .help("Copy these values as JSON")
            .accessibilityLabel("Copy JSON")
    }
}

struct PanelIconButton: View {
    let systemName: String
    let action: () -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var hover = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hover ? theme.textRoot : theme.textLabel)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
    }
}

/// Full-width versions dropdown. "Default" restores the base values; saved
/// versions can be selected or deleted; "New version" saves the current values.
struct VersionsMenu<P: TunableParameters>: View {
    @ObservedObject var store: TunerStore<P>
    let flash: (String) -> Void
    @Environment(\.tunerTheme) private var theme
    @State private var open = false

    private var currentName: String { store.activePresetName ?? "Default" }

    var body: some View {
        HStack(spacing: 8) {
            Text(currentName).font(TunerTheme.label).foregroundStyle(theme.textPrimary).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textLabel)
                .rotationEffect(.degrees(open ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: TunerTheme.rowHeight)
        .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(theme.surface))
        .contentShape(Rectangle())
        .onTapGesture { open.toggle() }
        .tunerAnimation(TunerTheme.quick, value: open)
        .popover(isPresented: $open, arrowEdge: .bottom) { menu }
        .accessibilityLabel("Versions")
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(name: "Default", active: store.activePresetName == nil) {
                store.resetAll(); open = false
            }
            ForEach(store.allPresets) { preset in
                HStack(spacing: 0) {
                    row(name: preset.name, active: store.activePresetName == preset.name) {
                        store.apply(preset: preset); open = false
                    }
                    if !preset.builtIn {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textLabel)
                            .frame(width: 26, height: 32)
                            .contentShape(Rectangle())
                            .onTapGesture { store.deletePreset(preset) }
                            .help("Delete this version")
                    }
                }
            }
            Rectangle().fill(theme.border).frame(height: 1).padding(.vertical, 3)
            row(name: "New version", active: false, icon: "plus") {
                let name = store.nextVersionName()
                if store.savePreset(named: name) != nil { flash("Saved \(name)") }
                open = false
            }
        }
        .padding(4)
        .frame(width: 236)
        .background(theme.dropdown)
        .tunerThemed()
    }

    private func row(name: String, active: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon ?? "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 14)
                .opacity(icon != nil || active ? 1 : 0)
            Text(name).font(TunerTheme.label).foregroundStyle(theme.textPrimary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: TunerTheme.rowRadius, style: .continuous).fill(active ? theme.surfaceActive : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
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
        VStack(alignment: .leading, spacing: 0) {
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
            HStack(spacing: 8) {
                Text(title).font(TunerTheme.folderTitle).foregroundStyle(theme.textLabel)
                Spacer()
                Text("Reset")
                    .font(TunerTheme.caption)
                    .foregroundStyle(resetHover ? theme.textPrimary : theme.textTertiary)
                    .onHover { resetHover = $0 }
                    .onTapGesture(perform: onReset)
                    .help("Put this group back to its defaults")
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textLabel)
                    .opacity(0.6)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .frame(height: TunerTheme.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { isOpen.toggle() }
            .focusable()
            .onKeyPress(.return) { isOpen.toggle(); return .handled }
            .onKeyPress(.space) { isOpen.toggle(); return .handled }

            if isOpen {
                content()
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Rectangle().fill(theme.surfaceSubtle).frame(height: 1)
        }
        .tunerAnimation(.easeOut(duration: 0.26), value: isOpen)
    }
}
