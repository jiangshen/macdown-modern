// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SnowfolioCore",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "DocumentCore", targets: ["DocumentCore"]),
    .library(name: "EditorCore", targets: ["EditorCore"]),
    .library(name: "SnowfolioUI", targets: ["SnowfolioUI"]),
    .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    .library(name: "RenderingCore", targets: ["RenderingCore"]),
    .library(name: "ExportCore", targets: ["ExportCore"]),
    .library(name: "PreferencesCore", targets: ["PreferencesCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0"),
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
  ],
  targets: [
    .target(name: "DocumentCore"),
    .target(name: "CodeHighlightCore", resources: [.process("Resources")]),
    .target(name: "EmojiCore", resources: [.process("Resources")]),
    .target(name: "MathCore", resources: [.process("Resources")]),
    .target(name: "RenderingCore", dependencies: ["CodeHighlightCore", "MathCore"]),
    .target(name: "ExportCore", dependencies: ["MarkdownCore", "RenderingCore"]),
    .target(name: "PreferencesCore"),
    .target(name: "EditorCore"),
    .target(
      name: "MarkdownCore",
      dependencies: [
        "EmojiCore", "CodeHighlightCore", "MathCore",
        .product(name: "Yams", package: "Yams"),
        .product(name: "cmark-gfm", package: "swift-cmark"),
        .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
      ]),
    .target(
      name: "SnowfolioUI",
      dependencies: [
        "DocumentCore", "EditorCore", "MarkdownCore", "RenderingCore", "PreferencesCore",
        "ExportCore", "EmojiCore", "CodeHighlightCore",
      ]),
    .testTarget(name: "ExportCoreTests", dependencies: ["ExportCore", "MarkdownCore"]),
    .testTarget(name: "RenderingCoreTests", dependencies: ["RenderingCore"]),
    .testTarget(name: "PreferencesCoreTests", dependencies: ["PreferencesCore"]),
    .testTarget(
      name: "MarkdownCoreTests", dependencies: ["MarkdownCore", "CodeHighlightCore", "MathCore"]),
    .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
    .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
    .testTarget(name: "SnowfolioUITests", dependencies: ["SnowfolioUI", "DocumentCore"]),
  ],
  swiftLanguageModes: [.v6]
)
