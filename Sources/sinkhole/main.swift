import SinkholeApp

// SwiftPM entry point; scripts/build.sh wraps this binary in Sinkhole.app.
MainActor.assumeIsolated { SinkholeApp.run() }
