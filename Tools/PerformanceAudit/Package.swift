// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SnowfolioPerformanceAudit",
  platforms: [.macOS("27.0")],
  dependencies: [
    .package(path: "../../Packages/SnowfolioCore"),
    .package(path: "../../Packages/MarkdownEngine"),
  ],
  targets: [
    .executableTarget(
      name: "NativeEditorAudit",
      dependencies: [
        .product(name: "SnowfolioUI", package: "SnowfolioCore"),
        .product(name: "DocumentCore", package: "SnowfolioCore"),
      ]),
    .executableTarget(
      name: "EngineComparisonAudit",
      dependencies: [
        .product(name: "MarkdownCore", package: "SnowfolioCore"),
        .product(name: "cmark-gfm", package: "MarkdownEngine"),
        .product(name: "cmark-gfm-extensions", package: "MarkdownEngine"),
      ]),
    .executableTarget(
      name: "PerformanceAudit",
      dependencies: [.product(name: "MarkdownCore", package: "SnowfolioCore")]),
    .executableTarget(
      name: "ReadingStyleAudit",
      dependencies: [.product(name: "RenderingCore", package: "SnowfolioCore")]),
  ],
  swiftLanguageModes: [.v6]
)
