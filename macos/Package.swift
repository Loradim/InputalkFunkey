// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InputalkFunkey",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "InputalkFunkeyCore",
            path: "SourcesCore"
        ),
        .executableTarget(
            name: "InputalkFunkey",
            dependencies: [
                "InputalkFunkeyCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "InputalkFunkeyCoreTests",
            dependencies: ["InputalkFunkeyCore"],
            path: "Tests/InputalkFunkeyCoreTests"
        )
    ]
)
