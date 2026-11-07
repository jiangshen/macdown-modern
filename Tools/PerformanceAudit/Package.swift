// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SnowfolioPerformanceAudit",
  platforms: [.macOS("27.0")],
  dependencies: [.package(path: "../../Packages/SnowfolioCore")],
  targets: [
    .executableTarget(
      name: "PerformanceAudit",
      dependencies: [.product(name: "MarkdownCore", package: "SnowfolioCore")]),
    .executableTarget(
      name: "ReadingStyleAudit",
      dependencies: [.product(name: "RenderingCore", package: "SnowfolioCore")]),
  ],
  swiftLanguageModes: [.v6]
)
