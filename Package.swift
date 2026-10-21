// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyEQ",
    defaultLocalization: "en",
    platforms: [.macOS("14.4")],
    products: [
        .executable(name: "EasyEQ", targets: ["EasyEQ"]),
    ],
    targets: [
        .target(
            name: "EasyEQCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "EasyEQAudio",
            dependencies: ["EasyEQCore"]
        ),
        .executableTarget(
            name: "EasyEQ",
            dependencies: ["EasyEQCore", "EasyEQAudio"]
        ),
        .testTarget(
            name: "EasyEQCoreTests",
            dependencies: ["EasyEQCore"]
        ),
        .testTarget(
            name: "EasyEQAudioTests",
            dependencies: ["EasyEQAudio", "EasyEQCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
