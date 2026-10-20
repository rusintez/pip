// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pip",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pip", targets: ["Pip"])],
    targets: [
        .executableTarget(name: "Pip"),
        .testTarget(name: "PipTests", dependencies: ["Pip"])
    ]
)
