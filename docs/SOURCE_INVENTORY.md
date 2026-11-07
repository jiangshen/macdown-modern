# Source inventory

Snapshot before Swift migration. No Swift implementation files were present.

First-party files: 72; lines: 8336.

| File | Lines | Migration area | Imported boundaries |
| --- | ---: | --- | --- |
| `MacDown/Code/Application/MPExportPanelAccessoryViewController.h` | 16 | App/Features | <Cocoa/Cocoa.h> |
| `MacDown/Code/Application/MPExportPanelAccessoryViewController.m` | 23 | App/Features | "MPExportPanelAccessoryViewController.h" |
| `MacDown/Code/Application/MPMainController.h` | 16 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Application/MPMainController.m` | 364 | App/Features | "MPMainController.h", <MASPreferences/MASPreferencesWindowController.h>, <Sparkle/SUUpdater.h>, "MPGlobals.h", "MPUtilities.h", "NSDocumentController+Document.h", "NSUserDefaults+Suite.h", "MPPreferences.h", "MPGeneralPreferencesViewController.h", "MPMarkdownPreferencesViewController.h", "MPEditorPreferencesViewController.h", "MPHtmlPreferencesViewController.h", "MPTerminalPreferencesViewController.h", "MPDocument.h" |
| `MacDown/Code/Application/MPPlugInController.h` | 15 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Application/MPPlugInController.m` | 74 | App/Features | "NSString+Lookup.h", "MPPlugIn.h", "MPPlugInController.h", "MPUtilities.h" |
| `MacDown/Code/Application/MPToolbarController.h` | 16 | App/Features | <Foundation/Foundation.h>, "MPDocument.h" |
| `MacDown/Code/Application/MPToolbarController.m` | 302 | App/Features | "MPToolbarController.h" |
| `MacDown/Code/Document/MPAsset.h` | 42 | Document / Preview / RenderingCore | <Foundation/Foundation.h> |
| `MacDown/Code/Document/MPAsset.m` | 191 | Document / Preview / RenderingCore | "MPAsset.h", <HBHandlebars/HBHandlebars.h>, "MPUtilities.h" |
| `MacDown/Code/Document/MPDocument.h` | 22 | Document / Preview / RenderingCore | <Cocoa/Cocoa.h> |
| `MacDown/Code/Document/MPDocument.m` | 2017 | Document / Preview / RenderingCore | "MPDocument.h", <WebKit/WebKit.h>, <JJPluralForm/JJPluralForm.h>, <hoedown/html.h>, "hoedown_html_patch.h", "HGMarkdownHighlighter.h", "MPUtilities.h", "MPAutosaving.h", "NSColor+HTML.h", "NSDocumentController+Document.h", "NSPasteboard+Types.h", "NSString+Lookup.h", "NSTextView+Autocomplete.h", "DOMNode+Text.h", "MPPreferences.h", "MPDocumentSplitView.h", "MPEditorView.h", "MPRenderer.h", "MPPreferencesViewController.h", "MPEditorPreferencesViewController.h", "MPExportPanelAccessoryViewController.h", "MPMathJaxListener.h", "WebView+WebViewPrivateHeaders.h", "MPToolbarController.h", <JavaScriptCore/JavaScriptCore.h> |
| `MacDown/Code/Document/MPRenderer.h` | 64 | Document / Preview / RenderingCore | <Foundation/Foundation.h> |
| `MacDown/Code/Document/MPRenderer.m` | 704 | Document / Preview / RenderingCore | "MPRenderer.h", <limits.h>, <hoedown/html.h>, <hoedown/document.h>, <HBHandlebars/HBHandlebars.h>, "hoedown_html_patch.h", "NSJSONSerialization+File.h", "NSObject+HTMLTabularize.h", "NSString+Lookup.h", "MPUtilities.h", "MPAsset.h", "MPPreferences.h" |
| `MacDown/Code/Extension/DOMNode+Text.h` | 25 | EditorCore / RenderingCore / native adapters | <WebKit/WebKit.h> |
| `MacDown/Code/Extension/DOMNode+Text.m` | 133 | EditorCore / RenderingCore / native adapters | "DOMNode+Text.h" |
| `MacDown/Code/Extension/NSColor+HTML.h` | 15 | EditorCore / RenderingCore / native adapters | <Cocoa/Cocoa.h> |
| `MacDown/Code/Extension/NSColor+HTML.m` | 228 | EditorCore / RenderingCore / native adapters | "NSColor+HTML.h" |
| `MacDown/Code/Extension/NSDocumentController+Document.h` | 16 | EditorCore / RenderingCore / native adapters | <Cocoa/Cocoa.h> |
| `MacDown/Code/Extension/NSDocumentController+Document.m` | 30 | EditorCore / RenderingCore / native adapters | "NSDocumentController+Document.h" |
| `MacDown/Code/Extension/NSJSONSerialization+File.h` | 16 | EditorCore / RenderingCore / native adapters | <Foundation/Foundation.h> |
| `MacDown/Code/Extension/NSJSONSerialization+File.m` | 23 | EditorCore / RenderingCore / native adapters | "NSJSONSerialization+File.h" |
| `MacDown/Code/Extension/NSObject+HTMLTabularize.h` | 15 | EditorCore / RenderingCore / native adapters | <Foundation/Foundation.h> |
| `MacDown/Code/Extension/NSObject+HTMLTabularize.m` | 119 | EditorCore / RenderingCore / native adapters | "NSObject+HTMLTabularize.h", <HBHandlebars/HBHandlebars.h>, <M13OrderedDictionary/M13OrderedDictionary.h> |
| `MacDown/Code/Extension/NSPasteboard+Types.h` | 15 | EditorCore / RenderingCore / native adapters | <Cocoa/Cocoa.h> |
| `MacDown/Code/Extension/NSPasteboard+Types.m` | 40 | EditorCore / RenderingCore / native adapters | "NSPasteboard+Types.h" |
| `MacDown/Code/Extension/NSString+Lookup.h` | 24 | EditorCore / RenderingCore / native adapters | <Foundation/Foundation.h> |
| `MacDown/Code/Extension/NSString+Lookup.m` | 119 | EditorCore / RenderingCore / native adapters | "NSString+Lookup.h", "YAMLSerialization.h", "MPUtilities.h" |
| `MacDown/Code/Extension/NSTextView+Autocomplete.h` | 38 | EditorCore / RenderingCore / native adapters | <Cocoa/Cocoa.h> |
| `MacDown/Code/Extension/NSTextView+Autocomplete.m` | 730 | EditorCore / RenderingCore / native adapters | "NSTextView+Autocomplete.h", "NSString+Lookup.h", "MPUtilities.h" |
| `MacDown/Code/Extension/NSUserDefaults+Suite.h` | 18 | EditorCore / RenderingCore / native adapters | <Foundation/Foundation.h> |
| `MacDown/Code/Extension/NSUserDefaults+Suite.m` | 40 | EditorCore / RenderingCore / native adapters | "NSUserDefaults+Suite.h" |
| `MacDown/Code/Extension/WebView+WebViewPrivateHeaders.h` | 26 | EditorCore / RenderingCore / native adapters | <WebKit/WebKit.h> |
| `MacDown/Code/Extension/hoedown_html_patch.h` | 39 | EditorCore / RenderingCore / native adapters |  |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.h` | 17 | Settings / Preferences migration | "MPPreferencesViewController.h", <MASPreferences/MASPreferencesViewController.h> |
| `MacDown/Code/Preferences/MPEditorPreferencesViewController.m` | 158 | Settings / Preferences migration | "MPEditorPreferencesViewController.h", "MPUtilities.h", "MPPreferences.h" |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.h` | 15 | Settings / Preferences migration | "MPPreferencesViewController.h", <MASPreferences/MASPreferencesViewController.h> |
| `MacDown/Code/Preferences/MPGeneralPreferencesViewController.m` | 49 | Settings / Preferences migration | "MPGeneralPreferencesViewController.h", "MPPreferences.h" |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.h` | 15 | Settings / Preferences migration | "MPPreferencesViewController.h", <MASPreferences/MASPreferencesViewController.h> |
| `MacDown/Code/Preferences/MPHtmlPreferencesViewController.m` | 155 | Settings / Preferences migration | "MPHtmlPreferencesViewController.h", "MPUtilities.h", "MPPreferences.h" |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.h` | 15 | Settings / Preferences migration | "MPPreferencesViewController.h", <MASPreferences/MASPreferencesViewController.h> |
| `MacDown/Code/Preferences/MPMarkdownPreferencesViewController.m` | 31 | Settings / Preferences migration | "MPMarkdownPreferencesViewController.h" |
| `MacDown/Code/Preferences/MPPreferences.h` | 88 | Settings / Preferences migration | <PAPreferences/PAPreferences.h> |
| `MacDown/Code/Preferences/MPPreferences.m` | 288 | Settings / Preferences migration | "MPPreferences.h", "NSUserDefaults+Suite.h", "MPGlobals.h" |
| `MacDown/Code/Preferences/MPPreferencesViewController.h` | 22 | Settings / Preferences migration | <Cocoa/Cocoa.h> |
| `MacDown/Code/Preferences/MPPreferencesViewController.m` | 31 | Settings / Preferences migration | "MPPreferencesViewController.h", "MPPreferences.h" |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.h` | 15 | Settings / Preferences migration | "MPPreferencesViewController.h", <MASPreferences/MASPreferencesViewController.h> |
| `MacDown/Code/Preferences/MPTerminalPreferencesViewController.m` | 209 | Settings / Preferences migration | "MPGlobals.h", "MPHomebrewSubprocessController.h", "MPPreferences.h", "MPTerminalPreferencesViewController.h", "MPUtilities.h" |
| `MacDown/Code/Utility/MPAutosaving.h` | 15 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Utility/MPGlobals.h` | 29 | App/Features | "version.h" |
| `MacDown/Code/Utility/MPHomebrewSubprocessController.h` | 20 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Utility/MPHomebrewSubprocessController.m` | 93 | App/Features | "MPHomebrewSubprocessController.h" |
| `MacDown/Code/Utility/MPMathJaxListener.h` | 16 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Utility/MPMathJaxListener.m` | 56 | App/Features | "MPMathJaxListener.h" |
| `MacDown/Code/Utility/MPPlugIn.h` | 21 | App/Features | <Foundation/Foundation.h>, "MPDOcument.h" |
| `MacDown/Code/Utility/MPPlugIn.m` | 66 | App/Features | "MPPlugIn.h" |
| `MacDown/Code/Utility/MPUtilities.h` | 46 | App/Features | <Foundation/Foundation.h> |
| `MacDown/Code/Utility/MPUtilities.m` | 214 | App/Features | "MPUtilities.h", "NSString+Lookup.h", <JavaScriptCore/JavaScriptCore.h> |
| `MacDown/Code/View/MPDocumentSplitView.h` | 19 | App/Features | <Cocoa/Cocoa.h> |
| `MacDown/Code/View/MPDocumentSplitView.m` | 85 | App/Features | "MPDocumentSplitView.h" |
| `MacDown/Code/View/MPEditorView.h` | 16 | App/Features | <Cocoa/Cocoa.h> |
| `MacDown/Code/View/MPEditorView.m` | 220 | App/Features | "MPEditorView.h" |
| `MacDown/Code/main.m` | 14 | App/Features | <Cocoa/Cocoa.h> |
| `MacDownTests/MPAssetTests.m` | 121 | Tests | <XCTest/XCTest.h>, "MPAsset.h" |
| `MacDownTests/MPColorTests.m` | 38 | Tests | <XCTest/XCTest.h>, "NSColor+HTML.h" |
| `MacDownTests/MPHTMLTabularizeTests.m` | 57 | Tests | <XCTest/XCTest.h>, "NSObject+HTMLTabularize.h" |
| `MacDownTests/MPPreferencesTests.m` | 48 | Tests | <XCTest/XCTest.h>, "MPPreferences.h" |
| `MacDownTests/MPStringLookupTests.m` | 187 | Tests | <XCTest/XCTest.h>, "NSString+Lookup.h" |
| `MacDownTests/MPUtilityTests.m` | 33 | Tests | <XCTest/XCTest.h>, "MPUtilities.h" |
| `macdown-cmd/MPArgumentProcessor.h` | 22 | CLI | <Foundation/Foundation.h> |
| `macdown-cmd/MPArgumentProcessor.m` | 96 | CLI | "MPArgumentProcessor.h", <GBCli/GBCli.h>, "MPGlobals.h" |
| `macdown-cmd/main.m` | 121 | CLI | <sys/time.h>, <AppKit/AppKit.h>, <GBCli/GBCli.h>, "NSUserDefaults+Suite.h", "MPGlobals.h", "MPArgumentProcessor.h" |

## Vendored third-party ownership

Do not count vendored code as first-party Swift migration work.

| Directory | Languages | Responsibility |
| --- | --- | --- |
| Dependency/peg-markdown-highlight | Objective-C, C, grammar/build tools | Editor highlighter and generated parser |
| Dependency/YAML-framework | Objective-C | YAMLSerialization wrapper; license in LICENSE/yaml.framework.txt |
| Dependency/prism | JavaScript, CSS, markup | Syntax highlighting submodule |
| Dependency/version | Makefile, Xcode configuration | Generated version metadata |
| MacDown/Resources/Extensions | JavaScript, CSS | Vendored Mermaid/Graphviz plus first-party initialization adapters |
| MacDown/Resources/MathJax | JavaScript | MathJax resources/configuration |
| MacDown/Resources/Styles and Themes | CSS, legacy style format | Mixed-author licensed styles; preserve notices |
| Pods (not present) | Objective-C, C, frameworks | Versions are recorded in Podfile.lock |

## Other first-party source

Resource initialization JavaScript, Handlebars templates, AppleScript dictionary, Interface Builder XML, localizations, shell/Python tooling and CSS are also part of parity. Swift-only application logic does not justify removing preview resources, localization assets or independently maintained third-party code.

## Modern parser ownership boundary

`Packages/SnowfolioCore/Sources/MarkdownCore` contains first-party Swift orchestration and
owned AST values. Its pinned SPM dependency `swiftlang/swift-cmark` 0.9.0 provides the
maintained third-party C CommonMark/GFM engine. Native pointers stay actor-confined;
no vendored parser C is counted toward first-party Swift migration. The dependency's
COPYING notice ships as `App/Resources/Licenses/swift-cmark.txt`.

## Progressive retirement ledger

The table above is the original migration baseline, not a claim that all listed code
must remain. Each migration increment also checks for dead first-party implementation.
Delete verified replacements and unused code, update references, preserve required
resources/licenses, and keep the prior implementation in Git history.

| Date | Removed | Evidence / remaining gate |
| --- | --- | --- |
| 2026-11-06 | `NSString.matchesForPattern:` declaration and implementation; `MPStringIsNewline` declaration and implementation (17 lines total) | Repository-wide symbol search found only their own declarations/definitions; no production, test, resource or build caller. No dynamic selector lookup was found. Other methods in these files still have callers and remain. |

This is a small dead-code cleanup, not retirement of the old renderer or editor. The
legacy project cannot currently provide a full runtime baseline because its old
dependencies are absent (see `validation/legacy-baseline.json`). Existing source syntax
colors do not yet replace custom theme/font or legacy dialect behavior. Delete those
subsystems and their build references only after their remaining parity gates pass.

## Updated code-highlighting ownership boundary

`Packages/SnowfolioCore/Sources/CodeHighlightCore` contains first-party Swift orchestration
and a pinned Prism 1.30.0 third-party resource bundle. The bundle includes all upstream
language components, the eight built-in themes, MIT notice, catalog and provenance.
`Tools/vendor-prism.py` is development tooling; Node is not bundled or needed to run the
app. This replaces the modern app's need for legacy Prism loaders and page scripts.
`Dependency/prism` and the old MPRenderer remain only for the not-yet-retired legacy target;
remove their obsolete build/resource references once remaining renderer parity passes.

## Ordered metadata ownership boundary

The modern parser uses the maintained CYaml event backend bundled with SPM Yams 6.2.2.
`MarkdownFrontMatter.swift` owns the bounded Swift composer/value graph and responsive
property HTML; `MarkdownNavigation.swift` owns heading IDs and TOC decoration. Original
YAML-framework/HTMLTabularize and Hoedown TOC code are no longer needed by the modern app,
but their old-target consumers (including presumed filename logic) remain to migrate.
Yams and libyaml notices are retained in `App/Resources/Licenses`.

## Offline equation ownership boundary

`MathCore` contains first-party Swift orchestration and KaTeX 0.19.1 third-party
JavaScript/CSS/fonts, pinned by npm SHA-512 and per-file SHA-256 provenance.
`MarkdownCore/MarkdownMath.swift` integrates equation delimiters into cmark using Swift
callbacks; it is not another Markdown parser. TeX rendering stays in a separate confined
JavaScriptCore context. App/script/export font licenses remain bundled, and exported
font stylesheets carry the original MIT notice. `Tools/vendor-katex.py` is development
asset-reproduction tooling; Node and a network connection are not app requirements.

The native app no longer needs the old MathJax web loader/listener for its implemented
equations, but the remaining MathJax-specific syntax, macro/numbering compatibility and
old-target consumers prevent complete subsystem deletion yet. Keep the retirement gate
in `MODERNIZATION_PLAN.md`; this increment does not claim full renderer parity.
