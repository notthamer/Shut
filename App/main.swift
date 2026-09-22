import ShutApp

// Xcode entry point. All real code lives in the ShutApp package library.
ShutApp.runCommandIfAny()
MainActor.assumeIsolated { ShutApp.run() }
