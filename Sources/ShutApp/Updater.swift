import AppKit
import Security
import Sparkle

/// In-app updates through Sparkle. The feed and the EdDSA public key live in
/// Info.plist; releases are signed by the release workflow.
///
/// Only a build signed by the release team checks for updates. A copy someone
/// built from source is ad-hoc signed, and quietly replacing it with the
/// official release would be a surprise, so it just never asks.
@MainActor
final class Updater {
    /// The team that signs releases (App/Signing.xcconfig, the Xcode project).
    static let releaseTeam = "2GDVAQTV5V"

    private let controller: SPUStandardUpdaterController?

    init() {
        if Self.isSignedByReleaseTeam, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            Log.app.info("updater started")
        } else {
            controller = nil
            Log.app.info("updater off: not a release-signed build")
        }
    }

    var isEnabled: Bool { controller != nil }

    /// Sparkle's own per-user setting: check about once a day without asking.
    /// The first launch asks; this lets the user change the answer later.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// A menu item that asks Sparkle to check now. Disabled when updates are off.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        item.isEnabled = controller != nil
        return item
    }

    /// True when the running bundle's code signature carries the release team.
    static var isSignedByReleaseTeam: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return (dict[kSecCodeInfoTeamIdentifier as String] as? String) == releaseTeam
    }
}
