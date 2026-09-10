// swift-tools-version: 6.0
// Sinkhole — lid transitions for MacBook. See docs/PRD.md.
//
// Every library here depends only on Apple frameworks. `Tuner` intentionally has no
// dependency on `TransitionKit` or `SinkholeApp` so it can be extracted later.
import PackageDescription

let package = Package(
    name: "Sinkhole",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LidSensor", targets: ["LidSensor"]),
        .library(name: "TransitionKit", targets: ["TransitionKit"]),
        .library(name: "Tuner", targets: ["Tuner"]),
        .library(name: "SinkholeApp", targets: ["SinkholeApp"]),
        .executable(name: "lidangle-cli", targets: ["lidangle-cli"]),
        .executable(name: "sinkhole", targets: ["sinkhole"]),
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
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("SwiftUI")]
        ),

        // All app code lives in a library so both the Xcode target and the SwiftPM
        // executable are a 3-line shim over it.
        .target(
            name: "SinkholeApp",
            dependencies: ["LidSensor", "TransitionKit", "Tuner"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "sinkhole",
            dependencies: ["SinkholeApp"]
        ),

        .testTarget(name: "LidSensorTests", dependencies: ["LidSensor"]),
        .testTarget(name: "TransitionKitTests", dependencies: ["TransitionKit"]),
        .testTarget(name: "TunerTests", dependencies: ["Tuner"]),
    ],
    swiftLanguageModes: [.v5]
)
