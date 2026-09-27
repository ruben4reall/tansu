// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TansuKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TansuCore", targets: ["TansuCore"]),
        .library(name: "TansuSystem", targets: ["TansuSystem"]),
        .library(name: "TansuUI", targets: ["TansuUI"]),
        .library(name: "TansuApp", targets: ["TansuApp"]),
    ],
    targets: [
        // Drawers, Smart Sort, layout planning, settings: Foundation only, so `swift test` covers every rule.
        .target(name: "TansuCore", resources: [.process("Resources")]),
        // The two menu bar engines (macOS 26 and 27) and the system services around them.
        .target(name: "TansuSystem", dependencies: ["TansuCore"]),
        // Drawers, search, the welcome and Settings windows.
        .target(name: "TansuUI", dependencies: ["TansuCore", "TansuSystem"], resources: [.process("Resources")]),
        // The model and the coordinator that wire the engine, the interface and the services together.
        .target(name: "TansuApp", dependencies: ["TansuCore", "TansuSystem", "TansuUI"]),
        .testTarget(name: "TansuCoreTests", dependencies: ["TansuCore"]),
        .testTarget(name: "TansuSystemTests", dependencies: ["TansuSystem", "TansuCore"]),
        .testTarget(name: "TansuUITests", dependencies: ["TansuUI", "TansuSystem", "TansuCore"]),
        .testTarget(name: "TansuAppTests", dependencies: ["TansuApp", "TansuUI", "TansuSystem", "TansuCore"]),
    ]
)
