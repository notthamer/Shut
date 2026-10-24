import AppKit
import SwiftUI

/// Whether the window a view sits in is really on screen: ordered in, not minimized, not
/// wholly covered. Every clock in the panel reads it (the glyph's breath, the eyes' glances)
/// and stops when it is false, so a window minimized to the Dock costs what a closed one
/// does: nothing. Measured before this: the panel minimized read 34 % of a core and 117 MB,
/// because a TimelineView keeps ticking in a window nobody can see and SwiftUI lays the
/// whole panel out on every tick. At rest the app reads 0.1 % and 23 MB.
private struct WindowOnScreenKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var windowOnScreen: Bool {
        get { self[WindowOnScreenKey.self] }
        set { self[WindowOnScreenKey.self] = newValue }
    }
}

extension View {
    /// Put on a window's root view: everything under it learns whether the window is on screen.
    func pausesClocksOffScreen() -> some View { modifier(WindowPresence()) }
}

private struct WindowPresence: ViewModifier {
    @State private var onScreen = true
    func body(content: Content) -> some View {
        content
            .environment(\.windowOnScreen, onScreen)
            .background(WindowWatcher(onScreen: $onScreen).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

/// A zero-size view that listens to its window. The window's own notifications say when
/// it is minimized, uncovered, ordered out or closing; nothing is polled.
private struct WindowWatcher: NSViewRepresentable {
    @Binding var onScreen: Bool
    func makeNSView(context: Context) -> WindowWatcherView { let view = WindowWatcherView(); view.onChange = { onScreen = $0 }; return view }
    func updateNSView(_ view: WindowWatcherView, context: Context) { view.onChange = { onScreen = $0 } }
}

final class WindowWatcherView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { DispatchQueue.main.async { [weak self] in self?.onChange?(false) }; return }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.report() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in self?.onChange?(false) })
        // Not during layout: the first answer comes a turn later.
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    private func report() { onChange?(Self.isOnScreen(window)) }

    /// The one rule: visible, not minimized, and at least partly uncovered.
    static func isOnScreen(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
