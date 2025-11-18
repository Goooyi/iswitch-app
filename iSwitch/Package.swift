// swift-tools-version:5.9
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
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Resources/Info.plist"])
            ]
        )
    ]
)
