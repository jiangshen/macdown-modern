import ProjectDescription

let probeKind = Environment.documentHostProbeKind.getString(default: "swiftui")
let appKitProbe = probeKind == "appkit"
let probeCompilationConditions =
  appKitProbe
  ? "$(inherited) APPKIT_DOCUMENT_HOST_PROBE"
  : probeKind == "swiftui-url" ? "$(inherited) DIRECT_URL_DOCUMENT_HOST_PROBE" : "$(inherited)"
var probeDocumentType: [String: Plist.Value] = [
  "CFBundleTypeName": "Probe text", "CFBundleTypeRole": "Editor",
  "LSHandlerRank": "Alternate",
  "LSItemContentTypes": .array([.string("public.plain-text")]),
]
if appKitProbe { probeDocumentType["NSDocumentClass"] = "ProbeNativeDocument" }

// Diagnostic only: this standalone app does not depend on or ship with Snowfolio.
let project = Project(
  name: "DocumentHostProbe",
  settings: .settings(base: [
    "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
    "ARCHS": "arm64", "ONLY_ACTIVE_ARCH": "YES",
    "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .string(probeCompilationConditions),
  ]),
  targets: [
    .target(
      name: "DocumentHostProbe", destinations: .macOS, product: .app,
      bundleId: "local.snowfolio.document-host-probe", deploymentTargets: .macOS("27.0"),
      infoPlist: .extendingDefault(with: [
        "NSPrincipalClass": "NSApplication",
        "CFBundleDocumentTypes": .array([
          .dictionary(probeDocumentType)
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
