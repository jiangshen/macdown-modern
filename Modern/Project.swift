import ProjectDescription

let project = Project(
  name: "MacDownModern",
  packages: [.local(path: "../Packages/MacDownCore")],
  settings: .settings(base: [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ARCHS": "arm64",
    "ONLY_ACTIVE_ARCH": "YES",
    "MARKETING_VERSION": "0.2.0",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_IDENTITY": "-",
    "CODE_SIGN_STYLE": "Manual",
  ]),
  targets: [
    .target(
      name: "MacDownModern",
      destinations: .macOS,
      product: .app,
      productName: "MacDown",
      bundleId: "local.macdown.modern",
      deploymentTargets: .macOS("27.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "MacDown",
        "CFBundleName": "MacDown",
        "NSPrincipalClass": "NSApplication",
        "LSApplicationCategoryType": "public.app-category.productivity",
        "NSHumanReadableCopyright":
          "Copyright © 2014–2020 Tzu-ping Chung and contributors. MIT License.",
        "CFBundleDocumentTypes": .array([
          .dictionary([
            "CFBundleTypeName": "Markdown",
            "CFBundleTypeRole": "Editor",
            "CFBundleTypeIconFile": "MarkdownDocument",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": .array([
              .string("net.daringfireball.markdown"),
            ]),
          ]),
          .dictionary([
            "CFBundleTypeName": "Plain text",
            "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Alternate",
            "LSItemContentTypes": .array([.string("public.plain-text")]),
          ]),
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
      resources: ["Resources/AppIcon.icon", "Resources/DocumentIcons.xcassets", "Resources/MarkdownDocument.icns", "Resources/Licenses/**"],
      dependencies: [.package(product: "MacDownUI")],
      settings: .settings(base: [
        "ENABLE_HARDENED_RUNTIME": "YES", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
      ])
    ),
    .target(
      name: "MacDownModernUITests",
      destinations: .macOS,
      product: .uiTests,
      bundleId: "local.macdown.modern.uitests",
      deploymentTargets: .macOS("27.0"),
      infoPlist: .default,
      sources: ["UITests/**"],
      dependencies: [.target(name: "MacDownModern")]
    ),
  ]
)
