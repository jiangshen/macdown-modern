// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacDownCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
    ],
    targets: [
        .target(name: "DocumentCore"),
        .target(name: "EditorCore"),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
    ],
    swiftLanguageModes: [.v6]
)
