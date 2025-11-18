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
    targets: [
        .executableTarget(
            name: "iSwitch",
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
