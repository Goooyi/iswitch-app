// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "iSwitch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "iSwitch", targets: ["iSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "iSwitch",
            path: "Sources",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
