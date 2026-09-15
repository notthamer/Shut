import TransitionKit

/// The styles the app ships, in gallery order. Adding one is a line here plus a
/// `register` line in TunerHost.
enum TransitionCatalog {
    static func make() -> [AnyTransition] {
        [
            AnyTransition(FoldTransition()),      // the default: the hinge, made visible
            AnyTransition(SinkholeTransition()),  // the headline
            AnyTransition(FrostTransition()),
            AnyTransition(CreaseTransition()),
            AnyTransition(RecedeTransition()),
            AnyTransition(SlideTransition()),
            AnyTransition(ShutterTransition()),
            AnyTransition(FadeTransition()),
        ]
    }
}
