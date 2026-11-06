// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacDownCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "MacDownUI", targets: ["MacDownUI"]),
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
        .library(name: "RenderingCore", targets: ["RenderingCore"]),
        .library(name: "PreferencesCore", targets: ["PreferencesCore"]),
    ],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0")],
    targets: [
        .target(name: "DocumentCore"),
        .target(name: "RenderingCore"),
        .target(name: "PreferencesCore"),
        .target(name: "EditorCore"),
        .target(name: "MarkdownCore", dependencies: [
            .product(name: "cmark-gfm", package: "swift-cmark"),
            .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
        ]),
        .target(name: "MacDownUI", dependencies: ["DocumentCore", "EditorCore", "MarkdownCore", "RenderingCore", "PreferencesCore"]),
        .testTarget(name: "RenderingCoreTests", dependencies: ["RenderingCore"]),
        .testTarget(name: "PreferencesCoreTests", dependencies: ["PreferencesCore"]),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
        .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "MacDownUITests", dependencies: ["MacDownUI", "DocumentCore"]),
    ],
    swiftLanguageModes: [.v6]
)
