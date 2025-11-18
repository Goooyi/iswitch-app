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
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "iSwitch",
            dependencies: ["KeyboardShortcuts"],
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
