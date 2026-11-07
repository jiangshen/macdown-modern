// swift-tools-version: 6.4
import PackageDescription

// Native C is maintained third-party parser code. First-party integration is Swift.
let package = Package(
  name: "SnowfolioMarkdownEngine",
  platforms: [.macOS("27.0")],
  products: [
    .executable(name: "cmark-audit", targets: ["cmark-audit"]),
    .library(name: "cmark-gfm", targets: ["cmark-gfm"]),
    .library(name: "cmark-gfm-extensions", targets: ["cmark-gfm-extensions"]),
  ],
  targets: [
    .executableTarget(name: "cmark-audit", dependencies: ["cmark-gfm"], path: "Audit"),
    .target(
      name: "cmark-gfm", path: "src",
      exclude: ["scanners.re", "libcmark-gfm.pc.in", "config.h.in", "CMakeLists.txt"],
      cSettings: [.define("CMARK_DISABLE_ATTRIBUTES")]),
    .target(
      name: "cmark-gfm-extensions", dependencies: ["cmark-gfm"], path: "extensions",
      exclude: ["CMakeLists.txt", "ext_scanners.re"]),
  ]
)
