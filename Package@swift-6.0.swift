// swift-tools-version:6.0
import PackageDescription
import Foundation

let package = Package(
    name: "swift-ass-renderer",
    platforms: [
        .iOS("27.0"),
        .tvOS("27.0"),
        .macOS("27.0")
    ],
    products: [
        .library(name: "SwiftAssRenderer", targets: ["SwiftAssRenderer"])
    ],
    dependencies: [
        .package(url: "https://github.com/mihai8804858/swift-snapshot-testing", branch: "main"),
        .package(url: "https://github.com/TheFireKahuna/swift-libass", exact: "1.4.0-fire.2"),
        .package(url: "https://github.com/pointfreeco/combine-schedulers", .upToNextMajor(from: "1.0.0"))
    ],
    targets: [
        .target(
            name: "SwiftAssRenderer",
            dependencies: [
                .target(name: "SwiftAssBlend"),
                .product(name: "SwiftLibass", package: "swift-libass"),
                .product(name: "CombineSchedulers", package: "combine-schedulers")
            ],
            path: "Sources/SwiftAssRenderer",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "SwiftAssBlend",
            dependencies: [
                .product(name: "SwiftLibass", package: "swift-libass")
            ],
            path: "Sources/SwiftAssBlend",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SwiftAssRendererTests",
            dependencies: [
                .target(name: "SwiftAssRenderer"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests",
            exclude: ["Pipeline/__Snapshots__"],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/Subs")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
