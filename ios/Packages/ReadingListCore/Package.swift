// swift-tools-version: 5.9
// ReadingListCore: every piece of Unlimited Reading List that is not a view.
// It has no UIKit or SwiftUI dependency so it builds and tests on Linux too,
// which is how the logic is verified in CI and in the Claude Code sandbox.
import PackageDescription

let package = Package(
    name: "ReadingListCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReadingListCore", targets: ["ReadingListCore"])
    ],
    targets: [
        // zlib is available on every Apple platform (libz.tbd) and on Linux via zlib1g-dev.
        // Share links are gzip so they interoperate with the web app's CompressionStream.
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib",
            providers: [.apt(["zlib1g-dev"]), .brew(["zlib"])]
        ),
        .target(
            name: "ReadingListCore",
            dependencies: ["CZlib"],
            path: "Sources/ReadingListCore"
        ),
        .testTarget(
            name: "ReadingListCoreTests",
            dependencies: ["ReadingListCore"],
            path: "Tests/ReadingListCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
