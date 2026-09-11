import AppKit
import Combine
import TransitionKit

/// Every transition the app knows about, in menu order, plus the active one.
@MainActor
public final class TransitionRegistry: ObservableObject {
    public let all: [AnyTransition]
    @Published public private(set) var current: AnyTransition

    public init(transitions: [AnyTransition], currentID: String) {
        all = transitions
        current = transitions.first { $0.id == currentID } ?? transitions[0]
    }

    public func select(id: String) {
        guard let t = all.first(where: { $0.id == id }) else { return }
        current = t
    }

    public func transition(id: String) -> AnyTransition? {
        all.first { $0.id == id }
    }

    /// Updated by the controller's 2 s poll; keeps CGPreflight off the sensor path.
    @Published public var captureAvailable: Bool = ScreenRecordingPermission.isGranted

    /// The transition to actually play on the lid. Reduce Motion, or a snapshot
    /// style without Screen Recording, substitutes Fade rather than showing nothing.
    public var effectiveForLid: AnyTransition {
        guard let fade = transition(id: FadeTransition.id) else { return current }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return fade }
        if current.needsSnapshot && !captureAvailable { return fade }
        return current
    }

    /// True when the chosen style is not the one being rendered.
    public var isSubstituting: Bool { effectiveForLid.id != current.id }
}
