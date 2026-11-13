// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RhineKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RhineKit", targets: ["RhineKit"]),
    ],
    targets: [
        .target(name: "RhineKit"),
        .executableTarget(name: "rhine-probe", dependencies: ["RhineKit"]),
        .executableTarget(name: "rhine-render", dependencies: ["RhineKit"]),
        .testTarget(name: "RhineKitTests", dependencies: ["RhineKit"]),
    ],
    // Renderer and scene are main-thread objects; Swift 5 mode keeps them free of Sendable plumbing.
    swiftLanguageModes: [.v5]
)
