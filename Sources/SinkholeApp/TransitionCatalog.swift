import TransitionKit

/// The transitions the app ships, in menu order. Adding one is a one-line change.
enum TransitionCatalog {
    static func make() -> [AnyTransition] {
        [
            AnyTransition(NotchDrainTransition()),
            AnyTransition(FrostTransition()),
            AnyTransition(FadeTransition()),
        ]
    }
}
