// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseFixLite",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MouseFixLite",
            path: "Sources/MouseFixLite",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
