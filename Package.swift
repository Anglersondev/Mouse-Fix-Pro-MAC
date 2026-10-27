// swift-tools-version:5.9
import PackageDescription

let release: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "MouseFixPro",
    platforms: [.macOS(.v13)],
    targets: [
        // Modelo e comunicação, usados pelos dois processos.
        .target(name: "MouseFixShared", path: "Sources/MouseFixShared", swiftSettings: release),
        // Faz o trabalho: botões, rolagem, ponteiro. Sem SwiftUI, fica sempre rodando.
        .executableTarget(name: "MouseFixProHelper", dependencies: ["MouseFixShared"],
                          path: "Sources/MouseFixProHelper", swiftSettings: release),
        // Janela de ajustes em SwiftUI. Só roda enquanto está aberta.
        .executableTarget(name: "MouseFixPro", dependencies: ["MouseFixShared"],
                          path: "Sources/MouseFixPro", swiftSettings: release),
    ]
)
