// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseFixPro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MouseFixPro",
            path: "Sources/MouseFixPro",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
