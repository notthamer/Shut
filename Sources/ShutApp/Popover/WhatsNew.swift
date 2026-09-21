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
        let onShow: () -> Void = { [weak self] in self?.close(); self?.showMe?() }
        let onClose: () -> Void = { [weak self] in self?.close() }
        // A release with a tour shows it; any other gets the words from the changelog.
        let view = WhatsNewTour.slides(for: version).map { AnyView(WhatsNewTourView(slides: $0, version: version, onShow: onShow, onClose: onClose)) }
            ?? AnyView(WhatsNewView(news: news, version: version, onShow: onShow, onClose: onClose))
        let hosting = FirstMouseHostingView(rootView: view)
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
                    PrimaryButton("Show me", action: onShow)
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

// MARK: - The tour: a release worth showing, shown

/// A few slides for a release with something to see. Each is one idea: a small stage with the
/// real thing on it (the eyes, the switch, the battery card; drawn live, never a picture that
/// can go out of date), a headline, and one sentence. Some stages can be played with; what
/// they change is only the slide.
enum WhatsNewTour {
    enum Stage: Equatable { case eyesWake, lidAnswer, twoWays, batteryAndReceipt }

    struct Slide: Equatable {
        let stage: Stage
        let headline: String
        let detail: String
    }

    static func slides(for version: String) -> [Slide]? {
        guard version.hasPrefix("0.3") else { return nil }
        return [
            Slide(stage: .eyesWake, headline: "Close the lid. It keeps working.",
                  detail: "New: Stay awake. Your Mac stays awake while something is working, and sleeps by itself when it is done."),
            Slide(stage: .lidAnswer, headline: "You always know what the lid will do.",
                  detail: "Eyes open, it stays awake. Eyes shut, the lid sleeps it. Try it."),
            Slide(stage: .twoWays, headline: "Automatic, or for a set time.",
                  detail: "Let your apps decide, or keep it awake for as long as you say. One click either way."),
            Slide(stage: .batteryAndReceipt, headline: "It minds the battery, and tells you what happened.",
                  detail: "It lets your Mac sleep under a battery level you choose. When you open the lid again, a note says how it went."),
        ]
    }
}

struct WhatsNewTourView: View {
    let slides: [WhatsNewTour.Slide]
    let version: String
    var onShow: () -> Void = {}
    var onClose: () -> Void = {}
    @State var index = 0
    @Environment(\.tunerTheme) private var theme

    static let width: CGFloat = 440
    static let stageHeight: CGFloat = 170

    init(slides: [WhatsNewTour.Slide], version: String, index: Int = 0, onShow: @escaping () -> Void = {}, onClose: @escaping () -> Void = {}) {
        self.slides = slides; self.version = version; self.onShow = onShow; self.onClose = onClose
        _index = State(initialValue: index)
    }

    private var slide: WhatsNewTour.Slide { slides[min(index, slides.count - 1)] }
    private var isLast: Bool { index >= slides.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpectrumLine()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow("New in Shut \(version)")
                    Spacer()
                    Text("\(index + 1) / \(slides.count)").font(TunerTheme.mono(10)).foregroundStyle(theme.inkTertiary)
                }
                TourStage(stage: slide.stage)
                    .frame(maxWidth: .infinity).frame(height: Self.stageHeight)
                    .background(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous).fill(theme.linen))
                    .clipShape(RoundedRectangle(cornerRadius: TunerTheme.cardRadius, style: .continuous))
                    .id(index).transition(.opacity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(slide.headline).font(TunerTheme.display(22)).tracking(-0.5).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(slide.detail).font(TunerTheme.body).foregroundStyle(theme.inkLabel).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Every slide the same height, so the card never jumps under the pointer.
                .frame(height: 118, alignment: .topLeading)
                .id(index).transition(.opacity)
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(slides.indices, id: \.self) { i in
                            Circle().fill(i == index ? theme.ink : theme.inkTertiary.opacity(0.45)).frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityElement().accessibilityLabel("Slide \(index + 1) of \(slides.count)")
                    Spacer()
                    // Never a trap: leaving is on every slide.
                    QuietButton("Later", action: onClose)
                    if index > 0 { QuietButton("Back") { index -= 1 } }
                    PrimaryButton(isLast ? "Show me" : "Next") { if isLast { onShow() } else { index += 1 } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
        }
        .frame(width: Self.width)
        .tunerAnimation(TunerTheme.ease, value: index)
        .tunerThemed()
    }
}

/// What is on a slide's stage. State here is the slide's own: nothing on a stage touches
/// the app's settings.
struct TourStage: View {
    let stage: WhatsNewTour.Stage
    @State private var on = false
    @State private var timed = false
    @Environment(\.tunerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch stage {
        case .eyesWake:
            // Asleep as the slide arrives, awake a moment later: the feature's first act.
            AwakeEyes(mood: on ? .awake : .asleep, pixel: 6, tint: theme.ink, dreams: true)
                .tunerAnimation(TunerTheme.ease, value: on)
                .onAppear {
                    if reduceMotion { on = true } else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { on = true } }
                }
        case .lidAnswer:
            VStack(spacing: 12) {
                AwakeEyes(mood: on ? .awake : .shut, pixel: 4, tint: theme.ink, dreams: false)
                Text(on ? "Closing the lid keeps your Mac awake." : "Closing the lid will sleep your Mac.")
                    .font(TunerTheme.display(17)).tracking(-0.3).foregroundStyle(theme.ink)
                ModeSwitch(options: ["Nothing is working", "An agent is working"], selection: on ? 1 : 0) { on = $0 == 1 }
                    .frame(width: 340)
            }
            .tunerAnimation(TunerTheme.ease, value: on)
        case .twoWays:
            VStack(alignment: .leading, spacing: 12) {
                ModeSwitch(options: ["Automatically", "For a set time"], selection: timed ? 1 : 0) { timed = $0 == 1 }
                Text(timed ? "Your Mac stays awake until \(AwakeText.clock(Date().addingTimeInterval(3600)))."
                           : "Stays awake while an app is busy, and sleeps by itself when that ends.")
                    .font(TunerTheme.body).foregroundStyle(theme.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 40, alignment: .topLeading)
            }
            .frame(width: 340)
            .tunerAnimation(TunerTheme.ease, value: timed)
        case .batteryAndReceipt:
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery 18 % · too low").font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    BatteryMeter(percent: 18, floor: 20).padding(.top, 4)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.washSaffron))
                HStack(spacing: 6) {
                    Text("Awake for 1 h 34 min").font(TunerTheme.bodyMedium).foregroundStyle(theme.ink)
                    Text("· Battery 82 → 64 %").font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(.card, radius: 10)
            }
            .frame(width: 340)
        }
    }
}
