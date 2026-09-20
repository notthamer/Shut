import AppKit
import SwiftUI
import Tuner

/// "What's new", once, after an update: a card of the same paper as the receipt slip, under
/// the menu bar icon. Its words are this version's section of CHANGELOG.md, which
/// scripts/build.sh puts in the app as `WhatsNew.md`; the same section is the GitHub release
/// notes and what Sparkle's update window shows. One source, three places.
struct WhatsNew: Equatable {
    /// "Stay awake"
    let title: String
    /// The sentence after the title.
    let lead: String
    /// The first list, up to the next heading.
    let points: [String]

    /// Reads the changelog's Markdown: a first paragraph that opens with a **bold title.**,
    /// then "- " points until the next bold heading. Anything else: no card.
    static func parse(_ markdown: String) -> WhatsNew? {
        var title = "", lead = "", points: [String] = []
        var seenTitle = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("**") {
                if seenTitle { break }                      // "**Also**": the second section
                seenTitle = true
                let parts = line.dropFirst(2).components(separatedBy: "**")
                title = plain(parts.first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                lead = plain(parts.dropFirst().joined(separator: "")).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- ") {
                points.append(plain(String(line.dropFirst(2))))
            }
        }
        // A fix-only release has no bold title: its first point carries the card.
        if !seenTitle, let first = points.first { return WhatsNew(title: "", lead: first, points: Array(points.dropFirst())) }
        return seenTitle ? WhatsNew(title: title, lead: lead, points: points) : nil
    }

    /// A point's first sentence. The changelog writes each point as a short claim and then its
    /// detail ("Reasons, not timers. Your Mac stays awake while…"); the card shows the claim.
    static func claim(of point: String) -> String {
        guard let end = point.range(of: ". ") else { return point }
        return String(point[..<end.lowerBound]) + "."
    }

    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }

    /// The notes scripts/build.sh put in the app. nil under Xcode or `swift run`: no card.
    static func bundled() -> WhatsNew? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Whether this launch is the first of a new version for someone who already had Shut.
    /// A new install gets the welcome instead, and the same version never asks twice. A copy
    /// from before the card existed has no `lastSeen` but has finished its first run.
    static func isDue(current: String, lastSeen: String?, hasCompletedFirstRun: Bool) -> Bool {
        guard hasCompletedFirstRun else { return false }
        return lastSeen != current
    }
}

/// Puts the card under the menu bar icon. It stays until it is answered: news is not a
/// receipt, and nobody should miss it by looking away for seven seconds.
@MainActor
final class WhatsNewCard {
    var anchor: (() -> NSStatusBarButton?)?
    var showMe: (() -> Void)?
    private var panel: NSPanel?

    func show(_ news: WhatsNew, version: String) {
        close()
        let view = WhatsNewView(news: news, version: version,
                                onShow: { [weak self] in self?.close(); self?.showMe?() },
                                onClose: { [weak self] in self?.close() })
        let hosting = FirstMouseHostingView(rootView: AnyView(view))
        hosting.sizingOptions = [.intrinsicContentSize]
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        let chrome = PanelChrome(frame: NSRect(origin: .zero, size: size))
        chrome.install(hosting)
        panel.contentView = chrome
        panel.setFrameOrigin(PopoverController.origin(for: size, under: anchor?()))
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PopoverController.duration(0.25)
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct WhatsNewView: View {
    let news: WhatsNew
    let version: String
    var onShow: () -> Void = {}
    var onClose: () -> Void = {}
    @Environment(\.tunerTheme) private var theme

    static let width: CGFloat = 380
    /// The card is an invitation, not the changelog: the first few points, the rest a click away.
    static let shownPoints = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpectrumLine()
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("New in Shut \(version)")
                if !news.title.isEmpty {
                    Text(news.title).font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink)
                }
                Text(news.lead).font(TunerTheme.body).foregroundStyle(theme.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(news.points.prefix(Self.shownPoints).enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(theme.inkTertiary).frame(width: 3, height: 3).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                            Text(WhatsNew.claim(of: point)).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel).lineSpacing(2)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                HStack(spacing: 14) {
                    CapsuleButton("Show me", action: onShow)
                    QuietButton("Later", action: onClose)
                    Spacer()
                    if news.points.count > Self.shownPoints {
                        Link("All changes", destination: URL(string: "https://github.com/notthamer/Shut/releases/tag/v\(version)")!)
                            .font(TunerTheme.bodySmall).foregroundStyle(theme.inkTertiary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
        }
        .frame(width: Self.width)
        .tunerThemed()
    }
}
