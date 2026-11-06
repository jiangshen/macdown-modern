// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacDownCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "MacDownUI", targets: ["MacDownUI"]),
    ],
    targets: [
        .target(name: "DocumentCore"),
        .target(name: "EditorCore"),
        .target(name: "MacDownUI", dependencies: ["DocumentCore", "EditorCore"]),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "MacDownUITests", dependencies: ["MacDownUI", "DocumentCore"]),
    ],
    swiftLanguageModes: [.v6]
)
