import TransitionKit

/// The transitions the app ships, in menu order. Adding one is a one-line change.
enum TransitionCatalog {
    static func make() -> [AnyTransition] {
        [
            AnyTransition(SinkholeTransition()),
            AnyTransition(FrostTransition()),
            AnyTransition(FadeTransition()),
        ]
    }
}
