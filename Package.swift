// swift-tools-version:5.9
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
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "iSwitchTests",
            dependencies: ["iSwitch"],
            path: "Tests/iSwitchTests"
        )
    ]
)
