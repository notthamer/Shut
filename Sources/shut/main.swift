import Foundation
import ShutApp

// SwiftPM entry point; scripts/build.sh wraps this binary in Shut.app.
//
//   shut                              run the menu bar app
//   shut --export-presets DIR         write the built-in presets as JSON and exit
//   shut hold ...                     keep the Mac awake with the lid shut (see `shut hold`)
let args = CommandLine.arguments
ShutApp.runCommandIfAny()
if let i = args.firstIndex(of: "--export-presets"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1])
    do {
        let written = try ShutApp.exportBuiltInPresets(to: dir)
        print("Wrote \(written.count) presets to \(dir.path)")
        exit(0)
    } catch {
        print("Export failed: \(error)")
        exit(1)
    }
}
MainActor.assumeIsolated { ShutApp.run() }
