import AppKit
import StayAwake
import SwiftUI

/// An app's own icon, read from the Mac. Nothing is bundled: whatever keeps the Mac
/// awake shows up with its real face, including tools that do not exist yet.
struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 18

    var body: some View {
        if let image = AppIcons.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// A command-line tool has no icon of its own. When its maker's app is installed
    /// its icon is the honest stand-in; otherwise the host app's icon is used.
    /// First installed wins. Tools with no app of their maker's on the Mac (or no such app
    /// at all: Gemini CLI, Aider, Amp…) show the app they run in, which is also true.
    static let toolApps: [String: [String]] = [
        "Claude Code": ["com.anthropic.claudefordesktop"],
        "Codex": ["com.openai.codex", "com.openai.chat"],
        "Cursor Agent": ["com.todesktop.230313mzl4w4u92"],
    ]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }

    /// The bundle whose icon best stands for this reason.
    static func bundleID(for reason: HoldReason) -> String? {
        if let tool = reason.tool, let app = toolApps[tool]?.first(where: { icon(for: $0) != nil }) { return app }
        return reason.bundleID
    }
}
