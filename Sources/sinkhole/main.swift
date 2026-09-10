import Foundation
import SinkholeApp

// SwiftPM entry point; scripts/build.sh wraps this binary in Sinkhole.app.
//
//   sinkhole                          run the menu bar app
//   sinkhole --export-presets DIR     write the built-in presets as JSON and exit
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--export-presets"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1])
    do {
        let written = try SinkholeApp.exportBuiltInPresets(to: dir)
        print("Wrote \(written.count) presets to \(dir.path)")
        exit(0)
    } catch {
        print("Export failed: \(error)")
        exit(1)
    }
}
MainActor.assumeIsolated { SinkholeApp.run() }
