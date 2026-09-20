import AppKit
import SwiftUI
import Tuner

/// The receipt, handed over when you come back.
///
/// Stay awake does its work while nobody is looking. Before this, the account of it
/// ("Claude Code kept your Mac awake for 2 h 14 min") waited inside the panel until
/// someone thought to open it. Now a small slip of the same paper appears under the
/// menu bar icon once the lid is open and the screen unlocked, stays a few seconds,
/// and fades. It never takes focus, and a click opens the Awake page.
///
/// Everything here is an event: the lid edge, the unlock notification. The one timer
/// is the dismissal, and it exists only while the slip is on screen.
@MainActor
final class ReceiptSlip {
    /// How long the desktop gets to come back (the reopen transition, the unlock
    /// animation) before the slip appears over it.
    var settleDelay: TimeInterval = 1.2
    var visibleFor: TimeInterval = 7

    private let stayAwake: StayAwakeController
    private let isLocked: @MainActor () -> Bool
    private let anotherSurfaceIsOpen: () -> Bool
    /// Puts the slip on screen. The tests replace it; the app leaves it alone.
    var present: ((HoldReceipt) -> Void)?
    var anchor: (() -> NSStatusBarButton?)?
    var openAwakePage: (() -> Void)?

    private let unlock = UnlockObserver()
    private var waitingForUnlock = false
    private var panel: NSPanel?
    private var dismissal: Timer?

    init(stayAwake: StayAwakeController,
         isLocked: @escaping @MainActor () -> Bool = { UnlockObserver.sessionIsLocked() },
         anotherSurfaceIsOpen: @escaping () -> Bool = { false }) {
        self.stayAwake = stayAwake
        self.isLocked = isLocked
        self.anotherSurfaceIsOpen = anotherSurfaceIsOpen
        unlock.onUnlock = { [weak self] in self?.sessionUnlocked() }
    }

    private var pending: HoldReceipt?

    /// From Stay awake: the lid opened on a fresh receipt.
    func lidOpened(_ receipt: HoldReceipt) {
        guard stayAwake.settings.showReceipt else { Log.awake.notice("receipt slip: switched off"); return }
        pending = receipt
        after(settleDelay) { [weak self] in
            guard let self else { return }
            // Locked (Lock when shut, or the Mac slept and woke): the desktop is not
            // there to show anything over. Wait for the unlock.
            if isLocked() { waitingForUnlock = true; Log.awake.notice("receipt slip: waiting for unlock") } else { show() }
        }
    }

    func sessionUnlocked() {
        guard waitingForUnlock else { return }
        waitingForUnlock = false
        after(settleDelay) { [weak self] in self?.show() }
    }

    private func show() {
        guard let receipt = pending, !AwakeText.receipt(receipt).isEmpty else { return }
        pending = nil
        // Only Shut's own popover stands in for the slip: it opens under the same icon and
        // its bar says the same sentence. A main window does not: it may be minimized or
        // behind everything (that rule once swallowed every slip while the window existed).
        guard !anotherSurfaceIsOpen() else { Log.awake.notice("receipt slip: the popover is open and says it"); return }
        Log.awake.notice("receipt slip: shown")
        if let present { present(receipt) } else { presentPanel(receipt) }
        // Said once. The Awake page keeps it under "Last time".
        stayAwake.perform(.ok)
    }

    private func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        if delay <= 0 { work() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    // MARK: The panel

    private func presentPanel(_ receipt: HoldReceipt) {
        close(animated: false)
        let view = ReceiptSlipView(receipt: receipt,
                                   onOpen: { [weak self] in self?.close(animated: false); self?.openAwakePage?() },
                                   onHover: { [weak self] inside in self?.hovering(inside) })
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
        scheduleDismissal(after: visibleFor)
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: AwakeText.receipt(receipt).joined(separator: " "),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func scheduleDismissal(after seconds: TimeInterval) {
        dismissal?.invalidate()
        dismissal = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(animated: true) }
        }
    }

    /// Reading it keeps it there; moving away gives it a moment more.
    private func hovering(_ inside: Bool) {
        if inside { dismissal?.invalidate() } else { scheduleDismissal(after: 2.5) }
    }

    func close(animated: Bool) {
        dismissal?.invalidate()
        dismissal = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = PopoverController.duration(0.4)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

/// The slip itself: how long in Playfair, the clock times under it, why and the battery last;
/// the spectrum line on top.
/// A hold that a limit cut short gets the Saffron wash, like the cards on the Awake page.
struct ReceiptSlipView: View {
    let receipt: HoldReceipt
    var onOpen: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    @Environment(\.tunerTheme) private var theme

    static let width: CGFloat = 340

    var body: some View {
        let slip = AwakeText.slip(receipt)
        VStack(alignment: .leading, spacing: 0) {
            SpectrumLine()
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("While the lid was shut")
                // How long, first and largest; then the clock times by themselves.
                Text(slip?.headline ?? "")
                    .font(TunerTheme.display(24)).tracking(-0.6).foregroundStyle(theme.ink)
                Text(slip?.span ?? "")
                    .font(TunerTheme.body).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote = slip?.footnote, !footnote.isEmpty {
                    Text(footnote).font(TunerTheme.bodySmall).foregroundStyle(theme.inkLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(slip?.cutShort == true ? theme.washSaffron : .clear)
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover(perform: onHover)
        .environment(\.tunerTheme, theme)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the Awake page")
        .help("What happened while the lid was shut. Click for the Awake page.")
    }
}
