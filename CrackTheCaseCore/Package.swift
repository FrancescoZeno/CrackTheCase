// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CrackTheCaseCore",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        // Not a shipping target, but SwiftPM builds/tests this package
        // against macOS by default on a Mac host; without a macOS minimum
        // it falls back to a very old default that predates the
        // Observation framework used by `@Observable` below.
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CrackTheCaseCore",
            targets: ["CrackTheCaseCore"]
        ),
    ],
    targets: [
        .target(
            name: "CrackTheCaseCore"
        ),
        .testTarget(
            name: "CrackTheCaseCoreTests",
            dependencies: ["CrackTheCaseCore"]
        ),
    ]
)
