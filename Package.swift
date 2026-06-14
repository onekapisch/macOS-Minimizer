// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Minimizer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Minimizer",
            path: "Sources/Minimizer"
        ),
        .testTarget(
            name: "MinimizerTests",
            dependencies: ["Minimizer"],
            path: "Tests/MinimizerTests"
        )
    ]
)
