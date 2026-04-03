// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Statify",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "IOKitShim",
            path: "Sources/IOKitShim"
        ),
        .executableTarget(
            name: "Statify",
            dependencies: ["IOKitShim"],
            path: "Sources/Statify",
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedLibrary("IOReport"),
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Statify/Info.plist"])
            ]
        )
    ]
)
