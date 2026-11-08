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


## Offline diagram ownership boundary

`DiagramCore` owns the Swift queue, deadlines, cancellation, resource loading, SVG
validation and preview/export variants. Only pinned third-party Mermaid 12.3.0 and
Viz.js 3.31.0 execute in a confined, nonpersistent WebKit client world. Viz bundles
Graphviz 16.1.0 as embedded WebAssembly; no native Intel executable, Node runtime,
network fetch or document script is needed. The fixed worker page has no native bridge
and rejects navigation/resource requests outside its app-owned initialization/data fonts.
The preview receives validated SVG, with page JavaScript disabled.

`Tools/vendor-diagrams.py` verifies npm integrity, source archives, distribution notices
and per-file checksums. App and resource bundles retain Mermaid/Viz MIT notices,
Graphviz EPL 2.0 plus its rbtree notice, Expat MIT and Emscripten MIT/NCSA notices, with
corresponding source/build URLs. Native build validation verifies the actual packaged
files and notices. These maintained third-party engines are ownership exceptions;
first-party orchestration stays Swift. The small trusted DOM/CSS adapters are WebKit
boundary code, not document-provided scripts.

The native app no longer consumes the original Mermaid/Viz initialization loaders.
Their legacy-target resource/build references remain coupled to the original renderer,
which still supplies unmigrated templates, custom CSS, extensions and other behavior.
No additional legacy subsystem is deleted at this partial gate; retire it after the
remaining renderer and original-target consumers have been replaced and verified.


## Inline dialect and parser configuration ownership

`MarkdownCore/MarkdownInlineExtensions.swift` is first-party Swift, using native cmark
callbacks for optional highlight and superscript nodes. `EditorCore` owns the restored
highlight transaction; native UI/source styling and portable document CSS consume that
owned representation. There is no regex-based document-wide Markdown rewrite.

The parser now builds through `Packages/MarkdownEngine`, containing 76 original files
from maintained swift-cmark 0.9.0 and its COPYING notice, plus a first-party Swift manifest
and provenance. Exactly two C preprocessor directives expose a build opt-out for the
unrequested attributed-string inline grammar that swallowed text during malformed-input
tests. The manifest defines `CMARK_DISABLE_ATTRIBUTES`. This narrowly scoped third-party
configuration patch is an explicit exception to the Swift-only first-party application
rule; no original MacDown C/Objective-C is reused in modern app logic. All other native
source matches the pinned release. Vendoring/verification tools preserve original and
packaged hashes and license bytes; generated build artifacts are excluded.

The old highlighter/renderer/Format-menu methods still have original-target callers.
They remain coupled to unmigrated underline/quote/dialect/custom-theme/template behavior,
so this increment does not delete their files or claim the zero-legacy-code gate achieved.
A new standards ledger records the 11 inherited CommonMark differences found by the
broader corpus audit. Retire these subsystems only after the remaining replacements
and desktop acceptance gates pass.


## CommonMark backport update

The preceding two-directive configuration record describes commit `62344f7`. The current
native parser additionally contains three upstream CommonMark/cmark 0.31.2 backports in
`src/html.c`, `src/houdini_html_u.c` and `src/utf8.c`. The first preserves native nested
strong nodes in HTML; the others implement standard reference digit bounds and Unicode
punctuation/symbol flanking. These remain explicit third-party C code, sourced from a
checksum-pinned maintained release with the complete COPYING notice. All remaining native
source matches swift-cmark 0.9.0. `Patches.json` and provenance describe the exact changes;
build verification reverses them to verify original hashes.

`Packages/MarkdownEngine/Audit/ParserAudit.swift` is a first-party development tool. It
reads stdin and prints the core engine HTML for corpus checks; it is not the app's future
user-facing CLI and is not linked or bundled into Snowfolio. All first-party application
logic remains Swift. The new corpus pass does not yet authorize deleting the coupled
legacy renderer/editor/custom-template implementation.


## Project cleanup and development audit ownership

The obsolete `.travis.yml` (Xcode 10.1/CocoaPods) and its sole localization-upload
helper `Tools/travis_push_transifex.py` are retired. The verified arm64 GitHub Actions
workflow supplies native builds, package/spec checks and document UI tests. No
localization resources or manual translation import tool are removed. The old Ruby/
CocoaPods and release dependency graph remains until its original-target consumers
are retired; this cleanup does not claim that graph has migrated.

`Tools/PerformanceAudit` is a first-party Swift development executable measuring the
actual MarkdownProcessor pipeline. It is not linked or bundled into Snowfolio and
does not replace the future user-facing CLI. Generated builds remain outside tracked
source. `validation/project-cleanup.json` records all recoverable Trash destinations;
`PERFORMANCE_AUDIT.md` distinguishes core measurements from remaining app-level gates.


## Fenced-code configuration ownership

`MarkdownCore` owns the Swift `fencedCode` option; native Settings/migration/export paths
consume it. The pinned engine adds the local `CMARK_OPT_NO_FENCED_CODE` bit (22) in its
public header and a conditional around the existing fence recognizer in `src/blocks.c`.
This is a configuration exception to the Swift-only application boundary, not an upstream
API or a new first-party parser. Default native behavior remains unchanged. The other
four patched native files retain the attributed-string opt-out and CommonMark backports.
All unpatched source remains byte-identical, and the verifier reverses all six file patches
to check original hashes. Application grammar is not duplicated in a document preprocessor.

`Tools/characterize-fences.py` and `LegacyFences.json` retain exact original-engine output
and explicit known CommonMark differences for development. The tool/original characterizer
are not bundled or app requirements. Legacy renderer/editor/custom-style consumers still
prevent complete old-target retirement.


## Settings window replacement (2026-11-07)

`SettingsCatalog.swift` now supplies all 38 existing preference controls and search
metadata; `SnowfolioSettingsView.swift` supplies the native sidebar/grouped forms;
`SettingsWindowController.swift` owns the single native window and Settings command.
Persisted keys and the shared `AppPreferences` model are unchanged. The superseded
`MarkdownSettingsView.swift` was moved to native Trash after the replacement built
and ran: `/Users/caden/.Trash/MarkdownSettingsView.swift`. This retires a duplicate
modern implementation; original preference code with remaining parity obligations
remains in the audit inventory. See `validation/settings-redesign.json`.


## Underline matcher and generic native extension bridge

`MarkdownCore/MarkdownDelimiterExtensions.swift` is Swift application integration for
the optional underscore dialect. Span-search semantics derive from Hoedown 3.0.7 and
retain its complete original ISC notice in `App/Resources/Licenses/Hoedown-inline.txt`.
`Tools/characterize-underline.py` is a development-only original-engine fixture capture;
its 84 captured choices and 16 documented native differences live in test resources.
It and the original Hoedown executable are not linked into the app.

The maintained parser now also has a generic opt-in pre-token callback in `blocks.c`,
`inlines.c`, `syntax_extension.c` and two extension headers, plus native link-context
propagation for callback-created subtrees. This local API is explicitly not upstream;
there is no underline grammar in C. The same pinned archive still provides all 76
original files and notices. Reversible patches, original/packaged hashes and an isolated
80-file reproduction verify exactly this boundary. Native app builds check the bundled
Hoedown notice against the checked-in original notice.

The legacy renderer/highlighter/formatting files still have original-target callers and
unmigrated quote/intraword/custom-theme/template behavior. They are not duplicate dead
files solely because underline parity is now implemented. Do not delete them until
remaining replacements and desktop acceptance pass. The zero-legacy-code gate remains
open, along with a live source-color repaint observation recorded in the roadmap.


## Quoted text and source presentation ownership

The optional `extensionQuote` replacement extends the existing Swift delimiter matcher
with `.quotation` nodes. It reuses native child parsing and the existing pre-token bridge;
`cmark_inlines_add_special_character` marks quote scanner boundaries without registering
a competing smart-quote delimiter handler. There are no further C patches. Original
Hoedown ISC attribution remains bundled. The quote capture tool and 80-case golden fixture
are development evidence, not shipping parser executables.

`NativeSyntaxHighlighter` owns an attributes-only viewport notification that refreshes
native paragraph surfaces after temporary styles change. It writes no text-storage
attribute values or source bytes and cannot run that notification during marked-text
composition. Full-workspace and actual displayed-source UI checks cover the presentation
boundary separately from parser metadata and fresh offscreen drawings.

The remaining independent intraword preference and custom themes/templates still share
original-target renderer/editor/formatting callers. Underline/quote replacements alone
do not make those coupled files unused; the zero-legacy-code retirement gate stays open.


## Word-formatting policy ownership

`MarkdownEmphasisPolicy` and the existing Swift delimiter matcher now replace the
independent original intraword setting across every enabled emphasis marker family.
The native app preserves both old Boolean choices and an explicit new Standard mode.
There are no new native C changes or runtime Hoedown dependencies. The 276-case original
fixture and its capture tool are development evidence; they do not ship an old parser.

Custom themes/templates and remaining original-target callers still couple the old
renderer/highlighter/formatting subsystem. Those files are not unused solely because
word-formatting parity now passes. Preserve them and all licenses until their remaining
replacements and acceptance checks make progressive Trash retirement safe.


## Editor-theme reader foundation

`EditorCore/EditorTheme.swift` independently reads the original `.style` data grammar.
It retains the full font/color/trait vocabulary and reports bounded import diagnostics.
`Tools/characterize-editor-themes.py` and the 21-case JSON fixture are development-only
original-engine evidence, including all 15 original bundled themes. Neither the capture
C wrapper nor the original PEG parser is added to a shipping target. The retained MIT
notice covers the format compatibility work.

The reader is not yet wired into native syntax presentation or settings. Existing
highlighter/theme, custom CSS and template consumers therefore remain needed. Do not
retire those coupled original files based on parser/model parity alone.


## Native theme typography foundation

`NativeEditorTheme` compiles the Swift theme model into native font/color attributes.
`NativeSyntaxHighlighter` supplies copied `NSTextParagraph` presentation through the
public content-storage delegate, while its default mode still uses temporary colors.
`MarkdownSyntaxToken` supplies bounded AST-derived semantic scopes; only matched native
inline-code delimiter ranges are expanded for presentation. The app's native document
storage receives no theme attributes. Native tests exercise real layout, typing, undo,
programmatic composition, source bytes and theme removal.

There is still no user-facing theme catalog/import path. Entity/reference/note scopes,
editor global accessories, complete acceptance and custom CSS/templates remain coupled
to original-target consumers. Do not retire the original theme/highlighter subsystem
yet. The reader and native typography layer alone do not prove complete feature parity.


## Custom stylesheet ownership boundary

`RenderingCore` owns Swift discovery/import, access grants, bounded file reads,
resource resolution and immutable stylesheet snapshots. A confined JavaScriptCore
instance calls pinned [CSSTree 3.2.1](https://github.com/csstree/csstree) parser/walker
modules; authored CSS is passed as data and receives no DOM/native/network bindings.
Only identified resource-token ranges change, with CSS source and copied resources
retained separately. This is a CSS parser, not another Markdown parser.

The parser bundle contains only upstream parser/walker/identifier modules.
Its MIT notice ships in both resource and app license bundles. The reproduction
script verifies the locked npm build and rejects unexpected bundled dependencies;
MDN lexer data, source-map code, esbuild and Node do not ship in the app. Source and
packaged checksums/notices are checked without network or Node access.

The document-directory reader retains its existing allowlist. Additional CSS font/image
fallbacks use a separate internal policy only while resolving an explicitly chosen
style folder. Frozen preview/export CSS contains embedded local assets; relative CSS
imports cannot use a new unrestricted document resource root.

The original renderer, Handlebars and their original-target build/resources remain
coupled to template and remaining asset-option behavior. This checkpoint does not
retire those dependencies or claim full CSS/template/visual/release acceptance.


## Swift HTML template ownership boundary

`RenderingCore` now owns the bounded Swift context program for the observed Default
Handlebars grammar, a byte-preserved bundled template/provenance, and shared typed
preview/export parts. `ExportCore` uses the program for fresh standalone documents.
`SnowfolioUI` captures migrated template names in immutable export snapshots and
provides explicit unavailable-name recovery. No Handlebars runtime or page scripts
enter the native app. The Default template and MacDown MIT notice are verified in
source and packaged resources; the retained original is a characterization baseline.

Call-site review of `MPRenderer.render`, `HTMLForExportWithStyles:highlighting:` and
`MPDocument.exportHtml:` corrects the previously inferred linked-export gate:
full links are internal preview assembly, while the HTML export accessory offers
independent include/omit styles and highlighting, embedding included resources.
User-provided asset license sidecars, remaining renderer parity and original-target
callers remain open. The old renderer/asset/dependency graph is still coupled and is
not retired by this template checkpoint. See `HTML_TEMPLATES.md` and its evidence ledger.


## Swift code-block presentation ownership boundary

`MarkdownCore` now reads code metadata from the native AST and owns the Swift label,
numbering and bounded generated-span transformation. Original AST/source-syntax facts
stay unchanged. `CodeHighlightCore` adds human names from the same pinned Prism archive;
`LanguageTitles.json` is included in resource provenance/build verification and the
existing MIT notice. The other pinned resources are byte-identical. `RenderingCore`
owns shared code CSS and the existing isolated preview bridge's unchanged-code selection
mapping. `SnowfolioUI` preserves htmlLineNumbers/htmlCodeBlockAccessory keys, original
0/1/2 choices, and a no-style export default derived from the frozen presentation.

The original Prism DOM plugins and custom-information stylesheet are not added to the
native app; numbers/labels are generated before preview/export. The original target
still owns unmigrated renderer/preferences/integration behavior, including the default
asset directory for unsaved documents, so this checkpoint does not retire its coupled
renderer/asset/dependency graph. See `CODE_BLOCKS.md` and its validation ledger.


## Swift unsaved asset-folder ownership boundary

`SnowfolioUI.DocumentAssetFolder` now owns the original htmlDefaultDirectoryUrl migration
as an inactive chooser suggestion, read-only bookmark persistence/recovery and balanced
access lifetime. Preview requests and export snapshots retain their own access. Saved
files keep their containing-directory rule. `ExportCore` reports a typed recoverable
error only when a missing remembered grant is needed for relative Markdown images. `LocalResourceHandler` uses distinct
per-navigation origins and translates only the current one into the existing bounded
resource reader; parser/source logic is unchanged. Native editor undo notifications
respect a newer model-owned source revision. See `DOCUMENT_ASSETS.md` and
`validation/unsaved-asset-folder.json`. Other original consumers and preference/parity
gates still prevent coupled MPDocument/renderer/preferences target retirement.
