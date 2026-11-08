import ProjectDescription

let probeKind = Environment.documentHostProbeKind.getString(default: "swiftui")
let fullWorkspaceProbe = probeKind == "native-workspace"
let productionNativeProbe = probeKind == "native" || fullWorkspaceProbe
let appKitProbe = probeKind == "appkit" || productionNativeProbe
let baseProbeCompilationConditions =
  productionNativeProbe
  ? "$(inherited) APPKIT_DOCUMENT_HOST_PROBE PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE"
  : appKitProbe
    ? "$(inherited) APPKIT_DOCUMENT_HOST_PROBE"
    : probeKind == "swiftui-url" ? "$(inherited) DIRECT_URL_DOCUMENT_HOST_PROBE" : "$(inherited)"
let probeCompilationConditions =
  baseProbeCompilationConditions + (fullWorkspaceProbe ? " FULL_WORKSPACE_DOCUMENT_HOST_PROBE" : "")
var probeDocumentType: [String: Plist.Value] = [
  "CFBundleTypeName": "Probe text", "CFBundleTypeRole": "Editor",
  "LSHandlerRank": "Alternate",
  "LSItemContentTypes": .array([.string("public.plain-text")]),
]
if appKitProbe { probeDocumentType["NSDocumentClass"] = "ProbeNativeDocument" }

// Diagnostic only: minimal variants are independent; native links the shared adapter.
// This standalone app never ships with Snowfolio.
let project = Project(
  name: "DocumentHostProbe",
  packages: productionNativeProbe ? [.local(path: "../../Packages/SnowfolioCore")] : [],
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
      sources: ["Sources/**"],
      dependencies: productionNativeProbe ? [.package(product: "SnowfolioUI")] : []
    ),
    .target(
      name: "DocumentHostProbeUITests", destinations: .macOS, product: .uiTests,
      bundleId: "local.snowfolio.document-host-probe.uitests",
      deploymentTargets: .macOS("27.0"), infoPlist: .default,
      sources: ["UITests/**"], dependencies: [.target(name: "DocumentHostProbe")]
    ),
  ]
)
