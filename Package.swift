// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "iSwitch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "iSwitch", targets: ["iSwitch"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "iSwitch",
            dependencies: [],
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags([
                    "-Xfrontend",
                    "-disable-round-trip-debug-types"
                ], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "iSwitchTests",
            dependencies: ["iSwitch"],
            path: "Tests/iSwitchTests"
        )
    ]
)
