// swift-tools-version: 6.0
// Shut — lid transitions for MacBook. See README.md and docs/ARCHITECTURE.md.
//
// Every library here depends only on Apple frameworks. `Tuner` intentionally has no
// dependency on `TransitionKit` or `ShutApp` so it can be extracted later.
import PackageDescription

let package = Package(
    name: "Shut",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LidSensor", targets: ["LidSensor"]),
        .library(name: "StayAwake", targets: ["StayAwake"]),
        .library(name: "TransitionKit", targets: ["TransitionKit"]),
        .library(name: "Tuner", targets: ["Tuner"]),
        .library(name: "ShutApp", targets: ["ShutApp"]),
        .executable(name: "lidangle-cli", targets: ["lidangle-cli"]),
        .executable(name: "shut", targets: ["shut"]),
    ],
    dependencies: [
        // The one third-party dependency: in-app updates. Everything else is Apple frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        // Sensor access: IOKit HID, smoothing, velocity, adaptive polling.
        .target(
            name: "LidSensor",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "lidangle-cli",
            dependencies: ["LidSensor"]
        ),

        // Staying awake with the lid shut: reasons, limits, and the one kernel call.
        // No dependency on the rest of the project, like LidSensor.
        .target(
            name: "StayAwake",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        ),

        // Rendering: Transition protocol, shared Metal renderer, the transitions.
        .target(
            name: "TransitionKit",
            dependencies: ["Tuner"],
            // The .metal sources are copied verbatim into the resource bundle and compiled
            // once at launch (see ShaderLibrary). Same behaviour under Xcode and swift build.
            resources: [.copy("Shaders")],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AppKit"),
            ]
        ),

        // The tuning panel. Zero dependencies on the rest of the project.
        .target(
            name: "Tuner",
            resources: [.copy("Fonts")],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),

        // All app code lives in a library so both the Xcode target and the SwiftPM
        // executable are a 3-line shim over it.
        .target(
            name: "ShutApp",
            dependencies: ["LidSensor", "StayAwake", "TransitionKit", "Tuner", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.copy("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "shut",
            dependencies: ["ShutApp"],
            // Sparkle.framework is embedded in Shut.app/Contents/Frameworks by scripts/build.sh;
            // the executable has to look for it there.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),

        .testTarget(name: "LidSensorTests", dependencies: ["LidSensor"]),
        .testTarget(name: "StayAwakeTests", dependencies: ["StayAwake"]),
        .testTarget(name: "TransitionKitTests", dependencies: ["TransitionKit"]),
        .testTarget(name: "TunerTests", dependencies: ["Tuner"]),
        .testTarget(name: "ShutAppTests", dependencies: ["ShutApp"]),
    ],
    swiftLanguageModes: [.v5]
)
