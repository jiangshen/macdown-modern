import ProjectDescription

// Diagnostic only: this standalone app does not depend on or ship with Snowfolio.
let project = Project(
  name: "DocumentHostProbe",
  settings: .settings(base: [
    "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
    "ARCHS": "arm64", "ONLY_ACTIVE_ARCH": "YES",
    "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
  ]),
  targets: [
    .target(
      name: "DocumentHostProbe", destinations: .macOS, product: .app,
      bundleId: "local.snowfolio.document-host-probe", deploymentTargets: .macOS("27.0"),
      infoPlist: .extendingDefault(with: [
        "NSPrincipalClass": "NSApplication",
        "CFBundleDocumentTypes": .array([
          .dictionary([
            "CFBundleTypeName": "Probe text", "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": .array([.string("public.plain-text")]),
          ])
        ]),
      ]),
      sources: ["Sources/**"]
    ),
    .target(
      name: "DocumentHostProbeUITests", destinations: .macOS, product: .uiTests,
      bundleId: "local.snowfolio.document-host-probe.uitests",
      deploymentTargets: .macOS("27.0"), infoPlist: .default,
      sources: ["UITests/**"], dependencies: [.target(name: "DocumentHostProbe")]
    ),
  ]
)
