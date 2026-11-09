import ProjectDescription

let nativeDocumentHost = Environment.snowfolioDocumentHost.getString(default: "swiftui") == "native"
var markdownDocumentType: [String: Plist.Value] = [
  "CFBundleTypeName": "Markdown", "CFBundleTypeRole": "Editor",
  "CFBundleTypeIconFile": "MarkdownDocument", "LSHandlerRank": "Alternate",
  "LSItemContentTypes": .array([.string("net.daringfireball.markdown")]),
]
var plainDocumentType: [String: Plist.Value] = [
  "CFBundleTypeName": "Plain text", "CFBundleTypeRole": "Editor",
  "LSHandlerRank": "Alternate", "LSItemContentTypes": .array([.string("public.plain-text")]),
]
if nativeDocumentHost {
  markdownDocumentType["NSDocumentClass"] = "SnowfolioNativeDocument"
  plainDocumentType["NSDocumentClass"] = "SnowfolioNativeDocument"
}

let project = Project(
  name: "Snowfolio",
  packages: [.local(path: "../Packages/SnowfolioCore")],
  settings: .settings(base: [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .string(
      nativeDocumentHost ? "$(inherited) NATIVE_DOCUMENT_HOST" : "$(inherited)"),
    "ARCHS": "arm64",
    "ONLY_ACTIVE_ARCH": "YES",
    "MARKETING_VERSION": "0.2.0",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
  ]),
  targets: [
    .target(
      name: "Snowfolio",
      destinations: .macOS,
      product: .app,
      productName: "Snowfolio",
      bundleId: "local.macdown.modern",
      deploymentTargets: .macOS("27.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Snowfolio",
        "CFBundleName": "Snowfolio",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSPrincipalClass": "NSApplication",
        "NSAppleScriptEnabled": .boolean(nativeDocumentHost),
        "OSAScriptingDefinition": "Snowfolio.sdef",
        "LSApplicationCategoryType": "public.app-category.productivity",
        "NSHumanReadableCopyright":
          "Copyright © 2014–2020 Tzu-ping Chung and contributors. MIT License.",
        "CFBundleDocumentTypes": .array([
          .dictionary(markdownDocumentType), .dictionary(plainDocumentType),
        ]),
        "UTImportedTypeDeclarations": .array([
          .dictionary([
            "UTTypeIdentifier": "net.daringfireball.markdown",
            "UTTypeConformsTo": .array([.string("public.plain-text")]),
            "UTTypeDescription": "Markdown document",
            "UTTypeIconFile": "MarkdownDocument",
            "UTTypeIcons": .dictionary([
              "UTTypeIconBackgroundName": "MarkdownDocumentBackground",
              "UTTypeIconBadgeName": "MarkdownDocumentBadge",
              "UTTypeIconText": "MD",
            ]),
            "UTTypeTagSpecification": .dictionary([
              "public.filename-extension": .array([.string("md"), .string("markdown")]),
              "public.mime-type": .array([.string("text/markdown"), .string("text/x-markdown")]),
            ]),
          ])
        ]),
      ]),
      sources: ["Sources/**"],
      resources: [
        "Resources/AppIcon.icon", "Resources/DocumentIcons.xcassets",
        "Resources/MarkdownDocument.icns", "Resources/Licenses/**", "Resources/Snowfolio.sdef",
      ],
      dependencies: [.package(product: "SnowfolioUI")],
      settings: .settings(base: [
        "ENABLE_HARDENED_RUNTIME": "YES", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
      ])
    ),
    .target(
      name: "SnowfolioUITests",
      destinations: .macOS,
      product: .uiTests,
      bundleId: "local.macdown.modern.uitests",
      deploymentTargets: .macOS("27.0"),
      infoPlist: .extendingDefault(with: [
        "NSAppleEventsUsageDescription": "Verify Snowfolio's own document scripting interface."
      ]),
      sources: ["UITests/**"],
      dependencies: [.target(name: "Snowfolio")]
    ),
  ]
)
