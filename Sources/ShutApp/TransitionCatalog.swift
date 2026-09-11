import TransitionKit

/// The styles the app ships, in gallery order. Adding one is a line here plus a
/// `register` line in TunerHost.
enum TransitionCatalog {
    static func make() -> [AnyTransition] {
        [
            AnyTransition(SinkholeTransition()),
            AnyTransition(FrostTransition()),
            AnyTransition(FoldTransition()),
            AnyTransition(CurlTransition()),
            AnyTransition(CreaseTransition()),
            AnyTransition(RecedeTransition()),
            AnyTransition(SlideTransition()),
            AnyTransition(ApertureTransition()),
            AnyTransition(ShutterTransition()),
            AnyTransition(BlindsTransition()),
            AnyTransition(FadeTransition()),
        ]
    }
}
