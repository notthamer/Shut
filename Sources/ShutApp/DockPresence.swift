import AppKit

/// Shut lives in the menu bar, but shows a Dock icon while one of its windows is
/// open (popover, Tuner, welcome), so the app is findable and Command-Tab-able
/// exactly when it has something to show, and invisible otherwise.
@MainActor
final class DockPresence {
    private var visible = Set<String>()

    func retain(_ key: String) {
        let wasEmpty = visible.isEmpty
        visible.insert(key)
        if wasEmpty { NSApp.setActivationPolicy(.regular) }
    }

    func release(_ key: String) {
        visible.remove(key)
        if visible.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
