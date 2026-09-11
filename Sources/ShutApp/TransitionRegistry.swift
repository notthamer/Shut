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

    /// The transition to actually play on the lid. Reduce Motion swaps in Fade
    /// so users who asked for less motion never see a swirl.
    public var effectiveForLid: AnyTransition {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let fade = transition(id: FadeTransition.id) {
            return fade
        }
        return current
    }
}
