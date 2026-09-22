import AppKit

/// Shut lives in the menu bar, but shows a Dock icon while one of its windows is
/// open (popover, Tuner, welcome), so the app is findable and Command-Tab-able
/// exactly when it has something to show, and invisible otherwise.
@MainActor
final class DockPresence {
    private var visible = Set<String>()
    /// The user's choice: a Dock icon at all times, or menu bar only.
    var alwaysVisible = true { didSet { apply() } }
    /// Told when the first of Shut's windows opens and when the last one closes,
    /// so live readouts only run while there is someone to read them.
    var onSurfacesChanged: ((Bool) -> Void)?

    func retain(_ key: String) {
        visible.insert(key)
        apply()
    }

    func release(_ key: String) {
        visible.remove(key)
        apply()
    }

    private var hadSurfaces = false

    private func apply() {
        let hasSurfaces = visible.contains("popover") || visible.contains("window")
        if hasSurfaces != hadSurfaces {
            hadSurfaces = hasSurfaces
            onSurfacesChanged?(hasSurfaces)
        }
        let wanted: NSApplication.ActivationPolicy = (alwaysVisible || !visible.isEmpty) ? .regular : .accessory
        if NSApp.activationPolicy() != wanted { NSApp.setActivationPolicy(wanted) }
    }
}
