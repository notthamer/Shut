import ServiceManagement

/// FR-17. `SMAppService` needs a real app bundle; from `swift run` it silently no-ops.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            Log.app.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
