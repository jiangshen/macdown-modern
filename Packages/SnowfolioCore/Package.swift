// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SnowfolioCore",
  platforms: [.macOS("27.0")],
  products: [
    .executable(name: "snowfolio", targets: ["SnowfolioCLI"]),
    .library(name: "DocumentCore", targets: ["DocumentCore"]),
    .library(name: "PluginCore", targets: ["PluginCore"]),
    .library(name: "EditorCore", targets: ["EditorCore"]),
    .library(name: "SnowfolioUI", targets: ["SnowfolioUI"]),
    .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    .library(name: "RenderingCore", targets: ["RenderingCore"]),
    .library(name: "ExportCore", targets: ["ExportCore"]),
    .library(name: "PreferencesCore", targets: ["PreferencesCore"]),
  ],
  dependencies: [
    .package(path: "../MarkdownEngine"),
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
  ],
  targets: [
    .target(name: "DocumentCore"),
    .target(name: "PluginCore"),
    .executableTarget(name: "SnowfolioCLI", dependencies: ["DocumentCore"]),
    .target(name: "CodeHighlightCore", resources: [.process("Resources")]),
    .target(name: "EmojiCore", resources: [.process("Resources")]),
    .target(name: "MathCore", resources: [.process("Resources")]),
    .target(name: "DiagramCore", dependencies: ["MathCore"], resources: [.process("Resources")]),
    .target(
      name: "RenderingCore", dependencies: ["CodeHighlightCore", "MathCore"],
      resources: [.copy("Resources/Styles"), .copy("Resources/CSS"), .copy("Resources/Templates")]),
    .target(name: "ExportCore", dependencies: ["MarkdownCore", "RenderingCore"]),
    .target(name: "PreferencesCore"),
    .target(name: "EditorCore", resources: [.copy("Resources/Themes")]),
    .target(
      name: "MarkdownCore",
      dependencies: [
        "EmojiCore", "CodeHighlightCore", "MathCore", "DiagramCore",
        .product(name: "Yams", package: "Yams"),
        .product(name: "cmark-gfm", package: "MarkdownEngine"),
        .product(name: "cmark-gfm-extensions", package: "MarkdownEngine"),
      ]),
    .target(
      name: "SnowfolioUI",
      dependencies: [
        "DocumentCore", "EditorCore", "MarkdownCore", "RenderingCore", "PreferencesCore",
        "ExportCore", "EmojiCore", "CodeHighlightCore", "PluginCore",
      ]),
    .testTarget(name: "DiagramCoreTests", dependencies: ["DiagramCore"]),
    .testTarget(name: "ExportCoreTests", dependencies: ["ExportCore", "MarkdownCore"]),
    .testTarget(name: "RenderingCoreTests", dependencies: ["RenderingCore"]),
    .testTarget(name: "PreferencesCoreTests", dependencies: ["PreferencesCore"]),
    .testTarget(
      name: "MarkdownCoreTests", dependencies: ["MarkdownCore", "CodeHighlightCore", "MathCore"],
      resources: [.process("Fixtures")]),
    .testTarget(name: "DocumentCoreTests", dependencies: ["DocumentCore"]),
    .testTarget(name: "PluginCoreTests", dependencies: ["PluginCore"]),
    .testTarget(
      name: "EditorCoreTests", dependencies: ["EditorCore"], resources: [.process("Fixtures")]),
    .testTarget(
      name: "SnowfolioUITests", dependencies: ["SnowfolioUI", "DocumentCore", "DiagramCore"]),
  ],
  swiftLanguageModes: [.v6]
)
