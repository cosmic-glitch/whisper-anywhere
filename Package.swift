// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperAnywhere",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperAnywhere", targets: ["WhisperAnywhere"])
    ],
    targets: [
        .executableTarget(
            name: "WhisperAnywhere",
            path: "WhisperAnywhere",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WhisperAnywhereTests",
            dependencies: ["WhisperAnywhere"],
            path: "WhisperAnywhereTests"
        )
    ]
)
