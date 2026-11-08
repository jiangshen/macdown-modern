# Snowfolio modernization plan

Status: **Active and incomplete. M1 is complete; M2 document acceptance, M3 parser/preview parity and M4 native experience continue. M5 productivity/integrations and M6 app performance/release acceptance remain incomplete.**

Current worktree checkpoint: grant-backed assets for unsaved documents, fresh preview
resource origins and a stale native buffer guard for model-owned undo. Local evidence
verifies **334 package tests / 71 suites**, **ten Address Sanitizer tests / two suites**,
eight arm64 test executables and an arm64 native app build. The actual native workspace
passes five missing/loaded image transitions and retains source, selection, views and
undo. Two new app UI methods cover folder chooser/cancel/history and an actual untitled
save followed by image export from the saved file's folder; hosted execution passed
all 17 native UI methods, 334 package tests and 652 CommonMark examples.
See [unsaved-asset-folder.json](validation/unsaved-asset-folder.json) and
[DOCUMENT_ASSETS.md](DOCUMENT_ASSETS.md).

The preceding exact code-presentation checkpoint `1057098` passed 329 package tests,
652 CommonMark examples and 15 native app UI tests. Its contrast, visual-capture limits
and diagnostics remain in [code-block-presentation.json](validation/code-block-presentation.json).
Template/CSS evidence remains in [html-template-exports.json](validation/html-template-exports.json)
and [custom-reading-styles.json](validation/custom-reading-styles.json).

The existing notebook design remains the default. None, six original styles, edited
MacDown CSS, local CSS and imported copies remain selectable. CSS/image/font imports
freeze into preview and fresh HTML/PDF/print snapshots; reload preserves the last valid
appearance on failure. The bundled Default template is preserved with Swift context
assembly and explicit unavailable-name recovery. Source call-site review confirms that
fully linked assets served the original preview internally; the HTML export UI exposed
independent include/omit choices for document styles and code highlighting, with included
resources embedded. Separate user-provided license sidecars, remaining renderer parity
and safe coupled legacy retirement stay open. The HTML accessory now starts without document styles for None; its new native UI
case passes in the final hosted run. Unsaved-document default asset folders now have
an explicit grant-backed migration workflow (`htmlDefaultDirectoryUrl`), with hosted chooser/Save As acceptance passed. The [original characterization ledger](validation/css-template-characterization.json)
preserves source evidence and the call-site correction.

Fresh user-desktop visual acceptance, captured WebKit glyph painting, real IME/VoiceOver,
document reliability and full app performance remain required. Prior bundled-style
hosted evidence is retained in [reading-styles.json](validation/reading-styles.json).

Input-normalization source projection previously passed local/hosted acceptance;
[its ledger](validation/input-source-projection.json) preserves exact evidence.
Direct desktop, real IME/VoiceOver, remaining parity, complete native performance,
release readiness and safe coupled legacy retirement remain required. The chronological
evidence below preserves prior checkpoints; it does not close these gates.

## Scope and source of truth

The checked-out Snowfolio repository (formerly `macdown-modern`) defines legacy behavior.
Preserve its source and resources until replacements pass characterization and integration
tests. All new application-owned code uses Swift 6 language mode and the installed Swift
6.4 toolchain. Third-party C/JavaScript may remain behind explicit boundaries when needed.
Native AppKit selectors and Objective-C interoperability are permitted in Swift; this does
not mean keeping first-party Objective-C implementations.

## Independent product direction — added 2026-11-06

The user explicitly wants to fundamentally move away from the original MacDown and
build an independent native writing product. This is an added requirement of the active
goal, not just a cosmetic rename. The existing repository defines feature and file
compatibility requirements and attribution obligations; it does not dictate the final
architecture, information layout, workflows, visual identity or product positioning.

- Develop Snowfolio as an original, coherent native writing product. The user selected
  **Snowfolio** on 2026-11-06, replacing the earlier MacDown working name.
- Keep the liked current document/callout styling as a starting point. Evolve the
  glacial-blue layered icon and native Apple/Liquid Glass chrome into a consistent
  identity; a new name does not authorize discarding the current liked design.
- Design around local plain-text Markdown, clear reading/writing, responsive native
  interaction and useful document/workspace tools. Existing MacDown UI and code
  organization are not constraints on the new implementation.
- Preserve essential capabilities, data, user choices and compatibility already
  requested. Do not infer permission to silently remove writing features from the
  independent-product direction. Modern replacements and new workflows may differ
  structurally once their behavior is verified.
- Continue removing original first-party implementation, duplicate targets and obsolete
  dependencies progressively, ending with zero legacy implementation. Preserve legally
  required attribution and still-needed licensed resources; historical source belongs
  in Git rather than a parallel shipping app.
- Review future milestone work against this independent-product direction as well as
  technical parity. Completion requires an original coherent product, not only a Swift
  translation of the old app.

Selected identity: **Snowfolio**. The current native app, project/package/module names,
build tools, repository and active documentation use this name. Preserve the liked
glacial-blue layered app/document icons and the Markdown M↓ format mark. Preserve
original MacDown attribution, license files, historical validation records and legacy
code until its replacements reach parity. The internal macOS bundle and tabbing IDs
remain stable compatibility keys for app data, native document history and restoration;
they are not displayed as product branding. No default-app change or public release is
implied by the rename. See `docs/BRANDING.md`.

## Baseline audit (2026-11-06)

- Xcode 27.2, build 27B52; Swift 6.4.2; native arm64 host.
- System developer selection points to Command Line Tools. Set `DEVELOPER_DIR` per command
  to the installed Xcode; do not silently change machine-wide settings.
- No applicable `AGENTS.md` found in the repository or its ancestor directories.
- Initial working tree was clean on `master` at `fa8af0e` (fresh README). Earlier upstream
  development notes were inspected before the fork's README-only fast-forward; build
  requirements are verified from the checked-out workspace itself.
- See `SOURCE_INVENTORY.md` for exact counts,
  file ownership, imports and migration destinations.
- Application shell: Objective-C `NSApplication`, `MPMainController`, Interface Builder
  menus/windows/preferences. `MPDocument` is an `NSDocument` with about 2,000 lines spanning
  editing, file I/O, preview, export, preferences, counting and scroll synchronization.
- Editing: `MPEditorView`/`NSTextView`, TextKit 1 highlighter and first-party autocomplete
  category. UTF-16 offsets, selection mapping, smart Home, list/blockquote continuation,
  paired delimiters, wrapping, indentation and heading commands require characterization.
- Documents: UTF-8 read/write, autosave-in-place, native print handling, suggested names,
  multiwindow document controllers. Optional ensure-final-newline mutates the document
  during save. New save behavior must preserve bytes unless the user explicitly edits or
  enables a transformation. Mixed line endings and BOMs require coverage.
- Rendering: patched Hoedown C -> HTML, Handlebars templates, local CSS and Prism assets,
  legacy WebKit `WebView`/DOM APIs. MathJax, Mermaid, Graphviz, front matter, TOC and
  nonstandard Markdown options are existing features, not optional future conveniences.
- Concurrency: `MPRenderer.parseAndRenderWithMaxDelay` cancels queued operations but does
  not check cancellation inside its loading loop. Its `while (loading || elapsed-test)`
  condition does not provide the documented bounded wait, and it repeatedly dispatches
  synchronously to the main queue without yielding. Replace with cancellation-aware,
  revision-checked background parsing; no busy wait.
- Preferences: PAPreferences dynamic properties, KVO/defaults notifications, five panes.
  Preserve historical key spellings, defaults, fonts and user-defined theme/style paths.
- Integration: bundled CLI accepts files and piped stdin through shared defaults;
  `x-macdown://open` exists, but line/column navigation is explicitly unimplemented.
  AppleScript dictionary exposes document text and rendered HTML. Plugin bundles load
  executable code through `NSBundle` and a small dynamically queried interface.
- Security: legacy Info.plist broadly allows arbitrary network loads; preview has private
  WebKit hooks; rendering can load linked resources. The replacement needs a separate
  isolated WKWebView content world, explicit resource policy and no document-to-native
  arbitrary script bridge. Plugins require an explicit compatibility/security decision.
- Tests: seven Objective-C XCTest implementation files cover assets, HTML tables, colors,
  string lookup, preferences and JavaScript extraction. No existing editor integration,
  UI, performance, conflict or IME suite was found.
- Build: CocoaPods workspace, patched pod-spec source, generated PEG C parser, Prism
  submodule and resource copying/style/version shell phases. CocoaPods is not installed
  and `Pods/` is absent. Development documentation and release tooling are legacy.
- CI: Travis configuration targets Xcode 10.1; GitHub contains Dependabot configuration,
  not a modern build/test workflow. Release script signs a ZIP using obsolete DSA/SHA-1.
- Licenses: MacDown MIT, with individual bundled-library and resource licenses. Preserve
  notices and audit dependencies individually; MIT on the application is not a blanket
  license for every included asset.

### Verified baseline build

The unmodified workspace was built with the existing `MacDown` scheme, Debug,
`platform=macOS,arch=arm64`, unsigned, with separate DerivedData. **Exit 65 before
compilation**: missing CocoaPods `.xcconfig` files for app and CLI, and deployment target
10.8 outside this SDK's supported 12.0–27.2 range. `docs/validation/legacy-baseline.json`
contains the captured diagnostics. Legacy tests therefore have **not** passed on this
toolchain. This is an initial repository limitation, not proof of a source incompatibility.

## Feature inventory and parity gates

Each unchecked item remains a requirement; presence in the old source is not runtime
verification. No essential feature is authorized for silent removal.

| Category | Legacy capability / acceptance gate | Status |
| --- | --- | --- |
| Essential | Open/new/save/save-as, UTF-8 contents, dirty state, native autosave/Versions, multiple windows | Native host and byte-preserving I/O implemented; final autosave/Versions/conflict desktop gates pending |
| Essential | Undo/redo, selection, Unicode, Chinese/Japanese marked text, spellchecking, native find | Native paths and simulated composition covered; real IME/VoiceOver/desktop acceptance pending |
| Essential | Source, preview and split modes; resize, swap sides, linked scrolling and zoom | Native modes/resize, linked scrolling, pane order and per-document zoom implemented; final desktop acceptance pending |
| Essential | Formatting, headings 1–6/paragraph, lists, indent/unindent, links/images, paired delimiters | Common source commands/input integrated; remaining legacy dialect and advanced editing gates pending |
| Essential | Live/manual HTML preview, HTML copy/export, styled export, PDF and native printing | Core paths verified; advanced renderer/export fidelity pending |
| Essential | Custom editor `.style` themes, CSS, templates, syntax themes, typography and layout preferences | Native source `.style` catalog/import, 15 bundled source themes, notebook typography all eight Prism code themes, code-block line numbers and language/custom labels implemented; eight reading presentations (Notebook, None and six original sheets) implemented for preview/export; custom CSS/folder import, immutable local assets and reload implemented; Swift Default template/context and unavailable-name recovery implemented; hosted export-panel/recovery acceptance passed; direct desktop theme/export acceptance, user asset license sidecars and remaining layout preferences pending |
| Essential | MathJax-compatible math, Mermaid, Graphviz, task lists, front matter and TOC | Task lists, YAML properties, heading links/TOC, offline equations and diagrams implemented; remaining MathJax compatibility pending |
| Essential | Existing Markdown extension toggles: tables/fences/autolinks/strike/underline/superscript/highlight/footnotes/quote/smart punctuation/intraword emphasis | GFM/footnotes/smart punctuation, underline/highlight/superscript/quoted-text, fenced-code and independent intraword-emphasis preferences implemented |
| Essential | Word/character statistics, shortcut/menu behavior, full screen, window restoration | Pending |
| Modernize | CLI paths/stdin, Open Recent, Finder document associations and URL scheme | Pending |
| Modernize | AppleScript document text/HTML interface; evaluate native App Intents alongside it | Pending |
| Modernize | Plugin discovery/run compatibility, updater stable/prerelease choices and preferences migration | Pending |
| Add | Standards-verified CommonMark/GFM, AST outline, workspace/search/Quick Open/command palette | Planned after parity |
| Add | Optional focus/typewriter modes, line numbers, TOC generation, alert syntax, table assistance | Planned after parity |
| Add | Quick Look/Spotlight/Services/Shortcuts, share sheet, accessible keyboard customization | Planned after parity |
| Later | Explicit opt-in on-device AI with undo, availability handling and no silent transmission | Deferred |

Retirable implementation details: private `WebCache` APIs, direct DOM access, CocoaPods,
PAPreferences, DSA updater signing, legacy `/usr/local`-only CLI assumptions, Python 2-era
release glue and repeated unbounded parser polling. Retire their implementations only
after supported behavior has a verified replacement. The personalized `treat()` easter
egg is a candidate for retirement (not essential writing functionality); record the
decision when migrating application lifecycle. Existing bundled styles and help remain.

## Architecture decisions

### Document architecture evaluation

The installed SDK contains the macOS 27 `Document`, `ReadableDocument`,
`WritableDocument`, `DocumentReader`, `DocumentWriter` and FileWrapper adapter APIs;
availability was checked in SwiftUI's installed `.swiftinterface`. Apple's migration
guide confirms the new reader/writer model with coordinated background I/O. Evaluate
these APIs in the document-host integration spike with autosave, undo, native tabs,
external-edit conflicts, Versions and AppleScript tests before committing the app host.

Preferred direction: SwiftUI `DocumentGroup` with the new macOS 27 document protocol,
an observable reference document owning text, and immutable `Sendable` snapshots for
background work. Fallback: a Swift `NSDocument` owning file coordination/undo and hosting
SwiftUI windows if the new API cannot preserve required behavior. Do not invent a
parallel custom autosave/file watcher stack. The core codec is UI independent so either
host uses exactly the same byte-preserving document representation.

### Layers and boundaries

- `App/`: application lifecycle, commands, document windows and native Settings.
- `Features/Editor/`: AppKit `NSTextView` + TextKit 2 via a SwiftUI representable. UI,
  selection and undo are main-actor-owned. Never replace marked text during composition.
- `Features/Preview/`: WKWebView (justified by existing HTML/CSS/math/diagram fidelity),
  restrictive navigation/resource policy and a versioned DOM patch protocol. Preserve
  position and focus; full initial navigation is acceptable, full per-key reload is not.
- `Packages/SnowfolioCore`: independent `DocumentCore` and `EditorCore` initially;
  add `MarkdownCore` and `RenderingCore` when real consumers and tests need them.
- `DocumentCore`: bytes/encoding snapshots and eventually host-facing document values.
- `EditorCore`: UTF-16-aware edit operations and legacy behavior characterization,
  independent of SwiftUI/AppKit; actual view applies one edit through native undo.
- `MarkdownCore`: parser adapter/AST, source locations, outline, optional extensions.
  Distinguish persistent AST storage from genuine incremental reparsing: do not claim
  incremental parsing merely because the tree uses copy-on-write.
- `RenderingCore`: escaped HTML and local resource assembly; no arbitrary JS execution.
- Parsing receives immutable text+revision, cancels stale work, and only publishes the
  matching revision. Rendering debounce must never block typing. Parsing services own
  their mutable state through actors; pure value transformations are `Sendable`.

Avoid framework-wide dependency injection and protocol hierarchies. Introduce modules
only for testability and clear ownership. Keep plain Markdown files as the storage format.

## Dependency strategy

| Current dependency | Strategy and gate |
| --- | --- |
| Patched Hoedown 3.0.7 (C) | Evaluate `swiftlang/swift-markdown` via SPM for AST/CommonMark/GFM. It wraps maintained cmark-gfm C: document this exception. Characterize Hoedown extension flags first; footnotes/math/front matter/underline/quote are not assumed equivalent. |
| PEG Markdown Highlight (Objective-C/C) | Replace first-party integration with Swift TextKit 2 attributed styling driven by parser source ranges; benchmark before removal. Vendored generated/parser code is third-party, not first-party migration progress. |
| Handlebars 1.4.5 + M13OrderedDictionary | Replace asset/export assembly with typed Swift rendering and explicit escaping. Preserve custom-template compatibility through an adapter until documented migration is available. |
| LibYAML + YAML.framework | Evaluate a maintained Swift-facing YAML package (such as Yams) for ordered front matter. Preserve literal scalar display and table ordering. Do not implement YAML with regular expressions. |
| PAPreferences | Native UserDefaults with typed access/Observation and versioned, idempotent migration; never overwrite existing user choices on startup. |
| MASPreferences | Native SwiftUI Settings with the same choices and migration tests. |
| JJPluralForm | String Catalog pluralization/localization; retain translations and audit all localized assets. |
| Sparkle 1.18.1 | Current maintained Sparkle 2 via SPM; EdDSA and user-owned feed/signing configuration. Never ship the original project's production feed or pretend signing keys exist. |
| GBCli | Small Swift CLI with explicit files/stdin semantics; preserve exit codes/help/version, launch routing and deduplication. Evaluate swift-argument-parser only if complexity warrants it. |
| Prism submodule (JS/CSS) | Preserve initially as vendored local syntax resources; pin revisions and licenses. JavaScript in a constrained preview is an explicit third-party exception. |
| MathJax/Mermaid/Graphviz (JS) | Preserve fidelity, bundle/pin maintained releases, default to local resources and document any license/version changes. No automatic network dependency for writing. |

No new remote dependency is required by the initial document/editor core package. Pin
selected third-party revisions with Package.resolved when their integration begins.

## Roadmap and measurable acceptance criteria

### M1 — Audit and verified Swift foundations (current)

1. Save this plan, complete first-party ownership inventory and baseline diagnostics.
2. Add a dependency-free Swift 6.4/macOS 27 package in Swift 6 language mode.
3. Characterize legacy newline/whitespace lookup and add byte-preserving document codec
   coverage for UTF-8/BOM, UTF-16/BOM, mixed newlines, Unicode and invalid encodings.
4. Add safe UTF-16 edit primitives with selection/undo round-trip tests.
5. Build and test for arm64; inspect the actual test executable architecture. This does
   not establish a complete application build, UI parity or measured runtime performance.
6. Add a CI workflow and reproducible local validation entry point for these foundations.

### M2 — Document host and editor vertical slice

- Evaluate new Document APIs with compiled integration tests; choose host using the
  autosave/undo/Versions/conflict/AppleScript gates above.
- Create a modern Xcode target alongside legacy source. Wire DocumentCore/EditorCore
  into actual open/edit/save flows, TextKit 2, undo and marked-text-safe bindings.
- Open/save UTF fixtures without byte changes, reopen after external changes safely,
  verify native tabs/multiple windows and cancellation of a close-with-unsaved-edits.
- Migrate preferences without touching live user defaults during tests.
- Gate: native arm64 application builds, launches and passes open/edit/save UI tests.

### M3 — Parser/preview/export parity and complete Swift migration

- Integrate maintained AST parser and local WKWebView; characterize every extension,
  template/style, math/diagram and syntax resource with legacy fixtures.
- Port all formatting commands with selection/undo parity, synchronized scrolling,
  printing, HTML/PDF export, CLI, URL scheme and practical plugin compatibility.
- Remove each first-party `.m`/`.h` only after corresponding consumers/tests migrate.
- Gate: essential checklist complete, old tests ported, no first-party Objective-C
  compile sources in modern targets, no CocoaPods dependency in modern builds.

#### Offline equations — implemented increment (2026-11-06)

The current native app uses pinned **KaTeX 0.19.1** in an actor-confined JavaScriptCore
context. First-party orchestration and parser extension code are Swift; the maintained
third-party engine is an explicit JavaScript exception. Expressions enter as values,
with no DOM, file/network/native bindings, trusted TeX commands disabled, bounded macro
expansion/size/input/output and a bounded cache. Macro definitions are isolated between
expressions. Unsupported/malformed or oversized expressions render escaped source and
a preview notice, without dropping the source or failing the whole document.

Supported syntax: `math` fenced blocks; same-line `$$…$$`; display `$$` delimiters on
separate lines; display `\[…\]` and the original doubled `\\[…\\]` forms on separate
lines; the original `\\(…\\)` inline syntax; and optional same-line `$…$`. Native cmark
extension hooks protect TeX punctuation before Markdown inline processing and keep the
single native parse/AST/source-position model. Stand-alone block delimiters are matched
against future candidates before opening, preventing an unmatched opener from swallowing
the rest of the document. Native parser code/URL/image/quote/list scopes remain in charge;
UTF-8 ranges and source editor styling are preserved. Delimiter indexing avoids rescanning
long unmatched-dollar paragraphs quadratically.

**Render equations** and **Use single dollar signs for inline equations** migrate the
historical `htmlMathJax` / `htmlMathJaxInlineDollar` keys, both off by default. These options
are shared by live/manual preview and fresh HTML/PDF/print export snapshots. KaTeX generates
HTML plus semantic MathML; page JavaScript remains disabled. All 20 original WOFF2 fonts
are embedded into the stylesheet, including a full MIT distribution notice in exported
HTML. No Node, CDN or runtime download is required. The app build verifies pinned code,
stylesheet/license checksums and all 20 font declarations. `Tools/vendor-katex.py`
reproduces the assets from the integrity-pinned npm release.

Validation: **156 tests in 32 suites**, seven native arm64 test executables, native
build-for-testing, strict changed-Swift formatting, shell/Python syntax and diff checks.
Real WebKit checks load the embedded fonts, verify visible equation geometry and MathML,
retain equation node identity across a patch, and take inspected light/dark snapshots.
Native print-to-PDF yields a one-page document containing the equation and both surrounding
checkpoints. Regression cases cover fractions, sums, integrals/matrices, malformed and
malicious TeX, expansion loops, macro isolation, currency/code/link/image boundaries,
CRLF/Unicode source positions, blank lines, quotes/lists, code preceding a display block,
legacy delimiters, unmatched input, portable HTML and preference migration.

The native test suites now share an asynchronous exclusive scope because NSApplication
window/focus/printing state is process-wide. Per-suite `.serialized` alone allowed
separate suites to interleave windows and produced scrolling timeouts. Tests still use
condition-based waits and run without weakening assertions or increasing timeouts.

**The math parity gate remains open.** Remaining work includes full MathJax-only extension
compatibility, document-wide macro definitions/equation references/numbering, single-
backslash inline delimiters, multiline inline math, and display delimiters mixed with
body text across lines. KaTeX's supported TeX set is not identical to MathJax. Preserve
this distinction and add the required compatibility behavior before retiring the old
MathJax target/resources. Mermaid/Graphviz, custom themes/templates and the other
modernization requirements also remain. Direct desktop/VoiceOver/real IME acceptance is
still pending the existing Mac unlock request. No production installation or default
handler change is claimed. See `docs/validation/offline-math.json`.

### M4 — Native workspace and design

- SwiftUI toolbar/sidebar/outline/settings, split/solo modes, focus and typography.
- Native tabs/windows, restoration, keyboard focus, light/dark/high-contrast appearance,
  Reduce Motion, VoiceOver and Retina layout validation with runtime screenshots.
- Gate: keyboard-only open/edit/search/export, theme/window restoration and IME tests.

### Explicit follow-on goal — multiple Markdown files in native tabs

The user explicitly requests multi-tab support after the current work. Treat this as a
required product capability, with its own implementation and verification pass, not a
future idea or a claim already established by DocumentGroup.

- Open multiple `.md`/`.markdown` files into one window as separate native document tabs.
- Support File → Open, Finder/Open With and dropping multiple selected files; route
  already-open documents to the existing tab instead of creating duplicate editors.
- Allow creating/switching/closing/reordering tabs using native controls and shortcuts,
  as well as moving a tab into another window and merging document windows.
- Keep each document's source, selection, preview/scroll position, file URL, dirty state,
  autosave and undo/redo history separate. Closing one tab must not lose another's work.
- Preserve native multiple-window workflows. Scope shared settings globally and
  document-specific state to its tab. Keep tabs keyboard/VoiceOver accessible and use
  native Apple appearance so they fit the current design.
- Verify two or more real Markdown files side by side in a tab group, edit/undo/save
  independently, switch repeatedly, cancel closing a dirty tab, close a clean tab, and
  restore the selected document/tab group after relaunch. Use current SDK APIs and
  native document-host evidence before marking this follow-on goal complete.

#### Native tab foundation — verified increment (2026-11-06)

Document windows now share an explicit tabbing identity and prefer native tabs by
default, with a persisted Documents setting to follow the system preference instead.
The bridge preserves the document host's delegate, window identity, restoration and
close/save ownership. Workspace layout uses per-scene storage.

Direct native checks opened two selected Markdown files in one tab group, created a
third tab with the native “+” button, switched between independent sources, and undid
an edit in its original tab without changing the other. A native integration test also
checks separate selections/undo managers and closing one tab without changing the other.

#### Tab commands and native session restoration — verified increment (2026-11-06)

File → New Tab / Command-T now asks the native document host for a fresh untitled
document and places the resulting window in the originating tab group. A short-lived
placement request ignores existing/utility windows and expires after five seconds;
closing its anchor cancels it. It does not replace the document host, window delegate,
restoration class, undo manager or file coordination. The bridge applies window tabbing
policy before attachment as well as after it.

A Documents setting controls native reopen behavior using the app-scoped
`NSQuitAlwaysKeepsWindows` preference. Its registered fallback is true; explicit app,
system and launch-argument choices retain precedence. No machine-wide setting changes.
Native host restoration reopened two saved documents in the same group with the same
selected tab. Per-scene layout and source-selection offsets restore independently.
Selection restoration waits for the initial document snapshot, clamps stale/Unicode
UTF-16 offsets, avoids marked text, and does not change source or undo history.
Visible source panes receive keyboard focus only when the host has left focus on the
window itself. Scene storage contains UI offsets only, never a duplicate document.

Direct native checks verified repeated Command-T with a blank document already open,
Control-Tab switching, Move Tab to New Window, Merge All Windows, canceling an unsaved
tab close, saving a new tab, activating an existing tab through Open Recent, and repeated
quit/relaunch with different editor layouts and selections in two documents. Source
selection was explicitly checked with keyboard input and after relaunch; simply setting
an accessibility selection did not produce a native selection-change notification.

The full tab follow-on goal remains open: multi-file drops, Finder/Open With routing,
drag reordering, restoring multiple separate groups, source/preview scroll positions,
and the complete keyboard/VoiceOver audit still require implementation or direct
end-to-end evidence. The regression suite passes 116 tests across 23 suites and seven
native arm64 test executables. The native build-for-testing passes; XCUITest execution
remains unavailable because automation enablement times out. No replaced legacy tab or
file-lifecycle implementation was deleted while the old target still consumes it.
See `docs/validation/native-tabs.json`.

#### Markdown file drops — implemented increment (2026-11-06)

The sidebar has a native Open Files button/drop destination, and the native source and
preview surfaces route complete batches of local `.md`/`.markdown` file references to
the document host. Non-Markdown and mixed drops fall through to the existing native
surface behavior. The source is never replaced by dropped paths or contents. Only
copy operations are accepted; no source file is moved or deleted. Batch opening retains
original security-scoped URLs, deduplicates normalized references in order, balances
explicit access, continues after file errors and stops on user cancellation. A newly
created document window joins the originating group; an already-open document keeps
its own existing group. Closing the anchor prevents late placement from reopening it.

Six integration tests use private native pasteboards and real NSTextView/WKWebView
surfaces, plus batch-failure/cancellation and native tab grouping checks. All 122 tests
across 24 suites pass; native build-for-testing passes. The sidebar layout and its
Open Files chooser were checked directly. Physical cross-window Finder dragging could
not be completed through the current UI control surface (noWindowsAvailable), so that
end-to-end acceptance check remains open. Do not equate protocol-level integration
coverage with a completed Finder drag gesture. Sandboxed release access remains part
of production readiness. See `docs/validation/file-drops.json`.

#### Linked scrolling and reading-position restoration — implemented increment (2026-11-06)

Editor and preview scrolling now share source-line coordinates in split mode, with a
View-menu command and Editor setting using the historical `editorSyncScrolling` key.
Explicit disabled choices migrate; the default remains enabled. Native wheel/live-scroll,
keyboard commands, edits and outline navigation select the source as the driver. Preview
scrolling selects the preview. Programmatic movement suppresses feedback, and a new user
gesture supersedes queued movement. Stale preview revisions cannot move current source.
Hidden single-pane modes retain their independent positions and do not link scrolling.

Source coordinates use UTF-16 line maps and public TextKit 2 segment geometry. They do
not change selection, document bytes or undo. Restored source anchors survive later
native caret/focus adjustments until the user scrolls or navigates. Preview coordinates
come from rendered `data-sourcepos` blocks, including nested lists/callouts, with exact
top/bottom handling, coalesced reports, cached geometry and reload-generation checks.
The trusted bridge exists only in WebKit's isolated client world; page JavaScript and
active document content remain disabled, and exports contain no bridge script.

Per-scene offsets are supplemented by bounded durable per-file positions because native
scene recreation did not reliably restore the newly added viewport values in direct
checks. The latest file position takes precedence over stale scene data. The app stores
at most 128 hashed file-URL keys with coordinates/timestamps, never source text; a renamed
or moved file currently starts a new cache entry. Writes are debounced and deterministically
encoded, skip unchanged values, preserve the other pane, and flush on scroll completion
and deactivation. Hidden closing viewports cannot replace the last visible position.

Validation: 136 tests across 27 suites, seven native arm64 test executables, native
build-for-testing, strict Swift formatting and diff checks. Native coverage includes
two-way movement, disabling, stale revision rejection, isolated-world boundaries,
Unicode/newline mapping, source offsets/fractional lines, shortened files, native focus
adjustments, hidden-window persistence, preview context reloads, first split layout,
deferred document snapshots and bounded durable storage. Direct desktop checks verified
keyboard paging moves both panes to corresponding content. The final repeated-relaunch
visual check remains open after the Mac locked; earlier observations exposed launch-time
source drawing/focus issues now addressed by the reviewed implementation. Do not claim
that final acceptance passed until it is observed. Trackpad/mouse-wheel end-to-end checks,
multiple groups/tabs, real IME/VoiceOver and measured performance remain open. See
`docs/validation/linked-scrolling.json`.

A hosted deferred-load regression reproduced and repaired the remaining early-source
restoration race: the document model can have loaded text while NSTextView still contains
its initial empty snapshot. Native source identity/revision now gate capture and movement,
with readiness published after initial creation, synchronization, native edits, formatting
and undo/redo. Restoration waits for the actual native snapshot rather than clamping its
saved offset against the empty editor. The full split-view test fails before this repair
in both appearances, then passes with the restored reading line and bitmap text coverage
identical to ordinary native paging (14,289 light / 15,507 dark ink samples). Generated
native bitmap inspection confirms complete wrapped text, syntax colors, Chinese and emoji.
This strengthens the native evidence; the final desktop relaunch check remains open while
the Mac is locked.

The full modernization goal stays active. No additional legacy implementation is deleted
while the original target still consumes unmigrated renderer/accessory behavior. Release
installation and default association remain gated on broader reliability and parity.

#### Editor/preview pane order — implemented increment (2026-11-06)

The legacy `editorOnRight` preference now controls native pane order. New installs keep
the editor on the left; migrated and explicit choices persist, including explicit false.
The View menu has an **Editor on Right** toggle, mirrored by **Place editor on the right**
in Editor settings. The editor-only toolbar symbol follows the selected side. This is
an application-wide layout preference, matching the original behavior.

NSSplitViewController reorders its existing split items and hosting controllers; it does
not recreate NSTextView or WKWebView. Source width is remembered independently of its
side, so unequal splits mirror correctly. Collapse logic refers to the editor/preview
items themselves, keeping Editor and Preview modes correct in either order. Reordering
preserves native focus. Switching to Editor mode also routes focus away from a preview
that is about to become hidden.

Validation: all 138 tests in 28 suites, seven native arm64 executables, native
build-for-testing, strict formatting and diff checks pass. Tests start in both orders,
set unequal pane widths, retain source/preview reading offsets, verify exact native view
identity, selection/focus, mode transitions while swapping hidden panes, and undo/redo
after reordering. A complete hosted DocumentWorkspace responds to preference changes in
both directions without replacing its document views or changing source/revision. The
right-side SF Symbol resolves through NSImage on the target OS. Settings/menu clicks,
multiple-window propagation, real VoiceOver and the final desktop relaunch check remain
open while the Mac is locked. See `docs/validation/pane-order.json`.

No legacy files are deleted here: the old target still consumes its split-view and
preference implementation. Zoom, additional parity, performance and production-release
requirements remain part of the active modernization goal.

#### Per-document reading zoom — implemented increment (2026-11-06)

Each document owns a 50–300% reading zoom, routed through the focused scene. The View
menu provides Zoom In, Zoom Out and Actual Size with Command–Option–plus/minus/zero;
existing Command–minus strikethrough and Command–zero paragraph shortcuts remain.
Scene storage and the bounded per-file reading cache preserve zoom independently of
other documents. The latest file record wins over stale scene values, and user changes
win over delayed restoration. The optional cache field decodes older position records;
zoom writes merge with the two panes and skip unchanged values.

TextKit 2 uses a presentation font derived from the configured editor font and zoom.
The preview uses public WKWebView.pageZoom. The historical
`previewZoomRelativeToBaseFontSize` choice is migrated and exposed as **Scale preview
with editor font** (off by default), using the editor base size divided by 14. Reading
zoom stays separate from source snapshots, selection, undo, saved typography and the
independent HTML/PDF/print output surfaces. Callout popover anchors account for page zoom.

Source UTF-16/visual-line and trusted preview source-block anchors survive reflow. Latest
zoom requests coalesce with the serialized content/style pipeline, and navigation
generations reject stale work. Animation-frame waits have a bounded fallback for hidden
tabs/locked desktops. New input supersedes a pending viewport restore; preview-led
scrolling remains the driver across reflow. Preview bridge/scripts remain isolated from
page JavaScript and never enter exported documents.

Validation: **145 tests in 30 suites**, seven native arm64 test executables, native
build-for-testing, strict changed-Swift formatting and diff checks pass. Hosted coverage
includes source/preview scale changes, configured typography, native view identity,
selection/text/revision, undo/redo, source-led and preview-led anchors, rapid zoom,
changed-directory navigation, no-bootstrap fractional fallback and user input during a
pending preview restore. Unit tests cover limits, independent controllers, old cache
records, merging, durable-vs-scene precedence, save-as continuity and preference migration.

An intermittent `NSTextLayoutManagerBreakOnNilContentManager` diagnostic was emitted by
the hosted zoom test; it passed without a crash or failed assertion. Three focused runs
under a symbolic debugger breakpoint passed without reproducing it. Keep this in the
native acceptance follow-up rather than claiming a warning-free desktop session.
The test host has no SwiftUI App lifecycle, so this does not prove actual scene restoration
or menu focus routing. Direct desktop/relaunch, real IME/VoiceOver, physical scrolling,
multiple tab/window scene routing and the other modernization gates remain open. The Mac
is still locked and the existing unlock request is pending. See
`docs/validation/document-zoom.json`.

No further legacy deletion or production installation/default association is claimed.
The original target still needs its unmigrated renderer, theme and accessory behavior.

### M5 — Productivity and system features

- Command palette/Quick Open/workspace search, optional syntax enhancements and table
  assistance; then Quick Look/Services/App Intents/Shortcuts as separately tested units.
- AI remains a later optional feature and cannot delay correctness of the editor.
- Gate: each feature has real behavior, tests and explicit optional-syntax preferences.

### M6 — Performance and release readiness

- Fixtures at approximately 100 KB, 1 MB and 10 MB with tables/fences/images/nesting.
- Record cold/warm launch, loading, parsing, preview latency, peak RSS, CPU and energy on
  this host. Warm typing target: p95 <=16 ms for ordinary insertion in a 1 MB document;
  preview target: <=250 ms after debounce for 100 KB. Treat these as goals, not results.
- Large-file mode must keep text input responsive even if preview work is suspended.
- Check all bundled Mach-O binaries with `file`/`lipo`; arm64-only distribution.
- Gate: passing unit/integration/UI suites, measured results recorded, accessibility
  review, reproducible unsigned archive, documented Developer ID/notarization process.
  Signed publication remains conditional on actual credentials and release authorization.

## Risks and decisions requiring evidence

1. Hoedown dialect differs from CommonMark/GFM: keep a compatibility fixture matrix;
   no parser swap justified solely by package language or popularity.
2. Legacy plugins contain native executable code and may be Intel-only: inventory real
   plugins, preserve the API where practical, report incompatible binaries explicitly.
3. WKWebView timing/source mapping affects scroll sync, export, fonts and diagrams:
   revision-tagged ready events and deterministic integration fixtures are mandatory.
4. Document APIs can subtly alter undo, file presenters or scripting: verify actual SDK
   behavior before replacing NSDocument, not just compile-time availability.
5. TextKit 2 can fall back to TextKit 1 when accessing legacy layoutManager APIs: avoid
   those calls and inspect the real layout manager during view tests.
6. Large files cannot require attributed-string reconstruction on every keystroke.
7. Missing old dependency installation prevents legacy runtime characterization today;
   distinguish source/test-derived expectations from observed runtime results.

## Validation ledger

- Legacy workspace: **failed**, exit 65 before compilation; captured baseline diagnostics.
- Swift core build/tests: **passed**, 19 Swift Testing tests across three suites,
  including parameterized encoding/range cases and a 10 MB Unicode round-trip.
- Repeatable `Tools/validate-modernization.sh`: **passed** using Swift 6.4.2, with
  both DocumentCoreTests and EditorCoreTests Mach-O bundles verified arm64-only.
- Initial foundation package had no external dependencies and used macOS 27 baseline and Swift 6 mode;
  no unsafe Sendable escape hatches or actor-isolation suppression were introduced.
- GitHub Actions workflow added for the documented `xcode-27` native arm64 image;
  **remote execution has not been triggered or verified**.
- Swift modules are **not yet connected to the legacy application**. Legacy source
  has not been removed; this is foundation work, not completion of Swift migration.
- Final local evidence is recorded in `docs/validation/swift-foundations.json`.
- Modern application launch, UI/IME/accessibility, export, benchmarks and complete parity:
  **not yet verified**.

## References

- [Apple: Updating your document-based app](https://developer.apple.com/documentation/swiftui/updating-your-document-based-app)
- [Apple: DocumentReader](https://developer.apple.com/documentation/swiftui/documentreader)
- Installed Xcode 27.2 SwiftUI `.swiftinterface` (Document/reader/writer protocols).
- [Swift Markdown: parser, AST and cmark-gfm implementation](https://github.com/swiftlang/swift-markdown)
- [GitHub Xcode 27 runner availability](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)
- [Sparkle upgrade guidance](https://sparkle-project.org/documentation/upgrading/)

Update this ledger after each verified milestone. A roadmap, package build or screenshot
must never be presented as completion of the full application modernization.

## Milestone 2 progress — native document/editor adapter

- Added `SnowfolioUI` as a separately testable native adapter target.
- `MarkdownDocument` conforms to the actual macOS 27 `Document` protocols with
  FileWrapper reader/writer adapters and immutable byte-preserving snapshots.
- Main-actor observable source state; explicit programmatic undo/redo registration.
- External snapshots that conflict with unsaved local text are rejected instead of
  silently overwriting it. This unit behavior does not yet verify a hosted conflict UI.
- Native `NSTextView` uses TextKit 2, built-in find, spellchecking, plain-text editing
  and the host undo manager. Selection is preserved during document reflection and
  active marked text is not reset.
- Real view tests exposed that undo restored native text without updating the model;
  the adapter now observes undo/redo completion and synchronizes the source.
- Local validation: 28 Swift Testing tests across five suites passed; all three test
  executables are arm64. See `validation/native-document-adapter.json`.
- Still required for M2: actual application bundle/window integration, coordinated
  file open/save through DocumentGroup, autosave/Versions/conflict presentation, native
  tab/multiwindow UI tests and real Chinese/Japanese input-method sessions.
- No legacy application source or user preferences were removed or modified.

## Added requirements: adaptive icon and zero legacy first-party code

- Ship an original layered Liquid Glass app icon. `App/Resources/AppIcon.icon` is
  editable in Apple Icon Composer; its SVG layers are original vector artwork.
- Verify Default, Dark, Clear Light/Dark, and Tinted Light/Dark using Apple's renderer.
  The six real renderings are in `docs/design/icon`, with `Appearances.png` as the sheet.
  Tinted previews use one example tint; the operating system chooses the user's tint.
- Compile the native `.icon` asset through Xcode, retaining its `Assets.car` renditions
  and generated `.icns` fallback. Do not substitute a single flat PNG as the app icon.
- Final cleanup target: **zero legacy first-party implementation code and zero duplicate
  application targets**. After each migrated subsystem passes parity checks, delete its
  old implementation, test duplicates and obsolete build references in a reviewable commit.
- The transition may temporarily contain the legacy and modern projects. Completion
  requires retiring `MacDown/Code`, Objective-C test/CLI implementations, CocoaPods/Gem
  integration, legacy Xcode targets, Travis and replaced release tooling. Keep history in
  Git, not dead source folders or a parallel legacy app in the finished tree.
- Retain and relocate still-used themes, user-facing resources, third-party components
  with justified maintenance boundaries, and all applicable license notices. Their age
  alone is not a reason to delete a feature or strip copyright attribution.
- M1/M2 source is foundation work; it does not justify removing the still-needed legacy
  parser, renderer, export, settings, automation or plugin implementation prematurely.

## Native host integration evidence

The generated `App/Snowfolio.xcworkspace` builds a real `.app` with the local
Swift package. `Tools/build-snowfolio.sh` reproduces generation/build and verifies
arm64 output and compiled adaptive icon resources. The app, debug dylib and preview
dylib were inspected as arm64. The full app is still an incremental migration build.

Direct native UI checks verified new documents, Unicode text input, native undo/redo,
the Save panel and byte-exact UTF-8 output. After editing without another Save command,
the autosave checkpoint appeared on disk. Multiple documents appeared in the Window
menu; Merge All Windows produced the native two-tab bar. An outside file edit caused
the native Save Anyway / Save As / Revert conflict dialog. Revert loaded the external
contents without overwriting them. A BOM-tagged UTF-16 file containing CRLF, Japanese,
Chinese and emoji survived native Open and Save with identical bytes.

The XCUITest runner built, but local automated execution timed out enabling automation
before any test cases ran. This is recorded as a verification gap, not a passing UI
suite. The UI tests and hosted-runner CI job remain configured. Real IME sessions,
restoration and preferences migration are still required before closing all M2 gates.
See `validation/native-host.json` and `validation/native-host-ui-runner.json`.

The icon source compiled successfully through Xcode into AppIcon.icns and Assets.car;
asset inspection found 40 icon-related records. All six macOS 27 appearance previews
were rendered with Apple's tool and visually reviewed. See `validation/adaptive-icon.json`.

Icon palette refinement: use the user-requested gentle glacial ice blue for Default,
with coordinated cool-blue Dark artwork. Clear and Tinted retain native system rendering.

Icon palette follow-up: deepen the glacial-blue background midtones and saturation
to avoid the previous overly pale result, retaining the cool hue and native appearance modes.

## Parser, live preview and preferences integration

The modern app now connects the native source editor to a stable WKWebView preview,
with editor/split/preview layouts, a heading outline and a native Settings scene. The
outline uses one-based parser lines mapped to UTF-16 offsets, including CR/LF/CRLF and
non-BMP characters. Stale outline navigation is disabled until a new result is published.
Native document revision counters trigger work without hashing the entire source as a
SwiftUI task identifier. Selection requests do not change document contents or dirty state.

### Parser decision and third-party exception

Evaluated `swiftlang/swift-markdown` 0.9.0 and its underlying `swiftlang/swift-cmark`
0.9.0. The public Swift Markdown HTML formatter did not meet this integration's escaping
and footnote requirements. Use the maintained cmark GFM engine directly behind a Swift
actor rather than implementing a Markdown specification or parsing twice. This is a
**third-party C exception**, not first-party Swift migration. The package version and
revision are pinned; its complete COPYING notice is included in app resources.

One native parse supplies HTML and an owned Sendable flat AST. CommonMark/GFM tables,
task lists, strikethrough, autolinks and footnotes are covered by fixtures, with extension
preferences honored. Code and unsafe URL escaping are covered. This is currently a
whole-document parser with chunked feed and cancellation checks, **not incremental
reparsing**. Legacy-specific dialect extensions remain separate outstanding parity gates.

### Preview and resource policy

A 180 ms debounced background task publishes only current document revisions. Explicit
Render requests bypass debounce once; ordinary edits retain debounce afterwards. Files
larger than 1 MiB pause automatic preview with a visible Render action, preserving editor
availability. Performance targets still require measurement; this threshold is a guardrail.

The WebKit shell is loaded once per document directory/resource-policy change, then
trusted isolated-world code patches the DOM using HTML arguments. Unchanged nodes and
the visible scroll anchor are retained. Generation checks discard obsolete callbacks.
Document JavaScript is disabled; CSP denies scripts, frames, connections, forms and
objects. Remote images require an explicit preference. Relative local images, CSS and
fonts use a dedicated scheme restricted to the document directory and allowed types.
Descriptor-relative O_NOFOLLOW reads prevent symlink swaps from escaping this boundary;
regular files and a 32 MiB size cap are enforced. Arbitrary page navigation is denied;
explicit external link clicks use the system handler.

### Preferences and verification

Versioned migration copies persisted historical keys without changing the old preference
domain or overwriting new-app choices. Explicit false values and font dictionaries survive;
transient CLI launch queues are excluded. Tests use isolated preference suites. The current
Settings UI exposes typography, manual rendering, GFM options and preview privacy. Other
legacy settings are retained as data but their behaviors are **not all migrated yet**.

Local validation: **44 tests across ten suites passed**, with six test executables
verified arm64. Real WebKit integration tests verify DOM updates, retained node identity,
scroll position, blocked inline event handlers, relative local PNG loading and CSP-blocked
remote images/frames. The native app builds for testing. These are integration tests,
not a passing XCUITest automation run. Direct native inspection verified the new workspace, Settings panes, manual preview
deferral and explicit refresh, then native Save. The previous XCUITest initialization
failure remains unresolved. See
`validation/live-preview.json` for evidence and outstanding work.

Still required: legacy dialect fixtures, front matter/math/diagrams, syntax highlighting,
custom styles/templates, linked scrolling, export/print, full preference parity, real IME
sessions, visual/accessibility checks, performance and the remaining roadmap. Legacy
renderer/preferences implementations remain because their complete consumers and parity
gates have not yet migrated. No legacy source is deleted by this partial integration.

## HTML, PDF and native printing integration

- Added `ExportCore` and window-scoped export commands: Export HTML, Export PDF, Copy
  HTML and Print. Save panels attach to the owning document, and File-menu commands
  follow the focused scene. Workspace layout controls now have readable accessibility
  labels rather than SF Symbol descriptions.
- Export takes an immutable snapshot of current text and rendering choices at invocation.
  It never reads potentially stale manual-preview output. Native print uses a separate
  hardened WebKit surface, leaving the live preview's scroll position and document alone.
- Styled/plain HTML preserves Unicode, escapes titles and keeps the restrictive CSP.
  Markdown local image resources are embedded as data URLs so they survive moving the
  exported HTML. Copy HTML retains references and does not require local image files.
- Local images retain the preview reader's directory/type/size boundary and descriptor-
  relative symlink protection. Generated image markers allow safe SVG/HEIC data embedding
  without enabling cmark's unsafe HTML/URL mode. A single pass substitutes known image
  attributes; the original Markdown is parsed once, and raw HTML is not regex-transformed.
- Native AppKit printing paginates the full WebKit document. PDF export prints into a
  temporary staging file, then atomically replaces the user-selected destination only
  after successful completion. Image decoding and font readiness precede printing.
  Printing callbacks may originate on AppKit's worker thread; only their Boolean result
  transfers to the main actor.
- A first test incorrectly called synchronous `NSPrintOperation.run()`, which blocked
  WebKit's asynchronous page calculation and produced an unbounded incomplete spool.
  That test process was stopped and its temporary output removed. Both production and
  the corrected integration test use document-modal asynchronous printing, as required
  by the WebKit implementation. This was not accepted as a successful export.
- Current local validation: **53 tests across 12 suites passed**, with seven arm64 test
  executables. A long PDF fixture contains eight Letter pages, beginning/ending text,
  Japanese and Chinese. PDFKit extraction maps some CJK glyphs to compatibility radicals;
  assertions normalize those forms, and first/last pages were also rendered and visually
  inspected, including emoji. Vector-image decoding and corrupted-image errors are tested.
- Source references for the print-threading decision:
  [AppKit printing threads](https://developer.apple.com/documentation/appkit/nsprintoperation/canspawnseparatethread),
  [WebKit printing implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/WKPrintingView.mm).

Remaining export parity: syntax-highlighting resources and its export switch, custom
styles/templates, math/diagram/front-matter fidelity, resource handling inside opt-in raw
HTML, saved page setup and wider print/layout fixtures. The legacy export/renderer code
still has unmigrated consumers and must remain until those parity gates pass.

Direct native export checks then passed: HTML save sheets with Include document styles
on/off, actual styled/plain output content on disk, native PDF save, Copy HTML pasted as
markup into a new empty document, Print dialog preview and clean cancellation. The source
fixture remained unedited. The runtime PDF's Unicode text was extracted with PDFKit and
its full page rendered with Apple's renderer, confirming Japanese/Chinese/emoji. The
bundled Poppler lacked a required CJK language pack for that runtime file; its incomplete
render was not used as evidence of missing glyphs. PDF export explicitly requests all
pages, independently of previous printer range choices. See `validation/export.json`.

## Release installation and document identity authorization

The user authorizes verified commits to be pushed to the modernization branch. After
core parity and reliability checks provide adequate confidence, build tested releases,
install them in the user's Applications folder, and set the installed app as the default
Markdown viewer/editor. Do not set the default while the replacement remains an incomplete
migration build. Earlier registration-only preference was superseded for that later,
validated release step. Do not replace an unrelated application or change plain-text
file defaults. The user also requests upgraded Markdown document/file-type icons and
macOS registration; keep those registrations distinct from default-app changes.

Product name confirmed: **Snowfolio** (superseding the earlier MacDown working name).
Keep the glacial-blue icon style and M↓ Markdown format mark. Use Snowfolio for current
visible branding and the app bundle; retain compatibility identifiers and preference
migration history. Preserve all copyright and license notices.

## Markdown command engine and document icons

`EditorCore/MarkdownEditing.swift` now produces local UTF-16-safe transactions for
inline formatting, heading/paragraph conversion, list/quote conversion, indentation,
links/images, task toggling, list/quote/indent continuation, tab stops and optional paired
delimiters. Fixtures characterize selection-preserving toggles and the legacy emphasis
versus bold distinction. Mixed CR/LF/CRLF and multi-digit list prefixes use corrected
selection mapping. This engine is tested but **not yet wired into the native editor or
Format menu**; native undo/input/IME integration remains the next required editing step.
Latest core validation: **63 tests across 13 suites**, seven arm64 executables, all passed.

The current product name and bundle are **Snowfolio** / `Snowfolio.app`, with
`CFBundleName` and `CFBundleDisplayName` set to Snowfolio. Stable bundle identifiers and
preference migration remain intact. A separate glacial-blue document identity retains
the M↓ mark without an app-shaped background around the page. Native `UTTypeIcons`
references compiled background/badge icon sets, allowing macOS to supply its own folded
page, scaling and MD label. A generated high-resolution ICNS is the fallback; the artwork
and build tools are first-party Swift and reproducible with `Tools/generate-document-icons.sh`.

Markdown and plain text are separate document declarations, so the custom icon applies
to Markdown and does not decorate ordinary `.txt` files. Preserve both original `.md`
and `.markdown` tags and both Markdown MIME spellings. The standard Markdown UTI is
imported rather than claimed as a new proprietary type. Registration uses public
`LSRegisterURL`; `NSWorkspace` verifies the built app is an available Markdown handler.
Default applications are read before and after registration. No default setter is called.
The current original MacDown (`com.uranusjr.macdown`) and TextEdit defaults remain unchanged.
Finder may continue displaying its current default handler's icon until the later tested
release is installed and made default, as authorized by the user.

Apple's document-icon composition reference:
[UTTypeIcons](https://developer.apple.com/documentation/bundleresources/information-property-list/utexportedtypedeclarations/uttypeicons).

## Added goal requirement — Notion-like Markdown styles

The user requests that the Markdown/document styles closely resemble Notion. Treat this
as an explicit acceptance requirement for theme and rendering work. Match the visual
character of its readable typography, heading hierarchy, paragraph/section spacing,
list and task-list treatment, subtle table borders, inline/fenced code, quotes, callouts,
links and restrained light/dark document surfaces. Use current, publicly observable
Notion document styling as a reference and inspect representative rendered fixtures.
Keep this as an intentional, reusable style/theme in the native Markdown editor, preview
and styled exports, with consistent document typography and spacing across those outputs.
Preserve existing custom themes/styles and extension capabilities through their migration;
do not use a visual reference as justification to remove writing features or alter file data.
Acceptance requires runtime visual comparison in light/dark modes, readable tables/code/
Unicode, accessibility contrast checks, and HTML/PDF export fidelity. This requirement is
part of the active full modernization goal, which explicitly follows this plan.

## Native Markdown commands and stable workspace panes

The tested editing engine is now connected to the real TextKit 2 editor and a window-
scoped Format menu. Bold/italic, inline code, strikethrough, comments, heading/paragraph,
ordered/unordered lists, quotes, task toggling, indent/outdent, links/images and new
paragraph commands use local replacements. Historical shortcuts are retained for these
commands. Link/image commands can seed the selected destination from a valid clipboard
URL. Command availability follows the source editor's native focus and composition state.

Typing settings preserve historical preference keys and defaults: tabs/spaces, list and
quote continuation, incremented list numbering, optional matching delimiters and the
unordered-list marker. They appear in native Settings and persist across model instances.
Return continues lists and resets task checks, exits empty list items, preserves local
line endings and avoids duplicating a pre-existing marker. Paired insertion, selected
text wrapping, closer skipping and paired deletion are optional. Pasteboard reads bypass
pairing even for a single character; multi-character insertion also keeps native behavior.

The first marked-text update is protected before calling AppKit, including ASCII input
at the start of composition. Formatting is refused while composition is active, and
native marked text is not reset. Tests exercise actual NSTextView marked-text methods;
these do not replace the still-required real Chinese/Japanese input-method sessions.

Each command is one native undo group. Native text undo initially restored the wrong
selection; mirrored selection actions now bracket AppKit's text inverse so repeated
undo/redo restores both text and the intended selection. No-op formatting and skipping
an existing closer create no dirty undo step. Main-actor guards and weak undo-manager
captures avoid custom text-history stores or unsafe concurrency escapes.

The workspace uses an NSSplitViewController with stable SwiftUI-hosted editor and preview
surfaces. Hiding a pane keeps its text view, input context, undo observer and WebKit state
alive. The document undo manager passes explicitly across the hosting boundary. The
previous split fraction is restored after returning from a single-pane mode. A native
integration test confirms view identity, subsequent font updates, split size and document
undo after multiple mode switches.

Validation: **73 tests across 14 suites passed**, seven arm64 test executables, plus a
successful native app build. Direct native UI checks verified Bold/Italic shortcuts with
Unicode selections, formatting undo across preview/split changes, Format-menu contents,
list numbering/exit, heading conversion and outline updates, independent document windows,
optional pairing/closer skipping/deletion, native Settings, preference restoration and
saved UTF-8 fixture bytes. See `validation/native-editing.json`. XCUITest runner startup
is still a separate unresolved environment issue; no automated UI-runner pass is claimed.

Still required for complete editing parity: renderer support and source commands for the
remaining legacy dialect extensions (including underline/highlight), smart Home behavior,
fence-aware continuation, richer table/code assistance, image drag/drop, syntax highlighting,
real IME sessions, broader keyboard/accessibility review and measured large-file latency.
Retain the old autocomplete/editor implementations until their complete consumer and
parity gates pass. The Notion-like document style requirement above remains active.


## Notebook presentation progress — 2026-11-06

The first Notion-inspired document theme is implemented in `RenderingCore.DocumentStyle`,
shared by the live preview and styled HTML/PDF/printing. A neutral warm-gray hierarchy,
generous spacing, restrained links/inline code, nested lists/tasks, quote rules and light
table grid replace the temporary blue-gray preview stylesheet. Documents settings offer
Default/Serif/Mono, 12–28 point text and full width. Choices persist independently of the
legacy source-editor font and custom-style paths. No source syntax or bytes are rewritten.

Styles update the existing WK document in the isolated client world: no navigation,
parser rerun or content-node replacement is needed. Source-position anchors preserve
the reading position. Export captures the same immutable style with source/settings;
subsequent preference changes cannot alter an already-requested export. Print uses a
light palette and retains full-document pagination.

Validation: 74 tests in 14 suites, seven native arm64 executables; native app
build-for-testing passed. Real WebKit checks exercise light/dark, computed text contrast
>=4.5:1, heading hierarchy, bounded reading width, 320-point viewport containment,
style-update node/anchor preservation and actual export font/size resolution. Native
PDF pagination/Unicode regression tests pass. Strict Swift formatting and diff checks pass.
See `validation/notebook-style.json` and `design/notebook/` for the fixture and screenshot.
The full preview and Documents settings were inspected directly in the updated app;
native UI became unavailable before the remaining font-menu interactions.

This is partial delivery of the Notion-style requirement. Source-editor syntax theming,
custom CSS/style migration, alert/callout rendering, actual increased-contrast UI and
complete light/dark/per-font export visual comparisons remain pending. The full
modernization goal remains active; no legacy source is removed at this partial gate.


## Optional callout rendering — 2026-11-06

Top-level GitHub-style `NOTE`, `TIP`, `IMPORTANT`, `WARNING` and `CAUTION` markers
now render as quiet Notebook callout surfaces in preview and styled exports. Each
canonical uppercase marker occupies its own quoted line. The persisted Markdown
setting “Notes, tips and warnings” disables the extension for strict ordinary quote
output. Unknown, escaped/entity-escaped, inline-code, fenced/indented-code, reference
link and nested markers retain normal Markdown meaning. Callout bodies retain native
paragraphs, lists, headings, inline formatting, links and image behavior.

Recognition uses both the native block/inline tree and original marker line. The
original immutable AST, source positions and outline are captured before render-only
decoration. Trusted custom-block wrappers contain only enum constants and native
integer source positions; no document text is interpolated into wrapper HTML. Child
content still passes through cmark’s safe HTML and URL renderer. Visible type labels
carry meaning independently of color; decorative symbols are hidden from VoiceOver,
and these static document blocks do not trigger live alert announcements.

Validation: 80 tests in 15 suites, seven arm64 test executables, native app
build-for-testing, and five address-sanitized parser tests passed. Native WebKit tests
measure light/dark contrast against the actual callout background (>=4.5:1), verify
labels and narrow layouts. Native paginated PDF extraction finds the Warning label
and body after multiple pages. Styled/plain HTML and disabled-option export checks pass.
Direct native inspection verified all five labels, ordinary quote fallback, Default/
Serif display and restored Default font/re-enabled callouts. See
`validation/markdown-callouts.json`, `design/notebook/Callouts.md` and its screenshot.

An intermittent native UI inspection timeout remains open, including after closing
Settings. The diagnostic sample showed a normal idle main event loop and no crash
report; fresh launches restored access, and switching through Window menu allowed
inspection. Investigate this before claiming the settings/window workflow fully
verified. Full callout light/dark visual comparison, custom theme migration and
source-editor styling still remain; the overall modernization goal stays active.


## Design direction refinement — 2026-11-06

The user likes the current Notebook/callout design and asks to preserve its overall
look. Notion remains a reference for readable document structure and emoji interaction,
while Snowfolio must develop its own visual identity and follow Apple's current design
guidelines. Use native Liquid Glass in appropriate toolbars, controls and popovers;
keep writing/reading surfaces quiet, opaque and legible. Preserve the established
glacial-blue app identity and native Mac behavior rather than reproducing Notion's
interface. Respect system light/dark, Increase Contrast, Reduce Transparency and Reduce
Motion. Avoid a wholesale redesign of the current content styling. This refinement is
an explicit requirement of the active modernization goal and applies to the emoji
picker now being completed and later workspace/UI work.


## Native callout emoji picker — 2026-11-06

The requested picker and refined callout layout are implemented. After read-only visual
inspection of the authorized Notion reference, Snowfolio now uses a larger icon gutter,
quiet type-specific surfaces and a native transient NSPopover. Search, Unicode category
selection, recents, callout suggestions, random choice and reset operate locally. The
popover adopts native system appearance and disables presentation animation for Reduce
Motion. This follows the design refinement above while preserving the liked content look.

The `EmojiCore` Swift module owns the bundled Unicode Emoji 18.0 catalog, validation and
license; UI choices are filtered against the installed emoji font, on a background actor,
then cached. New glyphs unsupported by this Mac are excluded from the picker, while the
portable source parser accepts the complete catalog. Resource/license inclusion is
verified in the native app bundle. No build-time network fetch or Notion dependency is
introduced.

A custom icon is ordinary source text on the marker line (`> [!NOTE] 🎯`). Validation
accepts one catalog emoji, including composed sequences/flags/skin tones, and rejects
arbitrary text/HTML. Source replacement preserves indentation, trailing whitespace and
newlines. The controller validates the current document revision, approved parsed target,
native editor/source equality and marked-text state before using one native undo action.
Failed/stale preview updates cannot authorize edits. Only the live preview emits editing
links; styled/plain HTML/PDF/print receive inert icon markup. Custom icon callouts place
body content alongside the emoji and keep the kind label available to accessibility.

Validation: 85 tests in 17 suites, seven arm64 test executables, native app build-for-testing,
strict Swift formatting and diff checks passed. Actual native checks verified icon click,
search/selection, preview-mode undo/redo, saving/reopening the custom suffix, recents and
final font-filtered display. See `validation/callout-emoji-picker.json` and
`design/notebook/EmojiPicker.png`, `RefinedCallouts.png`, `EmojiDemo.md` and `EmojiData.md`.

The user’s refined design direction is now part of the active goal. Source syntax
highlighting, custom theme migration, broader accessibility/system-appearance checks,
the older Settings inspection issue and the remaining roadmap stay open. No legacy
implementation is deleted at this partial feature gate, and no release/default handler
is installed or changed before the core reliability/parity gates.

## Source syntax colors and progressive cleanup — 2026-11-06

The source editor now has an optional, persisted “Highlight Markdown syntax” setting.
Parser-owned ranges drive semantic heading, emphasis, link, code, quote/comment and
marker colors through native TextKit 2 rendering attributes. The original source stays
fully visible. Off-main AST processing composes nested styles, maps UTF-8 endpoints to
UTF-16 in one scalar pass and resolves overlapping ranges with an event sweep. Native
presentation binary-searches runs for cached/visible fragments; scrolling uses the
validator rather than forcing full-document layout. Source edits invalidate old styles;
stale revisions and marked-text composition cannot apply styles to different text.

Source syntax/outline parsing is separate from preview publication: manual preview can
stay unchanged while source syntax follows edits. Exports opt out of syntax generation.
The existing 1 MiB automatic-parse threshold remains; this is not incremental parsing.
The editor maintains its selected base font and layout metrics. Actual visual inspection
showed temporary font/decoration traits were not reliably honored by NSTextView, so the
final implementation uses supported foreground/background colors and does not claim
source bold/italic/strikethrough glyph styling. Preview/export formatting is unaffected.
Custom source themes, font treatments and remaining dialect parity are still required.

Validation: 91 tests in 19 suites passed, with seven native arm64 executables. Tests cover
nested styles, Unicode/CR/LF/CRLF boundaries, literal fenced/indented code, optional syntax
without HTML/AST changes, 2,000 spans on a Unicode line, native temporary color attributes,
unchanged storage/selection/undo, stale snapshots, composition and preference persistence.
Native app build-for-testing and strict Swift formatting passed. The final development
binary was relaunched: heading/emphasis/link/code colors were visually observed, then
“Bold” was changed to “Strong” and native undo restored the exact original text/preview.
This does not close real IME, VoiceOver, system-appearance or XCUITest runner gates.

The user's renewed request to progressively delete unneeded original code is part of
each migration increment. Two verified dead legacy helpers (17 lines including their
declarations) were removed in a separate commit; the retirement ledger is in
`SOURCE_INVENTORY.md`. Helpers and subsystems with remaining callers/parity gaps stay
until their replacement is verified. No essential writing feature, license or still-used
resource was removed. The full modernization goal remains active.

## Local preview/export code highlighting — 2026-11-06

Language-aware code highlighting is now part of the shared parser result, before HTML
reaches WebKit. `CodeHighlightCore` evaluates only a checksum-pinned local Prism 1.30.0
bundle inside a parser-actor-owned JavaScriptCore context. The application adapter,
selection, caching, preferences and render integration are Swift; the third-party
JavaScript grammars are an explicit ownership exception. Markdown is passed as a value
to `Prism.highlight`, never interpolated into executable code. No DOM, native bridge,
file API, network API, Node runtime, CDN or page scripts are exposed to document text.

The bundle contains 297 upstream components, covering 292 standalone grammars plus five
extras that extend other grammars. Upstream aliases and MacDown's historical aliases
(including `jl`, `c++`, `coffee-script`, `obj-c`, `graphviz` and `gv`) are supported.
JSON uses the maintained dedicated JSON grammar. Original AST nodes, literals, source
ranges, outline and source syntax remain unchanged; only the render tree receives
trusted wrappers containing escaped Prism output. Unknown, unlabelled and over-limit
blocks remain complete escaped code. Code inside callouts retains its original behavior.

The Snowfolio theme adapts to light/dark appearance and printing, with a contrast
fallback. All eight original built-in Prism themes are available: Prism, Coy, Dark,
Funky, Okaidia, Solarized Light, Tomorrow and Twilight. Legacy theme names are matched
case-insensitively; empty/default names and unknown-name fallback preserve the original
Prism default behavior. Existing explicit `htmlSyntaxHighlighting` and theme preferences
are migrated without replacing user choices. Theme changes update CSS in place and keep
existing code nodes and reading anchors. New installs use the adaptive Snowfolio theme.

HTML export exposes independent “Include document styles” and “Include code highlighting”
controls. Token markup and the selected local CSS ship in the exported HTML; no script
or runtime fetch is required. PDF/printing use the same immutable render output and
native print path. `Tools/vendor-prism.py` regenerates resources from the official npm
archive after verifying its SHA-512 integrity; provenance records the upstream commit
and individual file hashes. One documented encoding patch omits Prism’s conversion of
nonbreaking spaces into ordinary spaces; native code-text tests cover preservation.
The build verifies the bundled resources, themes, license
and hashes. Ordinary builds require neither Node nor a network download for Prism.

Native inspection exposed a startup race: two app-owned skeleton loads could overlap
when the document directory changed, and the first policy callback consumed the gate
needed by its replacement. A regression reproduced the blank preview before the fix.
The gate now stays open until the current load completes, and allows only the exact
`about:blank`/`mdasset://document/` skeleton URLs. Existing resource/CSP/navigation
boundaries remain enforced. Rapid replacement and standard preview policy tests pass.

Validation: 99 tests in 20 suites passed, with seven native arm64 test executables.
All 292 standalone grammars accepted code; legacy aliases, AST/source invariance,
unknown/large-block fallback, theme resources/migration, scriptless HTML export,
WebKit's exact malicious-looking code text, adaptive token contrast >= 4.5 in both
appearances, stable code-node identity through all themes, native PDF code text and
startup replacement are covered. Strict Swift formatting, diff checks and native app
build-for-testing passed. A fresh final development process displayed highlighted
Swift/JavaScript/HTML/Graphviz-source code, accepted Tomorrow then restored MacDown in
the native picker, and exported HTML through the native File menu. The saved file has
both stylesheets, token markup and no script elements. See
`validation/code-highlighting.json` and `design/notebook/CodeDemo.md`/`CodeDemo.html`.

Limits still open: regex-based Prism has known tokenization edge cases. A block over
65,536 UTF-16 units falls back to complete plain code; cancellation is checked between
JS calls, not a hard deadline within one call. Caching is bounded to 32 entries/1 MiB.
M6 still needs measured/adversarial performance work, and no responsiveness claim is
made from these tests. Code labels/accessories, line numbers, custom CSS/templates,
source `.style` themes, math/diagrams and the wider roadmap remain required. Graphviz
source coloring is not Graphviz diagram rendering. CUA had window-context timeouts
after closing Settings and while inspecting the toolbar Export popover; live sampling
showed ordinary menu tracking, and File-menu export succeeded. Wider native keyboard/
accessibility checks and the unresolved XCUITest automation gate are not claimed passed.

No additional legacy subsystem is deleted in this increment: the old renderer still
owns unmigrated math/diagram, custom-template and accessory behavior. Continue progressive
removal at verified parity gates, retaining licenses/resources and Git history. The
full modernization goal stays active; no production release/default-handler change
is made by this development increment.

## Ordered front matter and portable navigation — 2026-11-06

YAML front matter now renders as compact semantic document properties, with nested
property rows and wrapping list chips. This follows the independent-product direction
while retaining authored order, scalar spelling (including `001`, dates, `false`, `null`
and empty values), nested collections and aliases. Metadata strings are escaped text,
not Markdown, HTML, executable tags or configuration commands. Existing explicit
`htmlDetectFrontMatter` and `htmlRendersTOC` preferences migrate and persist independently.
New controls are in Markdown settings; invalid/over-limit metadata remains visible as
ordinary Markdown with a revision-checked notice.

Yams 6.2.2 is pinned at `a27b21e0c81c5bf42049b897a62aaf387e80f279` through SPM. Its
maintained CYaml/libyaml event parser validates YAML; a bounded first-party Swift
composer stores ordered scalar/sequence/mapping values with shared integer references
for aliases. It does not invoke tagged-object constructors or expand aliases into an
unbounded recursive object graph. Limits: 64 KiB header payload, 4,096 nodes/expanded
render visits, 8,192 events, depth 32 and 256 KiB metadata HTML. Cycles, duplicate scalar
keys, malformed/undefined aliases and excessive graphs fall back visibly. Still-needed
Yams and libyaml MIT notices ship in the native app. This is a maintained third-party C
boundary; first-party application logic remains Swift.

Internally masking the valid preamble preserves every UTF-8 byte position and original
line ending while keeping metadata out of the Markdown grammar. The stored document
text/bytes are unchanged. The owned AST has a front-matter node with the original range;
headings, outline UTF-16 offsets, callout marker lines and source syntax still map to the
actual file. Only initial exact `---` blocks closed by `---` or `...` are recognized;
indented delimiter text in YAML block scalars is retained. Ordinary documents avoid a
new full-source copy when no opening fence exists.

Headings now have deterministic, unique human-readable Unicode IDs. Generated IDs
reserve application element IDs and the old `toc_N` namespace. Original heading children
still use cmark's escaping/rendering. Empty zero-width `toc_N` aliases preserve legacy
links. An AST-recognized standalone `[TOC]` expands into accessible nested navigation;
escaped/entity/code/reference-link spellings remain ordinary content. TOC links use
escaped titles and percent-encoded fragment URLs. The native navigation handler decodes
fragments once through URLComponents before looking up the target. Metadata, heading
links and TOC survive HTML/PDF/print without page scripts or network resources.

Validation: 111 tests in 22 suites passed, seven native arm64 test executables, native
app build-for-testing, strict Swift formatting and diff checks. Added coverage includes
ordered literal/nested YAML, aliases, malformed/duplicate/cyclic/exponential/deep input,
CR/LF/CRLF and non-BMP source offsets, escaped TOC markers, skipped heading levels,
multiple/nested TOCs, duplicate/Unicode/reserved heading IDs, unchanged AST when TOC is
disabled, exact safe native property text, real Unicode and legacy-link scrolling,
standalone export, native PDF properties and persisted preferences. A fresh final native
process displayed the compact property layout and nested contents; a clicked Unicode
contents link moved the preview to its target. See `validation/metadata-navigation.json`
and `design/notebook/MetadataDemo.md`.

The user-requested native multi-document tab milestone above is explicitly next. It is
not yet implemented/verified by these document-rendering tests. Metadata-based suggested
filenames/window titles, complete VoiceOver/keyboard/system appearance checks, measured
performance, the wider renderer/dialect/integration roadmap and progressive retirement
remain open. No further legacy files are deleted here because the old target still
consumes its renderer, metadata and title helpers. The full goal stays active.


## Offline Mermaid and Graphviz — 2026-11-06

The native renderer now recognizes optional `mermaid` fences and all six original
Graphviz engines (`circo`, `dot`, `fdp`, `neato`, `osage`, `twopi`), plus `sfdp` and
`patchwork`. `graphviz`, `gv` and `viz` alias `dot`. The independent `htmlMermaid` and
`htmlGraphviz` choices migrate existing values, preserve explicit false and default off.
Settings expose each choice. Source AST ranges and native syntax coloring remain intact;
failed/oversized/unsafe/timed-out rendering keeps highlighted source and a preview notice.

`DiagramCore` uses pinned Mermaid 12.3.0 and Viz.js 3.31.0 with Graphviz 16.1.0 embedded
WebAssembly. A dedicated nonpersistent WKWebView runs bundled engines in the isolated
client world, with page scripts disabled and no network/native bridge. Source is passed
as an argument, not interpolated into code. Swift serializes jobs, bounds source/output
and caches, and resets the worker on cancellation/deadline. New workers clear engine
readiness so a failed process cannot reuse stale JavaScript state. Mermaid stays strict,
with HTML labels disabled as in the original configuration; remote assets and executable
callbacks are excluded. Graphviz supplies readable light/dark defaults and retains safe
source-authored colors/attributes. Scripts, unsafe links/resources and unsafe SVG/CSS
output are rejected or neutralized by the engine and validation boundary.

Live preview diagrams use supported shadow hosts, separating CSS/IDs between repeated
diagrams. Each appearance gets distinct identifiers. Unchanged diagram keys preserve
actual SVG identity through preview patches. Portable exports use ordinary inline SVG
with unique instance IDs and root-scoped engine styles, so pasting a fragment via
`innerHTML` works without declarative-shadow parsing or runtime engines. Animation names
are prefixed. Both HTML forms adapt to appearance; print/PDF use the light variant.
Mermaid math labels reuse bundled KaTeX fonts. This also fixes ordinary equation clipboard
fragments: font/layout CSS now accompanies math when no document head is available.

Validation: **169 tests in 34 suites**, eight native arm64 test executables, native app
build-for-testing, changed-file strict Swift formatting, script syntax and first-party diff checks.
Vendored bundles/notices retain exact upstream whitespace and verified checksums.
Native integration covers all nine engine choices, Unicode labels, flow/sequence/gantt
and math labels, independent preference migration, source positions, disabled/fallback
paths, caching, active cancellation with queued recovery, timeouts, unsafe links/SVG,
repeated diagram isolation, both appearances, stable live SVG identity, portable and
pasted fragments, equation clipboard fonts, and real native PDF labels/surrounding text.
Both native appearance snapshots were visually inspected. Engine archives, resource
hashes, licenses and corresponding source notices are reproduced/verified by tooling.
See `validation/offline-diagrams.json` and `design/notebook/DiagramDemo.md`.

This is a renderer increment, not complete migration parity. Mermaid plugins/icons,
remote images, scripted interactions, every upstream diagram type and every historical
syntax/version difference are not claimed verified. Direct desktop Settings/keyboard/
VoiceOver/IME acceptance is still pending the existing unlock request; the Mac was
observed locked, and hosted rendering tests do not establish those gates. XCUITest still
only compiles in this environment. Large/adversarial performance, custom styles/templates,
MathJax-only compatibility, remaining editor/integration/release work and progressive
legacy retirement remain open. No production install, default-handler change or further
legacy subsystem deletion occurs at this gate. The full Snowfolio goal remains active.


## Highlight/superscript dialects and parser visibility — 2026-11-06

The original `extensionHighlight` and `extensionSuperscript` keys now migrate and
persist independently, preserving explicit false and defaulting off. Settings enable
`==highlight==`, bare `x^2` and parenthesized `x^(a + b)` syntax. Swift cmark extension
callbacks build owned `.highlight`/`.superscript` AST values and semantic `<mark>`/`<sup>`
output. Native inline parsing handles child emphasis, code, references, footnotes and
escaping. Parenthesized spans use the native delimiter stack, so multiline source and
following Unicode/CRLF coordinates stay intact. Bare spans reuse the same parser's
reference map. Source text/bytes are never rewritten by rendering.

Highlight grouping includes adjacent runs such as `==a====b==` and retains the original
non-nested highlight behavior. A temporary, native arm64 build of exact Hoedown 3.0.7
captured 20 characterization examples; `Tools/characterize-inline-dialects.py` reproduces
them. The comparison permits CommonMark's existing paragraph-end space normalization.
The old engine's malformed `^()`/unclosed and nested-superscript deletion bugs are
intentionally corrected: source markers/text remain visible rather than losing authored
content. Broader historical Markdown-version differences are not claimed eliminated.

The original **Format → Highlight / ⌘=** command is integrated, selection-preserving and
undoable as one native transaction. It follows the setting and native focus/composition
availability. TextKit 2 highlights are disposable rendering backgrounds, including inside
nested strong/emphasis spans, and never enter text storage or change layout/undo/source.
Preview highlights use adaptive quiet yellow surfaces and inherit text color; tested
light/dark contrast is at least 4.5:1. HTML/PDF/print use the same semantic markup. Source
superscripts remain ordinary editable Markdown, without changing source glyph metrics.

Bare superscript bodies are bounded to 64 KiB, recursive inline parsing to 32 levels,
and native delimiter lookback to 128 records. Each inline container indexes whitespace
and parenthesis boundaries once; malformed long tokens do not rescan a whole paragraph
for every caret. Reaching a limit leaves remaining markers as text with a preview notice.
The 500-case deterministic malformed corpus and long/deep inputs pass. These are resource
bounds and regressions, not a replacement for M6's representative performance measurements.

### Native parser packaging correction

The malformed corpus exposed `swift-cmark`'s Apple attributed-string grammar (`^[...]`),
which is outside the requested CommonMark/GFM and original MacDown syntax. Its reference
matching can consume text without rendering it. This occurs before Swift receives the
AST, so a rendering-only correction cannot recover every lost segment.

The same maintained **swift-cmark 0.9.0 / 08ddb528923cc1a6527e02b7a1aee9e516ca749a** now
builds through local `Packages/MarkdownEngine`. An integrity-pinned release archive supplies
76 original source/license files. Exactly two preprocessor directives make the attribute
inline case conditional on `CMARK_DISABLE_ATTRIBUTES`; the Swift manifest opts out.
All other native source is byte-identical to that release. This is an explicit, minimal
third-party C configuration exception; application orchestration, dialects, editor/UI and
the package manifest stay Swift. No new first-party C Markdown implementation is introduced.
The public native parser APIs, footnotes, GFM, math/diagram adapters and source mapping
remain on the same version. Ordinary Markdown links after a literal caret work normally.

`Tools/vendor-cmark.py` reproduces the source and manifest. `Provenance.json` stores original
and packaged hashes; `Tools/verify-markdown-engine.py` verifies every source, the exact
reversible two-directive patch, unexpected-source detection and the unchanged bundled
COPYING notice before native builds/tests. The SwiftPM lockfile continues pinning Yams;
the cmark source revision is now recorded in the local package provenance. Ordinary builds
need no parser download. Local `.build` artifacts are excluded from the provenance set.

### Verification and remaining gates

**182 tests in 36 suites**, eight native arm64 test executables and native app
build-for-testing passed. The nine inline-dialect tests also passed under AddressSanitizer,
covering native delimiter/node lifetimes, 500 malformed combinations, long/deep source,
legacy fixtures, Unicode/CRLF, references, raw HTML/destination safety, code/image scopes,
and composition with front matter, callouts and math. Native integration verified
command enablement, selection and undo/redo, temporary source backgrounds with unchanged
text storage, both appearances, semantic geometry/contrast and actual paginated PDF text.
Both native snapshots were inspected. Changed Swift formatting, first-party diff checks,
script syntax and parser provenance/notice checks passed. See `validation/inline-dialects.json`.

An additional audit ran all **652 official CommonMark 0.31.2** examples against a temporary
CLI built from the same packaged native source. **641 pass; 11 differ**. A second CLI from
unmodified 0.9.0 produces identical differences: overlong numeric entities, Unicode currency
punctuation around emphasis, and nested strong flattening. `Tools/check-commonmark.py`
records every mismatch and exits nonzero; it does not ignore the inherited cases. The
summary is `validation/commonmark-core.json`. Fix these before claiming full standards
conformance; the CLI audit alone also does not establish full app-renderer conformance.

Remaining dialect work includes underline, quote, fenced-code/intraword-emphasis choices,
other historical extension differences and the documented MathJax gaps. Custom source
styles/CSS/templates, editing accessories, broader productivity/macOS integrations,
measured performance and release/install/default-handler gates remain open. Actual
Settings/keyboard/VoiceOver/IME desktop acceptance and XCUITest execution retain their
existing environment gates. No further legacy subsystem is deleted: the original target
still consumes its renderer, highlighter and formatting resource references. Continue
retirement when the coupled features reach parity. The full Snowfolio goal remains active.


## Published CommonMark corpus — corrected and verified increment

The 11 inherited differences recorded in the previous increment are now corrected.
All **652/652 published CommonMark 0.31.2 examples** pass, with exact HTML comparison,
using the `cmark-audit` development executable linked to the same packaged native parser.
The checker still fails on every mismatch and verifies the published fixture checksum;
no cases, nested tags or entity text are normalized away to obtain this result.

Three upstream CommonMark/cmark 0.31.2 behaviors are backported into swift-cmark 0.9.0:
seven-digit decimal/six-digit hexadecimal reference limits; Unicode punctuation-or-symbol
classification for emphasis flanking; and preservation of nested `<strong>` elements.
Source release `eec0eeba6d31189fd828314576494566d539b1e3` and its archive hash are pinned.
The Unicode routine retains the existing exported function name for API compatibility.
These are maintained third-party C backports, not another first-party Markdown parser.
First-party application integration, dialects and audit command stay Swift. The existing
attribute-grammar configuration gate remains in place.

`Tools/vendor-cmark.py` now accepts both pinned archives and records exact reversible
replacements in `Packages/MarkdownEngine/Patches.json`, with upstream hashes/origins in
`Provenance.json`. Every other native source file stays byte-identical to 0.9.0.
`verify-markdown-engine.py` checks packaged hashes, reverses each patch to prove its original
hash, rejects unexpected source files and verifies both original distribution notices.
The complete CommonMark COPYING notice (BSD and component MIT notices) is preserved in
the package and app. Native packaging compares both shipped parser notices byte-for-byte.

`Tools/validate-commonmark.sh` builds the development-only `cmark-audit` executable from
this exact local package, verifies arm64, then runs all official fixtures. The fixture
file is supplied explicitly and checksum-checked; ordinary app builds and runtime need
no spec download. The audit target is not linked into the application. The existing
hosted workflow now triggers for all package/tool changes and runs this full corpus check
as well as the package/native-app jobs. The official `xcode-27` arm64 runner label was
checked against actions/runner-images. Parser/package logs and native `.xcresult` bundles
are retained for seven days with the checksum-pinned official artifact action.

App-facing regressions verify the corrected AST/HTML nesting, decimal/hex bounds, literal
code handling, currency/emoji/letter flanking and fresh styled/plain exports. Validation:
**186 tests in 37 suites**, eight native arm64 test executables, native build-for-testing,
**652 official corpus examples**, and **12 AddressSanitizer tests in two suites** all pass.
Changed Swift formatting, script/workflow syntax, first-party diff checks and source/
notice provenance checks passed. The published corpus summary is updated in
`validation/commonmark-core.json`; broader evidence is in `validation/commonmark-backports.json`.

Read-only inspection also confirmed successful hosted `native-app` and package jobs for
prior commit `62344f7` (run `42346495525`). That workflow actually invokes the native
`xcodebuild test` path for the three checked-in document lifecycle UI methods. The local
UI automation limitation therefore does not establish a universal runner blocker. New
retained result bundles will provide method-level evidence; do not infer tests for
settings, tabs, real IME or VoiceOver from the three lifecycle methods. Local direct
user-desktop checks remain a separate acceptance gate.

This closes the **11 published core-corpus differences**, not the full modernization or
every normative/Unicode/GFM/app-rendering case. Optional extensions, application safety
filtering, heading/navigation decorations and exports have their own integration gates.
Underline/quote/fence/intraword choices, custom themes/templates, productivity/macOS
features, measured performance, real input/accessibility and production release/install/
default-handler work remain required. The original renderer still has coupled legacy
target consumers; no additional legacy files are deleted here. The full Snowfolio goal
remains active.


## Hosted document evidence and project audit — 2026-11-06

The exact retained results for commits `997baa4` and `715565c` now establish three
and four passed native document UI methods, respectively, with zero failures/skips.
The latter adds preview accessibility publication after editing and native Undo,
including disappearance of stale checkpoint text. Both hosted package runs pass
186 tests/37 suites and all 652 published CommonMark examples. The result bundles
identify arm64 macOS 27.0.1 virtual machines. The latest screenshot confirms restored
source/outline, but its preview pixels are blank; do not claim compositor/visual proof
from accessibility existence alone. Direct desktop paint checks remain required.
Five/seven priority-inversion warnings remain unattributed. Exact scope and evidence:
`validation/hosted-document-ui.json` and `validation/commonmark-backports.json`.

The user additionally requested a project-wide cleanup and performance audit, with
confirmed obsolete/duplicate files moved to recoverable Trash. Ten old generated
build/cache folders and the unused Xcode 10.1 Travis pipeline/uploader were retired.
The verified native GitHub workflow replaces the obsolete build check. Localization
resources/manual import, all licenses, icon-resolution assets and still-coupled legacy
application code remain. The cleanup manifest preserves recovery paths. No user
documents, current app build, current validation evidence or unrelated projects moved.

A new development-only Release audit measures the actual core render/syntax pipeline
at 100 KB, 1 MB and 10 MB across three workloads, with Instruments CPU sampling.
See `PERFORMANCE_AUDIT.md` and `validation/performance-baseline.json`. The 10 MB mixed
case still takes about one second warm and peaks near 979 MiB; cold highlighting adds
significant first-render cost. These are required optimization follow-ups, not a pass
for M6's UI typing, preview-publication, memory-growth or energy targets. The full
Snowfolio modernization goal remains active and incomplete.


## List selection seam — 2026-11-06

The user's numbered-list edge was reproduced in the live reading preview. Matching
selection in the observed default-font native source editor did not reproduce it;
preserve that distinction because the user identified the source editor.

A first opaque-highlight experiment passed a color-overlap test but did not remove
the visible native-marker edge. It was withdrawn. The final correction uses positioned
CSS list-item counters for ordinary decimal markers, retaining semantic ordered lists,
automatic numbering and hanging indentation. It visibly removes the seam after relaunch.
Normal system selection colors remain. Authored type/style attributes and ordered task
checkboxes retain their original marker behavior; no document bytes/HTML list structure
or browser security policy changes. Active-selection WebKit snapshots omit selection,
so direct CUA observation supplies the visual check.

Native WebKit tests in both appearances compare selection text with the native-marker
baseline, preserve non-one starts, wrapping/list-item semantics and selected node identity
through font/size updates, and check Roman-marker/task-checkbox exclusions. The earlier
canvas test hit a VM readback exception; requesting CPU readback passed hosted run
`42350551251`. That intermediate color test is replaced by final behavior/geometry checks;
it is not used to claim the native-marker edge fixed. See `validation/list-selection.json`.
The full modernization goal remains active and incomplete.


Final direct desktop verification of the list fix also covers a multi-paragraph,
wrapped list starting at 4, nested numbering starting at 7, list accessibility
containers and task checkboxes. The internal padding was moved to the margin to
avoid an unselected vertical strip beside loose paragraphs; the original text edge
is preserved. Standard system selection colors remain. Automated cases cover both
compact/loose forms in light/dark appearances. The original source bytes are unchanged.


Final marker commit `22be23e` passed hosted run `42351600131`: downloaded evidence
confirms **187 tests / 38 suites / eight arm64 executables** and **652/652** published
CommonMark examples. The independent native build/document UI job also passed. Direct
post-relaunch list selection was observed clean on this Mac. Broader modernization,
real VoiceOver/IME, remaining feature parity and performance/release gates remain open.


## Fenced-code preference — 2026-11-06

The original `extensionFencedCode` key now migrates and persists, defaults on, and
preserves an explicit false. The native Markdown Settings switch changes actual block
parsing. Disabling it leaves backticks/tildes to ordinary native inline/block grammar;
indented code still works. Source syntax, preview and fresh exports share the option.
Fenced math/Mermaid/Graphviz also stop being special blocks, while independently
enabled inline math remains available. No source-text rewriting is introduced.

The pinned parser has a small local runtime configuration extension: public bit 22
`CMARK_OPT_NO_FENCED_CODE` guards the existing fence recognizer in `src/blocks.c`.
It is explicitly a Snowfolio API addition, not an upstream swift-cmark API. This adds
no replacement grammar or native ownership logic; all parsing continues in the maintained
engine, and the bit is absent under default CommonMark behavior. The header/conditional
patch is an explicit third-party configuration exception. All application preference,
UI, orchestration and tests remain Swift. The vendoring tool regenerates both changes;
provenance hashes and reversible patch checks still prove all 76 original files.
Original notices and the three upstream CommonMark backports remain unchanged.

`Tools/characterize-fences.py` records 20 cases from original Hoedown 3.0.7, including
both fence characters, nesting, indented/inline code, longer fences and Unicode/CRLF.
The comparison explicitly accounts for CommonMark's inline-code newline/space rule.
Two existing enabled-fence differences retain both exact outputs: paragraph interruption
and a fence immediately after a list marker. No cases or markup are ignored. Malformed
fences follow CommonMark, including unclosed fences when enabled; source remains visible
when disabled. These are standard grammar differences, not claims of bit-identical
Hoedown HTML for every input.

Migration, per-render switching, syntax/source coordinates, code scope and special-renderer
boundaries are covered. Styled/plain HTML and actual native PDF/print output verify fresh
settings, including manual-preview snapshots. The default engine still passes all 652
published CommonMark examples. Native UI inspection observed the switch and an on-to-off
transition with the initial code-block preview. The UI connection then timed out, so the
post-change desktop preview/round trip is not claimed from that attempt. A one-second
stack sample found the main thread idle in its event loop; the timeout cause is not
attributed. The saved preference was restored to its observed original on value. A new
hosted UI method exercises the actual Settings switch, both preview transitions and
unchanged source. See `validation/fenced-code.json` for the exact validation state.

Underline, quote and intraword-emphasis choices, custom styles/templates, remaining
editor/workspace/integration capabilities, real input/accessibility, performance/release
readiness and progressive legacy retirement remain required. The original renderer still
has coupled consumers; this increment does not delete it. The full goal remains active.


### System Settings parity — requested 2026-11-07 (in progress)

Rebuild Snowfolio Settings around the actual System Settings UI on this Mac:
searchable sidebar, category/detail routing, back/forward history, native grouped
rows, switches/popups, descriptions, adaptive window chrome and scroll edges.
Preserve all preference choices, stored keys and their real editor/preview/export
effects. Verify search-to-row, navigation, resizing, reopen and persistence; retire
the replaced toolbar-tab implementation after validation. The full modernization
goal remains active.

The replacement now builds and runs with all 38 existing preferences. Search
reveals rows within the actual native grouped Form, including the disabled inline
equation option at the bottom of Markdown. The native sidebar divider matches the
reference at 231.5 pt in a 740×625 pt window. Search/navigation/persistence tests and
the full package pass (197 tests / 40 suites / eight arm64 executables). Native
build-for-testing and strict formatting pass. Final live checks and hosted native
UI execution remain pending; evidence is in `validation/settings-redesign.json`.


The final presentation has now been checked on this Mac: all five panes, native
font popup/cancel, keyboard back/forward, long-result wrapping, empty search,
search-to-row, zoom/restore, close/reopen and a real fence preview off/on round trip.
The original enabled setting and exact fixture text were restored. System Settings
was left on General with empty search; no system preference value was changed.

The hosted run exposed a real cold-open window placement bug on a 1024-point
display. Automatic hosting sizing reduced the initially sized window to 1×84 pt
before its first layout, so centering used the wrong width. Shared minimum form
dimensions, explicit native content sizing and disabled hosting auto-sizing now
keep the initial frame stable. Pure display-bound checks cover small/negative-origin
displays; the actual cold native window regression failed before the final fix and
passes after it. All 199 package tests / 41 suites / eight arm64 executables and the
native build-for-testing pass. Final hosted UI result is being recorded separately.

Hosted acceptance for the corrected Settings window is complete: run
[42357907672](https://github.com/jiangshen/snowfolio/actions/runs/42357907672)
on `0d38f7fc4204c1ddd3a29dd451561d00eb8f9e21` passed both jobs, including
all six native document UI tests, the actual fence Settings/preview round trip,
search/history/popups/every-category visibility/reopen, 199 package tests and the
652-example core parser audit. The wider modernization goal remains active.

### Tab-to-document transition — requested 2026-11-07

The screenshot showed the split divider visually meeting the tab strip. The native
tabs now sit above an inset writing surface with 12 pt top separation, 10 pt side
and bottom gutters and 12 pt outer corners. The standard native split view draws
its rule with 18 pt top/bottom insets and rounded ends; resize tracking and native
divider accessibility stay with NSSplitView. The existing editor/preview hosts and
document state remain intact. Direct desktop checks verified both tabs, all three
workspace modes, the restored split fraction, source selection and exact text.
Native app build-for-testing and 16 focused editing/pane/scroll tests passed; hosted
verification of the combined final change follows.

Combined final acceptance passed on `e15ebfc0f8b346028cdd20cd9c8b3f8b77dffd9d`:
[42358487380](https://github.com/jiangshen/snowfolio/actions/runs/42358487380)
passed both jobs, all six native document/Settings UI tests, 199 package tests in
41 suites, eight arm64 test executables and all 652 core CommonMark examples.
The updated writing surface is running on this Mac, with the original document
text/selection and split mode restored. Full modernization remains active.


### Current writing surface — edge-to-edge refinement (2026-11-07)

The user superseded the inset-card design and requested both panes extend all the
way, with no gaps around the preview's rounded surface. Removed the workspace
outer padding/rounded clipping and the custom inset divider drawing. Both panes
now fill the native content area, and the standard NSSplitView divider runs the
full height. The native window's own corners and tab controls remain system-owned.
The unused custom divider implementation was removed. Native build-for-testing,
16 existing editing/pane/scroll tests and direct desktop inspection pass. The
current geometry and historical inset design evidence are recorded separately in
`validation/writing-surface.json`. This change does not alter document text.

Hosted run [42359928178](https://github.com/jiangshen/snowfolio/actions/runs/42359928178)
for `db6c5a2` passed both native-app and swift-foundations jobs, including the
complete core CommonMark check. This result applies to the current edge-to-edge
geometry; the preceding inset-card entry is historical.


## Optional underline compatibility — 2026-11-07

**Underlines** now preserves the original `extensionUnderline` choice, defaults off,
and restores `_text_` as semantic `<u>` output when enabled. The same option controls
preview, temporary source syntax, fresh HTML and native PDF/print. Double/triple
underscore choices and intraword underlines follow original Hoedown behavior; disabled
mode retains established CommonMark underscore grammar. Stars still provide emphasis.
The Settings catalog now contains 39 preferences. Format → Underline (⌘U) follows the
setting and native editor focus/composition state. It preserves Unicode selection and
uses one native undo/redo step. Applying it inside `__bold__` uses equivalent star-bold
markers so triple underscores do not accidentally turn bold into emphasis.

`MarkdownDelimiterExtensions.swift` owns the compatibility grammar. It parses children
through native cmark with shared references, keeps native code/HTML/destinations opaque,
and preserves image-description marker behavior. Its span-search semantics derive from
Hoedown 3.0.7; the original ISC notice is bundled and checked during native builds.
No regex/source rewriting is used. A small, generic opt-in `match_inline_before` callback
bridge is a documented local native-parser API, not an upstream API. It permits Swift
extensions to handle built-in delimiters before native token dispatch and retains native
multiline position accounting. A native context correction prevents extension-created
link subtrees from becoming nested anchors, including existing superscripts. These are
explicit, reversible third-party parser integration exceptions to the Swift application
rule; the underline grammar itself remains Swift.

The matcher limits recursive parsing to 32 levels, span bodies to 65,536 bytes and scan
work to max(65,536, source byte count × 16). Long literal underscore runs are consumed in
chunks. Unsupported oversized spans retain visible source and publish the existing
complex-formatting notice. These bounds do not establish typing latency or whole-app
memory/energy acceptance. General underscore editing inside arbitrary preformatted
selections is not a semantic markup refactoring tool.

Validation: all 84 original Hoedown characterization cases pass with 16 explicit native
differences, all 652 core CommonMark examples pass, 208 package tests in 42 suites pass,
and eight test executables are arm64. Seventeen parser/dialect/conformance tests pass
under AddressSanitizer. Native build-for-testing, strict changed-Swift formatting,
source/notice verification, exact reproduction of all 80 generated parser/package files,
and exact characterization reproduction pass. Native checks cover light/dark preview,
current/manual export snapshots, styled/plain HTML, native PDF text, source attributes,
Unicode selection, undo/redo and focus/marked-text/preference gating. Direct desktop
checks verified the Settings switch, preview round trip, bold selection with ⌘U, undo
and disabled command. Original underline preference was restored off, the disposable
unsaved document was discarded, and the original tabbed workspace returned to the front.
Hosted verification for this increment is tracked in `validation/underline.json`.

A live source-color refresh quirk was observed around the preference/undo round trip:
source colors briefly stayed stale or cleared until a later native edit, while preview
and source bytes were correct. Targeted same-revision color transition/storage/undo tests
pass, but do not reproduce that visible repaint sequence. Keep the live presentation
acceptance gate open; do not claim this observation fixed or dismiss it as parser parity.

Remaining work includes quote and independent intraword-emphasis settings, custom
styles/templates, other editor/workspace/productivity and system integrations, real IME
and VoiceOver gates, measured native performance, release/signing/notarization/install
and default-handler readiness, and safe retirement of the coupled legacy target.
The complete modernization goal remains active.


Hosted run [42362496518](https://github.com/jiangshen/snowfolio/actions/runs/42362496518)
for `27bc74d` passed both jobs. Downloaded evidence confirms all seven native UI tests
(including the actual underline Settings/preview/⌘U/undo/redo/disabled-command sequence),
208 package tests in 42 suites, eight arm64 executables and 652/652 core CommonMark
examples. The native log still emits priority-inversion diagnostics; the existing
performance attribution gate and live source-color repaint observation remain open.
This is a verified development increment, not release readiness or full-goal completion.


## Live source repaint and optional quoted text — 2026-11-07

Changing an inline dialect in Settings could update the AST and preview while the
source view kept its previous painted colors. The defect was reproduced directly:
underlines enabled in preview, but their source remained orange emphasis until another
native edit. Fresh offscreen drawings and rendering-attribute checks alone did not
expose that retained live surface. The highlighter now sends an attributes-only
`NSTextStorage.edited` notification for the existing viewport after publishing current
rendering attributes. It changes no stored attributes, text, source revision or undo
state. The notification is bounded to a valid visible UTF-16 range, guarded against
reentrancy and omitted while marked text is being composed. No private API, font-trait
mutation or synchronous forced display is added; the notification names only the
existing viewport.

A complete-workspace regression covers inactive preference changes, orange/teal/orange
source presentation, Unicode formatting and undo/redo. A separate XCUITest now examines
pixels from the actual source UI screenshot before another edit; it does not substitute
`cacheDisplay` for the live surface. Direct desktop verification confirmed the corrected
source colors in both directions, native undo/redo, unchanged source and the original
underline choice restored off. The disposable document was closed and the original
existing two-tab workspace returned to the front. See `validation/source-syntax-refresh.json`.

**Quoted text** restores `extensionQuote`, defaults off and adds the fortieth Settings
entry. It renders original double-quoted spans as semantic `<q>` nodes; it is independent
of smart punctuation and composes with underlines, highlights, superscripts, references
and footnotes. Code, image descriptions, HTML tokens and destinations keep their native
scopes. Empty/unclosed markers remain visible; outer spaces/tabs are trimmed inside a
recognized quotation. `MarkdownDelimiterExtensions` owns this grammar in Swift and
retains the existing original Hoedown ISC notice. The existing upstream internal scanner
API marks double quotes as boundaries for this parser only, without taking ownership of
native smart-quote delimiter processing. No additional native C patch is introduced.

All 80 original Hoedown quote-choice fixtures pass with nine explicit native differences:
literal default-mode tabs, equivalent void image syntax, normal CommonMark paragraph
trimming, existing heading anchors and active-script filtering. The fixture is reproduced
exactly by `Tools/characterize-quote.py`. The same recursion/body/work caps apply to
both optional delimiter grammars. Quote-run inspection itself consumes the work budget,
and exhausted optional quote matching yields to native literal/smart-quote handling.
The adversarial 100,000-quote fixture retains every marker without repeated unbounded
rescanning. These checks do not establish native typing p95 or whole-app performance.

Local validation passes: 214 package tests in 43 suites, eight arm64 test executables,
652/652 core CommonMark examples, 21 AddressSanitizer parser tests in four suites,
native build-for-testing and strict changed-Swift formatting. Native light/dark preview,
styled/plain HTML, fresh manual-render snapshots and paginated PDF/print checks include
quotations; both appearance snapshots were inspected. Direct Settings checks exercised
the quote switch and source/preview change, then restored the original off value.
Hosted acceptance is tracked in `validation/quoted-text.json`.

Independent intraword-emphasis choice, custom themes/templates, remaining editor and
workspace productivity/system features, real IME and VoiceOver gates, measured native
performance, shipping/install/default-handler readiness and safe coupled-source
retirement remain outstanding. The full modernization goal remains active.


Hosted acceptance passed on `eedaf69ca9bf4089e6dd9c9852f1a17491a3fd13`:
[42366413412](https://github.com/jiangshen/snowfolio/actions/runs/42366413412)
completed both jobs successfully. Downloaded artifacts confirm 214 package tests in
43 suites, eight arm64 executables, all 652 published CommonMark examples and seven
native document/Settings UI tests with zero failures. The underline test now checks
teal source pixels from the actual UI screenshot before another edit, and passes with
the paragraph presentation notification. The previously recorded live source-color
refresh gate is closed for this reproduced Settings/undo sequence. Broader real IME,
VoiceOver, native performance and release gates remain active; no full-goal completion
or release-readiness claim follows from this increment.


## Independent word-formatting choice — 2026-11-07

The native Markdown settings now include **Formatting inside words** with Standard
Markdown, Allow and Avoid. The first preserves native CommonMark/GFM behavior; the
latter two restore both original `extensionIntraEmphasis` choices across stars,
underscores, bold/triple emphasis, optional underline/highlight and strikethrough.
The authoritative new `markdownEmphasisPolicy` string permits an explicit return to
Standard without losing to an older Boolean on the next launch. Existing true and
false choices migrate independently; fresh profiles default to Standard. Settings
search reveals the menu and the catalog contains 41 entries.

The existing Swift delimiter matcher owns only the selected compatibility grammar.
Native child parsing retains references, footnotes and security filtering; no source
rewriting or additional C patch is introduced. Its shared recursion/body/work caps
still apply (32 levels, 65,536 body bytes, max(65,536, sourceBytes × 16) search work).
The original Hoedown ISC notice remains bundled. The 276 original fixtures cover 69
sources, both word policies and both underline choices. Ten explicit differences retain
native fence grammar, unfinished link-label behavior and equivalent XHTML image tags;
there are no skipped fixtures. The capture tool reproduces the fixture byte-for-byte.

Local validation passes 223 package tests in 44 suites, eight arm64 executables and all
652 CommonMark examples. Export checks cover styled/plain HTML, current options captured
while preview rendering is manual, and native PDF/print in all three policies. PDFKit
extracts baseline underscores after adjacent letters, so its checks preserve marker
counts as well as all document letters. Deterministic malformed-input checks disable
fences to isolate inline letter preservation from legitimate code-fence metadata.
Large inline runs and oversized bodies remain visible with bounded fallback.

Direct desktop checks observed Allow → Standard → Avoid → Allow changing both displayed
source colors and preview without changing source. The original Allow value and the
original two-tab workspace were restored; only the temporary check draft was discarded.
The source/preview surfaces still extend flush to the window edges without inset gaps.
Native UI automation includes a picker search/reveal and round-trip regression, and
explicitly sets Standard in the existing underline test to avoid preference dependence.
Hosted and sanitizer evidence is tracked in `validation/intraword-formatting.json`.

Custom themes/templates, remaining editor/productivity/system features, document and
accessibility acceptance, measured performance, release/install/default-handler gates
and progressive coupled legacy retirement remain open. The full goal stays active.


### Hosted word-formatting acceptance

Run [42369063894](https://github.com/jiangshen/snowfolio/actions/runs/42369063894),
code commit `5934a8464bb9ea5559eda10fa47f61cf0d0e82fa`, passed both jobs. Downloaded
artifacts confirm 223 tests / 44 suites, eight arm64 executables, 652/652 CommonMark,
and all eight native UI tests. The picker round trip and existing source repaint
regression both pass. Fourteen priority-inversion warnings remain recorded without
claiming a first-party cause; the native performance attribution gate stays open.

## Mixed-list selection and alignment follow-up — 2026-11-07

The user's new screenshot was reproduced in the actual reading preview on
`editing-lists.md`: selecting from numbered items into a bullet exposes a small native
WebKit marker rectangle. The previous correction covered only decimal markers.
Numbers also had only a .15em gap before text, while bullets used native spacing.

Ordinary unstyled numbered and bulleted lists now share a .5em marker-to-text gap,
a common hanging text edge, and positioned generated markers. This removes the
remaining native bullet marker selection seam while preserving semantic ol/ul/li,
list start values, selected text and wrapping. Native nested circle/square
appearances are retained. Explicit type/style/class lists, individually styled items
and task checkboxes keep their own marker behavior. Property lists are excluded.

The existing native selection regression now selects across both kinds of list and
checks light/dark, compact/loose paragraphs, wrapped text, marker spacing, shared text
alignment, nested bullets, authored styles and node/selection identity through a
font/size change. Direct desktop checks reproduced the seam before rebuilding and
confirmed it gone afterward, with aligned First/Second/dfdfd text and a clearer number
gap. The user's current source bytes and original tabs were preserved. Evidence and
final hosted state are tracked in `validation/list-selection.json`.


### Hosted mixed-list acceptance

Run [42369808017](https://github.com/jiangshen/snowfolio/actions/runs/42369808017),
code commit `c5cfb6c41d2d85b15c0e5ef6c1947c70715b2b04`, passed both jobs. Downloaded
artifacts verify 223 package tests / 44 suites, eight arm64 executables, all 652
CommonMark examples and eight native document UI tests with zero failures. The
mixed-list light/dark and compact/loose cases pass in the package job. Exact native
runtime warning counts remain in the ledger; this does not close M6 attribution.
The full modernization goal stays active.


## Editor-theme grammar foundation — 2026-11-07

Custom styles remain an essential open gate. Inspection confirms the original `.style`
format includes editor/background/caret/current-line/selection colors, RGB and ARGB,
per-element colors, absolute/relative font sizes, font families and combined bold,
italic and underline traits. A color-only selector would silently lose behavior, so
no theme selector is exposed until native rendering can honor the whole model.

`EditorCore.EditorTheme` is now a data-only Swift reader for the complete original
selector/attribute vocabulary. It preserves duplicate scalar ordering, combined font
traits, repeated special-editor rule replacement, case-sensitive names, custom
attributes, UTF-8 BOM and CR/CRLF handling. Legacy px/pt suffixes both still mean points.
Diagnostics report line numbers and parsing recovers at blank-line block boundaries.
The reader performs no Markdown parsing, document edits, font lookup or I/O.

The development capture tool compiles the unchanged vendored style parser plus its
byte-identical name-table functions in a temporary directory. All five compiled
source/header inputs have checksums in the fixture. No original parser is added to
the shipping target. All 15 bundled themes plus six explicit grammar fixtures match
the original output, without skips. Repeated captures reproduce identical JSON.
The complete PEG Markdown Highlight notice remains bundled under its MIT option.

Malformed inputs intentionally have safe modern bounds: 1 MiB source, 4,096 blocks,
16,384 declarations, 256 diagnostics and signed font integers within ±4,096. NUL
and excessive complexity fail explicitly. Colors require exact hexadecimal digits;
empty names/values are diagnosed rather than inheriting the original parser's unsafe
empty-string behavior. These are import validation rules, not changes to Markdown.

All 227 package tests / 45 suites pass, with eight arm64 test executables. Native app
build-for-testing and strict formatting pass. The four new theme tests cover original
fixtures, malformed recovery, Unicode and relative-font values, and adversarial bounds.
This checkpoint is the grammar/model foundation only. Full selector-to-AST mapping,
actual native font/decoration/current-line rendering, custom theme catalog/import and
settings, custom CSS and template compatibility, live acceptance and legacy retirement
remain required. The new reader is not yet consumed by the app UI and is not claimed
as shipped theme support. Hosted checks are tracked in `validation/editor-themes.json`.


### Hosted theme-reader acceptance

Run [42371181242](https://github.com/jiangshen/snowfolio/actions/runs/42371181242),
commit `ced95cf942bbdeb22c7ab4d639ac854cafcc4810`, passed both jobs. Downloaded evidence
confirms 227 tests / 45 suites, eight arm64 executables, 652 CommonMark examples and
eight native UI tests. Fourteen runtime priority-inversion warnings remain recorded;
this does not establish their cause or close native performance acceptance.

## Native theme paragraph typography — 2026-11-07

The installed SDK exposes `NSTextContentStorageDelegate.textContentStorage` for custom
`NSTextParagraph` objects. A Swift 6 spike confirmed a real 30pt layout fragment with
the backing storage still at 14pt and no previous content-storage delegate. The native
editor now uses this public API when an explicit theme is supplied. It copies the
paragraph's attributed substring and applies theme fonts/colors to that copy, without
writing presentation attributes into `NSTextStorage` or the document/undo model.
Default appearance remains the existing temporary-color path until the full theme
feature is ready. The public editor value accepts an optional parsed theme, but there
is no user-facing catalog or picker yet.

Semantic source tokens retain six heading levels, nested emphasis, block/inline code,
explicit versus automatic URL/email links, images, quotes/comments, inline/block HTML,
rules and list marker types. Duplicate ancestor categories are suppressed, bounding
each token collection for deeply nested input. Native inline-code positions omit their
backticks; only AST-confirmed matching delimiter runs are added to presentation ranges.
Unicode, padded/multiline spans and surrounding prose are tested. No Markdown source
rewriting, regular-expression parser or new C patch is introduced.

`NativeEditorTheme` compiles scalar precedence and trait unions in original rule order,
resolves real native fonts with unavailable-face fallback, and applies zoom to absolute
and relative sizes. Global editor font attributes are now honored by the typed mapper;
the original view adapter applied only editor colors. Resolution is cached for up to
512 token combinations, and paragraph styling binary-searches only intersecting runs.
Parsed-theme identity stays stable across copies while value equality remains semantic,
avoiding a full imported-file comparison on each view update. Font presentation is
bounded at 8192pt, with the original 4pt minimum scaled by document zoom. Import UX must
surface relevant validation bounds before the catalog is exposed.

Native tests prove 30pt heading geometry, 16pt nested bold/italic/underlined text, 12pt
code including its ticks, 14pt restoration when disabling the theme, unchanged backing
attributes/source/selection/undo during styling, base-font typing and successful native
undo/redo. Programmatic Japanese marked text survives updates; stale snapshots cannot
restyle that changed paragraph. This is not real IME or VoiceOver acceptance. An initial
fixture crash came from inserting native text with event grouping disabled and no open
undo group; the fixture now opens/closes its group explicitly. No application workaround
or weakened undo assertion was added.

All 232 package tests / 46 suites pass, with eight arm64 executables and a successful
native arm64 app build-for-testing. Full raw logs and complete diagnostic capture are
retained by axbuild; strict changed-Swift formatting and parser provenance checks pass.
The paragraph tests exercise actual TextKit fragments, not only mapped attribute values.

Still required before exposing themes: HTML_ENTITY/REFERENCE/NOTE scope compatibility;
editor paper/caret/selection/current-line handling; catalog/import and saved choices;
visual, keyboard, real IME/VoiceOver and scrolling acceptance; measured large-document
performance; custom CSS/templates. Theme and old highlighter retirement stays open.
The full modernization goal remains active.


### Hosted native paragraph foundation

Run [42373303629](https://github.com/jiangshen/snowfolio/actions/runs/42373303629),
commit `7374e23cfc4b499300d55a9cd657807e64dabdf9`, passed both jobs. Downloaded
artifacts confirm 232 package tests / 46 suites, eight arm64 binaries, 652 CommonMark
examples and eight native UI tests. Thirteen priority-inversion warnings remain in the
native log; their attribution and native performance acceptance stay open.

## Remaining theme scopes and native prefix positions — 2026-11-07

`HTML_ENTITY`, `REFERENCE` and `NOTE` now reach typed source tokens and native theme
paragraph presentation. Entities use the existing native decoder inside AST-confirmed
text only, with 32-byte decode windows and cancellation checks. Code, HTML and link
destinations stay opaque. Recognized entities retain their heading/quote/emphasis/link
ancestry. Invalid names, excessive numeric digits and escaped ampersands follow native
CommonMark behavior rather than the old highlighter's broader matching.

Two documented opt-in metadata callbacks observe already-recognized native prefix
consumption and finalized block source positions. Neither adds Markdown grammar or
changes source bytes. Swift captures definitions before the native tree can discard or
relocate them. It reconciles a paragraph/heading origin before native inline parsing
when the remaining native line exactly matches the physical source suffix. This fixes
misplaced syntax after an immediately preceding reference definition, including setext
headings, without reparsing or disturbing native reference/footnote resolution. Source
bytes and line indexes allocate lazily and are reused by syntax generation.

The original `NOTE` selector emits no elements, even with its notes extension enabled.
Resolved native references and used/unused definition ranges now receive that selector.
Surviving note descendants retain native emphasis/code/entity scopes and original quote
ancestry. Default note body text keeps its text/quote role rather than being colored as
an entire link. Source metadata contains values only; no native pointers escape parsing.

The development capture regenerates and compiles the unchanged original highlighter in
a temporary directory. Nine fixtures preserve exact original source ranges, with explicit
reviewed native differences for invalid entities, escaped ampersands, grouped adjacent
reference spans and newly active note styling. A second capture reproduced byte-identical
JSON; no original parser enters the app. All build inputs are checksummed and attribution
is retained. Every local native patch reverses to the recorded unchanged upstream bytes.

Local validation: 239 package tests / 47 suites pass, including real TextKit fonts for the
three new scopes and unchanged document/backing attributes. Focused Address Sanitizer
source-scope/syntax tests pass with complete diagnostic capture and no diagnostics.
Strict changed-Swift formatting and native parser provenance pass. Native arm64 app
build-for-testing and all eight arm64 test executables are verified; the core CLI passes
652/652 pinned official CommonMark examples. Hosted results and exact local evidence
are tracked in `validation/editor-themes.json`.

This is not a claim of complete native source-coordinate correctness: lazy continuation
columns, partial-tab indentation and extension callback subcontexts retain a broader
acceptance gate. Global paper/caret/selection/current-line styling, catalog/import/saved
choices, real visual/keyboard/VoiceOver/IME/scrolling and measured large-document checks,
custom CSS/templates and coupled legacy retirement remain open. There is still no
user-facing theme picker. The full modernization goal remains active and incomplete.


### Empty reference-prefix follow-up

A focused regression exposed one additional native origin case: a paragraph containing
only definitions remains open when the next line resembles a setext underline. There
is no remaining buffered line to suffix-match. Swift now requires native current-line
number and complete byte identity before rebasing that empty paragraph to the native
first-nonspace column. The pre-fix test demonstrated incorrect paragraph/strong lines
and absent expected body syntax. The fix passes all three line endings and five
indentation/quote/list contexts, with plain/syntax-enabled outputs agreeing. No further
C patch or Markdown grammar was added. Final local validation is 240 tests / 47 suites,
13 Address Sanitizer source-syntax tests / two suites, and a successful native arm64
build-for-testing, with complete captures and no diagnostics. Other source-coordinate
and full theme/product acceptance gates above remain open.


### Hosted source-scope acceptance

Both pushed checkpoints passed. Downloaded run
[42376156626](https://github.com/jiangshen/snowfolio/actions/runs/42376156626), commit
`349470c7a6c8d0c9b52d6811565a19f8c126fa89`, confirms 239 package tests / 47 suites,
eight arm64 binaries, 652 CommonMark examples and eight native UI tests, with thirteen
priority-inversion warnings. Run
[42376569726](https://github.com/jiangshen/snowfolio/actions/runs/42376569726), commit
`3e72ca6f017165d3df24c14f55d273996562680e`, confirms 240 tests / 47 suites, the same
architecture/corpus/UI totals and twelve warnings. Runtime warning attribution remains
open; these successful runs do not establish native performance acceptance.

## Native theme surfaces and current-line foundation — 2026-11-07

Page and caret colors now use reversible view state. Selected foreground/background and
underline use the native temporary selection attributes; font/family/size remain ignored
for selection as in the original adapter and the SDK's no-layout-change contract. A
sparse replacement theme falls back to captured semantic defaults. Removing a theme or
detaching restores original editor/scroll colors, draw flags and selection attributes.
The scroll canvas paints page color once, including below a short document. Global page
background is no longer copied behind every character, avoiding double-alpha glyph boxes.

The original highlighter only stored `currentLineStyle`; no consumer was found in the
repository. Native current-line presentation is an improvement rather than a claim of
old runtime parity. A collapsed, non-composing caret activates one logical source line,
including its soft wraps. Its full-width color band uses cached viewport line geometry;
empty, blank and terminal LF/CRLF rows are covered. Nonempty offscreen ranges never
request new layout merely for their background. Selected/marked text suppresses the band.
A geometry-free path is used for caret motion within an unchanged line. Copied paragraphs
support authored current-line foreground/font/family/traits after semantic source styles;
the 512-entry attribute cache now distinguishes active and inactive line states.

Native tests prove moving 18/20pt paragraph fonts, restored sparse/default/detached states,
unchanged backing attributes/source/undo, Unicode/CRLF, six row-geometry cases, and retained
programmatic Japanese composition. Native bitmap checks prove uniform translucent paper
across margins/whitespace/row width and below short content, plus a consistent current-line
band across its width. An initial pixel assertion incorrectly assumed literal RGB values
after the host display/HDR profile conversion; the test now compares hue, contrast and
uniformity within the same captured color profile. No production workaround was added for
that fixture assumption. Changed-Swift formatting and unchanged parser provenance pass.
All 245 package tests / 48 suites pass with complete diagnostic capture and no warnings
or errors. Native arm64 app build-for-testing and eight arm64 test executables are
verified; AppKit review confirmed weak ownership, reversible state, saved/restored
drawing state and explicitly main-actor-isolated scroll restoration. Both package and
native Swift 6 build paths report zero warnings/errors. Exact evidence is tracked in `validation/editor-themes.json`.

The typography gate is still open: a 22pt native paragraph spike retained a 17pt extra
insertion line from the 14pt editor base; empty/terminal insertion and caret metrics need
resolution before theme selection/import is exposed. Catalog/persistence/validation UX,
real visual/keyboard/VoiceOver/IME and native scrolling/large-document measurements, broad
source-coordinate acceptance, custom CSS/templates and coupled legacy retirement remain
required. No user-facing theme picker is exposed. The full modernization goal stays active.


### Hosted surface acceptance

Downloaded run [42379207374](https://github.com/jiangshen/snowfolio/actions/runs/42379207374),
commit `ded3f5212152b01ccf479fb9ba04d29b550c8b99`, passed both jobs: 245 tests / 48 suites,
eight arm64 binaries, 652 CommonMark examples and eight native UI tests. Fourteen runtime
priority-inversion warnings remain recorded, with attribution and performance gates open.

## Native writing defaults and empty-line typography — 2026-11-07

The empty/extra-line metric gap is resolved through native writing preferences. Keeping
the native default font at 14pt while supplying a 22pt copied paragraph left the native
empty/terminal caret at 17pt high, versus 26pt in an ordinary 22pt NSTextView. Native
writing foreground also retained the previous system color, which could mismatch a
new theme page during composition. The highlighter now aligns native `font`/`textColor`
with the effective editor/current-line writing defaults and zoom. It queues page/caret/
selection and writing-style changes until marked text finishes, preserving a coherent
palette and the complete native preedit rather than modifying composition in progress.

This deliberately refines the earlier all-backing-attributes-unchanged invariant:
NSTextView's native default font/foreground preferences update uniform backing font and
foreground attributes. The document is still plain Markdown: source bytes, revision and
undo/redo do not change on style changes. Semantic heading/code/emphasis fonts, colors,
traits and backgrounds remain disposable paragraph copies. Tests now allow exactly the
native uniform writing preferences while still catching stored semantic span attributes;
theme removal restores original defaults. No custom input interception, Markdown source
rewriting or custom extra-line fragment implementation was introduced. Reentrancy guards
cover native preference setters, and viewport hooks surround font geometry changes.

A 48-case native/control matrix covers empty and nonempty text, terminal LF/CRLF,
editor/current-line rules, monospaced/Helvetica faces and 50/100/200% zoom. Native font
sizes and caret heights match an ordinary NSTextView using the intended font. Japanese
preedit keeps its marked range, selected range, full native attributes and palette during
a pending theme change. Typing and isolated-pasteboard paste preserve native undo/redo
across writing-default changes, including UTF-8 Unicode/CRLF and subsequent themed input.
Programmatic composition is not real keyboard IME/candidate-window acceptance.

The reference fixture's 96 animated windows initially exhausted the sampled 64-thread
dispatch soft limit with AppKit NSAnimation workers and starved diagram tests. After
capturing that state, the already-failing owned fixture process was stopped. Only the
new fixture windows now disable animation. The full rerun includes every diagram and
editor check. Exact font-size assertions use concrete CGFloat values to avoid mixed
optional CGFloat/Double macro comparisons; native reference-height assertions were
retained. No production workaround or skipped assertions were added for these fixtures.

All 248 tests / 49 suites pass. Native arm64 app build-for-testing, eight arm64 test
executables, strict formatting and unchanged parser provenance pass. Package and native
Swift 6 builds have complete captures with zero warnings/errors. Exact evidence and
hosted follow-up are in `validation/editor-themes.json`.

Next: theme catalog/import, saved choices and Settings validation, followed by actual
visual/keyboard/VoiceOver/real IME/resize/scroll and measured large-document acceptance.
Broader source-coordinate correctness, custom CSS/templates, safe coupled legacy
retirement and the other full roadmap gates remain required. No theme picker is exposed
yet. The full modernization goal remains active and incomplete.


## Theme catalog and Settings integration — 2026-11-07

The editor now consumes an app-owned observable theme library. Settings → Editor
provides Automatic, all 15 original bundled themes, read-only MacDown custom themes,
and imported `.style` files. The original saved name migrates without changing the
old preference domain. Explicit new Automatic takes precedence. Source theme search,
custom import and reload use the existing System Settings-style form.

A repository actor owns bounded regular-file reads and decoding. Imports preserve
raw UTF-8/BOM/CRLF bytes and the original file; content hashes deduplicate immutable
owned copies. An atomic directory rename publishes metadata and source together.
Import review identifies recoverable grammar problems, ignored fields, very large
fonts and unavailable native font faces. Damaged/missing selections keep the last good
appearance and display recovery guidance; reimport repairs a damaged owned copy by
recycling the old directory. No theme file is executed. Library-owned loading and
generation checks protect against canceled view waiters and stale selections.

Original theme assets/comments remain byte-identical. A reproducible verifier checks
all 15 SHA256 values and the retained MacDown license, including the built app resource
bundle. No coupled legacy implementation was removed at this checkpoint.

Local validation passes **259 tests / 52 suites**, eight native arm64 test bundles,
and an arm64 app build with zero compiler warnings/errors. The integration fixture
selects every bundled theme and an imported theme through the actual observable
SwiftUI/native editor wiring; editor identity, selection, source/revision and native
undo/redo survive, including restoration to Automatic. A hosted UI regression exercises
Settings search, the native menu, `.style` file panel, review, reopen and undo. Its
result is recorded separately in `validation/editor-themes.json`.

The Mac was locked during this checkpoint's direct visual check. Existing user tabs
and the Open panel were preserved; this is not a claim of fresh desktop acceptance.
The mixed-list selection/spacing correction from `c5cfb6c` remains in the current
build and its light/dark compact/loose regressions pass. Direct confirmation of the
user's running build still needs an unlocked desktop.

The preceding writing-typography commit `38b2e1f` passed hosted run
[42383079017](https://github.com/jiangshen/snowfolio/actions/runs/42383079017).
Downloaded evidence verifies 248 tests / 49 suites, eight arm64 bundles, 652 CommonMark
examples and eight UI tests. Fourteen existing priority-inversion warnings remain
recorded without attributing a first-party cause. The full modernization goal remains
active; real IME/VoiceOver, broader source-coordinate acceptance, measured performance,
CSS/templates, release readiness and safe legacy retirement are still open.


The first hosted catalog run `42386110911` passes all 259 package tests, 52 suites,
eight arm64 bundles and 652 CommonMark examples. The new native Settings walkthrough
exposed row-level accessibility modifiers cascading to both Import and Reload: both
buttons acquired the same identifier and "Custom themes" label. Compound theme rows
now keep their controls’ own identifiers/labels. The test explicitly requires one
Import and one Reload match, without selecting an arbitrary duplicate. Eight existing
UI methods passed; final import/review acceptance awaits the corrected hosted run.


The corrected-control run `42386924025` again passes package/corpus checks. Native
Import/Reload identities now pass, the `.style` panel selects the fixture, and Review
Theme appears. The test’s global Import-button query also matched macOS’s Touch Bar
mirror. The captured hierarchy identifies the intended action inside the Settings
alert sheet; the query now scopes to that single sheet. Import/review/undo assertions
remain intact. Final hosted acceptance is still pending rather than inferred.


Run `42387759704` verifies native file import, review and application of the imported
choice, then exposes a test fixture error at undo: normal list continuation had added
an enumerator before the test typed its own. The theme fixture now disables continuation
through its launch arguments and asserts its exact original text. The failed method
also left its custom theme saved, affecting a later Automatic-only color assertion.
Every UI-test launch now explicitly selects Automatic, removing that cross-method
preference dependency. Production continuation and theme behavior are unchanged.
Final full-suite hosted acceptance remains pending.


### Hosted theme-library acceptance

Run [42388642872](https://github.com/jiangshen/snowfolio/actions/runs/42388642872),
code `e56b2bf9951a5c95a6065e7c92ce92959b67d3f4`, passes both jobs. Downloaded
artifacts verify **259 package tests / 52 suites**, eight arm64 test executables,
652/652 CommonMark examples and **nine native UI tests with zero failures**. The new
walkthrough verifies Settings search, distinct Import/Reload controls, bundled choice,
file selection, review, imported choice, Settings reopen, exact source and native
undo/redo, then Automatic restoration. Its screenshot was inspected: controls and text
fit the grouped form without overlap. Fifteen priority-inversion warnings remain a
separate open attribution gate.

Direct user-desktop acceptance is still pending. The existing Snowfolio process was
launched at 03:47:34 PST, before the latest theme/Settings executable rebuild at
07:32:24 PST; it was preserved along with user documents and the Open panel while the
Mac remained locked. This checkpoint does not claim a fresh source-editor selection
reproduction or visual confirmation of that user process. The mixed-list preview
regressions remain passing. The full modernization goal stays active and incomplete.


## Physical inline source coordinates — 2026-11-07

New regressions reproduce misplaced native inline ranges on lazy list/quote continuation
lines and partial-tab indentation, including Unicode text. Native inline buffers omit
container prefixes and can replace the unconsumed part of a tab with spaces; their
original first-line column base is insufficient for later physical source lines.

A generic opt-in native inline-context observer now brackets both root and recursive
extension calls. Swift derives physical coordinates only from byte-identical fragments,
without another Markdown grammar or any source rewriting. Synthetic tab spaces point to
the original tab byte. Nested contexts derive maps from their exact outer buffer slices;
their descendants are reconciled once. Buffers are borrowed only inside the balanced
callbacks, and root completion clears context bookkeeping. Native multiline endpoints
retain the same context base as starts. A second regression proves and fixes the
one-byte-short end of multiline HTML tags. All C replacements remain recorded and
reversible to the original upstream hashes; application-owned mapping policy is Swift.

Local validation passes **263 tests / 53 suites**, including actual TextKit fonts on
lazy/partial-tab Unicode spans with unchanged source, selection, revision and undo.
**25 source/syntax Address Sanitizer tests / four suites** pass with no diagnostics.
Final arm64 app and corpus/hosted results are recorded in `validation/source-coordinates.json`.

This does not close the complete source-coordinate gate: non-identity transformations
such as escaped table-cell buffers and malformed/NUL replacement contexts need further
characterization. Direct desktop selection/IME/VoiceOver/scroll/resize and full M6
performance acceptance also remain open. The modernization goal remains active.


Final local source-coordinate checks include the native arm64 app build, all eight
arm64 test executables and 652/652 pinned CommonMark examples, with complete diagnostic
captures and zero compiler warnings/errors. Every native replacement reverses to the
recorded upstream source bytes. The source-map performance comparison and limitations
are in `PERFORMANCE_AUDIT.md`; no native app latency or memory-leak claim is inferred.


### Hosted physical-coordinate acceptance

Run [42392411885](https://github.com/jiangshen/snowfolio/actions/runs/42392411885),
code `9568c9cd23a0798591749aa7cbfc7541014cd094`, passes both jobs. Downloaded
artifacts verify **263 package tests / 53 suites**, eight arm64 test executables,
652/652 CommonMark examples and **nine native document UI tests with zero failures**.
The new physical-source/TextKit font regressions pass in the hosted package job.
Sixteen native runtime priority-inversion warnings remain recorded without inferring
a first-party cause. Direct desktop source-selection/real IME/VoiceOver and M6 runtime
acceptance are still open, along with non-identity source transformations, custom
CSS/templates, remaining feature parity and safe legacy retirement. The full goal is
active and incomplete.


## Escaped table coordinates and dialects — 2026-11-07

Table-cell normalization now exposes native provenance for actual pipe unescaping and
leading trim. Sparse events are recorded only for source-positioned owned rows and freed
with their native cells. Swift validates normalized content against the physical line
in one linear event walk, then maps inclusive start/end boundaries separately. A source
`\|` contributes both the backslash and pipe, preserving full inline-code delimiters.
Recursive extension contexts inherit that exact map. Body rows/cells use their own
physical origin rather than the header's indentation. The native cell whitelist now
admits the standard custom-inline node type, preserving supported Swift dialects in
tables. Grammar recognition stays native; document bytes are unchanged.

Local validation passes **266 tests / 53 suites**, **28 Address Sanitizer tests / four
suites** without diagnostics, eight arm64 test executables, the native arm64 app build
and 652/652 pinned CommonMark examples. Complete package/sanitizer/native captures have
zero compiler warnings/errors. The 240-case table matrix covers line endings, container
indentation, trim and escape counts. Real TextKit assertions cover Unicode strong text
and every byte of escaped inline code/backticks without changing tail fonts, selection,
source, revision or undo. Native patches remain exactly reversible to upstream hashes.

The same-harness before/after performance comparison is in `PERFORMANCE_AUDIT.md`; dense
escaped cells add measured work and metadata memory. This is not native app latency or
M6 acceptance. Full evidence is in `validation/table-source-coordinates.json`. Hosted
acceptance is recorded there after code push and artifact verification.

The source-coordinate gate remains open. Inspection of headers split from preceding
paragraph content flags missing paragraph source fields, inherited offsets and pipe
unescaping; these need a reproducer and characterization next. NUL/native replacement
contexts also remain. The user desktop is still locked; the existing app process and
user documents/Open panel are preserved, so no fresh desktop selection confirmation is
claimed. Real IME/VoiceOver, app performance, CSS/templates, remaining parity and safe
legacy retirement remain open. The full modernization goal stays active.


### Hosted table-coordinate acceptance

Run [42396415587](https://github.com/jiangshen/snowfolio/actions/runs/42396415587),
code `c6c8b228e2007bf41d0f91c1597c204de2b8b2e0`, passes both jobs. Downloaded
artifacts confirm **266 package tests / 53 suites**, eight arm64 test executables,
652/652 CommonMark examples and **nine native document UI tests with zero failures**.
The native theme search/import/undo and Settings/document walkthroughs all pass.
Fifteen runtime priority-inversion warnings remain an open attribution gate; two
App Intents metadata notices reflect the absent framework integration. No performance
fix is inferred from their count. Exact evidence and hashes are in
`validation/table-source-coordinates.json`.

Direct user-desktop acceptance remains pending while the Mac is locked, and the
existing running process predates the latest rebuild. The source-coordinate gates
above, real IME/VoiceOver, full native performance, remaining parity and safe legacy
retirement remain required. The full modernization goal remains active and incomplete.


## Paragraph/table partition and reference preservation — 2026-11-07

A new reproducer confirms that a table without a blank separator could leave its
preceding paragraph without source fields, shift header coordinates, remove a literal
backslash inside ordinary code, and bypass native reference resolution. The native
split now preserves the exact paragraph buffer, bounds its source span, and makes header
rows/cells relative to their own line. An optional generic split observer lets Swift
reconcile physical suffix coordinates while buffers are borrowed. It is separate from
reference-definition observation. The existing native paragraph resolver handles leading
definitions and removes definition-only prefixes through native ownership rules. No
document bytes or Markdown grammar are rewritten by Swift.

The split observer uses the native complete-line boundary for the prefix end and maps
only suffix fragments; an initial full-prefix pass was redundant. All native edits
remain exactly reversible to the recorded upstream hashes. Source callback lifetimes,
reference-only prefix teardown, container/internal offsets and unchanged document/undo
state were reviewed. No coupled legacy application code is removed at this checkpoint.

Local validation passes **270 tests / 53 suites**, **32 Address Sanitizer tests / four
suites**, eight arm64 test executables, the native arm64 app build and all 652 pinned
CommonMark examples. Complete final captures have zero compiler warnings/errors.
57 new cases cover line endings, Unicode, varying containers, optional leading pipes,
multi-line paragraphs, reference-only prefixes and footnote ancestry; actual TextKit
font assertions include a header after a paragraph. Plain/syntax outputs agree.

The same-harness render comparison is recorded in `PERFORMANCE_AUDIT.md` and
`validation/table-paragraph-split.json`. The corrected 1 MB paragraph/table case takes
about 10 ms versus 5.6 ms before, which omitted the prefix's source ranges/styles.
These are core-render timings, not native typing or M6 acceptance. Hosted results are
recorded after code push and artifact verification. Direct desktop access is still
locked, so the existing process and user documents/Open panel are preserved.

NUL/native replacement contexts, real IME/VoiceOver/visual interaction acceptance,
full app performance, CSS/templates, remaining parity, release readiness and safe legacy
retirement remain open. The full modernization goal remains active and incomplete.


### Next replacement-coordinate characterization

An isolated executable linked to exact commit `dda9e7b` reproduces the next NUL gate
without changing production code. All six diagnostic fixtures have misplaced strong
source ranges: ordinary paragraphs, lazy list continuations, quotes, headings, tables
and a literal replacement character followed by two NULs. Native `S_parser_feed`
replaces one NUL input byte with three UTF-8 replacement bytes before block parsing;
current byte-identity maps reject that non-identity line. Syntax ranges can then move
or disappear. This is explicitly **not fixed**, and is not counted among passing
package tests. Exact expected/actual ranges and raw evidence are in
`validation/null-source-characterization.json`.

Next implementation should preserve one normalized-coordinate domain through native
block/inline/container mapping, then project to physical source after all native
postprocessing. Authored replacement characters and document bytes must remain intact.
References, recursive scopes, tables, feed boundaries and actual native font placement
need regression coverage, with ordinary-path overhead measured. Broader source and
full modernization acceptance remain open.


### Automatic-link source-range characterization

The isolated diagnostic also reproduces ten incorrect or missing automatic-link ranges.
Plain `https://` and `www.` links include the preceding byte; lazy/partial-tab/container
and escaped-cell cases compound the wrong start. An email link has no source range.
Inspection finds native `www_match` subtracting one from the current column, `url_match`
using a buffer offset instead of a contextual line column, and email postprocessing
creating source-less nodes from decoded/consolidated text. Rendering still recognizes
the links; exact source highlighting is the incomplete requirement.

These are **not fixed** or included in passing-test totals. Exact isolated expected/
actual ranges are in `validation/autolink-source-characterization.json`. Correct the
native URL/www starts and preserve recognized email provenance through native text
transformations without another Markdown grammar. The NUL projection gate remains
separate; do not infer complete source-coordinate acceptance from current green tests.


### Hosted paragraph/table acceptance

Run [42398967214](https://github.com/jiangshen/snowfolio/actions/runs/42398967214),
code `dda9e7b76cb9390a9e8ae1509e522f340543d175`, passes both jobs. Downloaded
artifacts verify **270 package tests / 53 suites**, eight arm64 executables,
652/652 CommonMark examples and **nine native UI tests with zero failures**.
The first native app/test step passed, but artifact creation failed with GitHub DNS
`ENOTFOUND`. A failed-job retry, without a code change, passed and uploaded the exact
native log/result bundle. Sixteen runtime priority-inversion warnings and two App
Intents metadata notices are retained without inferring a performance cause or change.

This closes this partition checkpoint's hosted gate, not the overall source-coordinate
or modernization goal. The independently reproduced automatic-link and NUL cases
above are next. Direct desktop/real IME/VoiceOver, full app performance, remaining
feature parity, integration/releases and safe legacy retirement remain open.


## Automatic-link source reconciliation — 2026-11-07

Recognized URL/www links now start at the correct one-based contextual byte column.
Native URL rewind also keeps preceding text bounds synchronized and clears source
fields from empty text. Email postprocessing retains its native recognition rules
while exposing balanced source-only events for the existing immutable decoded buffer.

Swift captures candidate consecutive native text groups before consolidation. Plain
fragments carry owned row snapshots, including sparse table escapes; decoded entities,
escapes and smart punctuation carry their complete native lexeme bounds. Candidate groups
containing decoded `@` retain owned bytes. The retained node's resulting source
bounds and complete decoded buffer must agree before applying recognized partitions.
No native buffer/cell pointer escapes its callback. One full identity check per buffer
precedes offset-based partitions; END and parser completion clear owned maps. Grammar,
native ownership and document bytes are unchanged. All C edits remain exactly reversible.

Local validation passes **277 tests / 54 suites**, **38 Address Sanitizer tests / five
suites**, eight arm64 test executables, the native arm64 app build and 652/652 pinned
CommonMark examples, with complete captures and zero compiler warnings/errors.
URL/email label ranges and their automatic theme tokens are exact across Unicode, all
line endings, containers/tabs, decoded entities, escaped table text and recursive scopes.
Protocol/explicit-link controls preserve existing native grammar. A stress fixture maps
2048 emails after 8192 escaped pipes. Native TextKit checks prove complete source font
spans and untouched neighboring text, source, selection, revision and undo.

The final release comparison uses exact pre-change `f86d87f` with the identical audit
harness. Ordinary samples are close. The link-heavy 1 MB case takes about 79 ms versus
61 ms before, now including previously missing email source/style work. The cost and
raw RSS/timings are retained in `PERFORMANCE_AUDIT.md` and
`validation/automatic-link-source.json`; these do not establish native typing or M6
acceptance. Hosted follow-up is recorded after code push and artifact verification.

NUL projection remains open, as do direct desktop/real IME/VoiceOver, full native app
performance, CSS/templates, remaining parity and safe legacy retirement. The Mac is
still locked; its existing process and user documents/Open panel are preserved. The
full modernization goal remains active and incomplete.


### Hosted automatic-link acceptance

Run [42405440825](https://github.com/jiangshen/snowfolio/actions/runs/42405440825),
code `33e9046d6ab21c29220ee40abcdd0ba43cadcacc`, passes both jobs. Downloaded
artifacts verify **277 package tests / 54 suites**, eight arm64 test executables,
652/652 CommonMark examples and **nine native UI tests with zero failures**. Fifteen
runtime priority-inversion warnings and two App Intents metadata notices are retained
without inferring a first-party performance cause or change. Exact logs/result hashes
are recorded in `validation/automatic-link-source.json`.

An isolated executable from this exact code revision also confirms all six NUL
characterization fixtures still have incorrect strong ranges. The latest raw output
and exact harness hash are in `validation/null-source-characterization.json`. The
remaining work is input-normalized source-line projection, not another Markdown
grammar. Direct desktop/IME/VoiceOver, full native performance, CSS/templates, remaining
parity, integration/releases and safe legacy retirement remain open. The full goal
stays active and incomplete.


## Reported short mixed-list acceptance — 2026-11-07

The 03:42:42 screenshot predates the existing mixed-list correction in `c5cfb6c`
(03:49:35). Production styling is unchanged in this follow-up. The native WebKit
regression now also exercises the exact First/Second/dfdfd list at 28px, in light and
dark appearances, before and after a serif/20px style change. Both numbered items and
the bullet text must share their text edge within one CSS pixel, with a .5em marker
gap. The wrapped tight/loose cases and authored/task/nested marker checks remain.

Five targeted tests across two suites pass locally without warnings or errors,
including all six list parameter cases and the three existing source presentation,
selection/undo and stale/composition guards. Native copied text trims trailing
whitespace, so the full long bullet expectation uses its trimmed text. This is a
layout/selection regression, not a pixel-level screenshot assertion. Desktop access
remains locked; no fresh visual acceptance or running-app refresh is claimed. See
`validation/list-selection.json`. Native input normalization work remains uncommitted
and separately gated; the full modernization objective stays active and incomplete.


Hosted short-list acceptance passed on `9c98b3c` in run
[42407477812](https://github.com/jiangshen/snowfolio/actions/runs/42407477812).
Downloaded artifacts verify 278 package tests / 54 suites, the six list parameter
cases, eight arm64 executables, 652/652 CommonMark examples and nine native document
UI tests with zero failures. Runtime diagnostics remain recorded in the ledger and
do not close performance/integration gates. The user's desktop remains unavailable;
this records automated acceptance of the existing fix and added regression coverage.


## Native input normalization projection — 2026-11-07

The native parser expands each input NUL byte into the three-byte UTF-8 replacement
character before block parsing. Previous source identity checks then failed and left
subsequent source highlights shifted. A source-only optional callback now observes the
first actual replacement, with borrowed pointers scoped to the callback. Swift owns
normalized copies and sparse offset maps only for affected source lines. All intermediate
container/tab/table/recursive/reference/note/text mappings use the native input domain;
final definitions and AST/HTML/syntax node columns project to physical input only after
native postprocessing. This preserves authored replacement characters and document bytes.
Node projection shares the existing AST traversal. Dense buffer construction checks
cancellation. The local C bridge changes no parser grammar, literal content or ownership;
all patches reverse exactly to their pinned source hashes.

Six new test methods cover line endings, Unicode, NUL interiors, references/notes,
definition-only and paragraph/table splits, escaped cells, recursive dialects, math,
leading/trailing/consecutive replacements and native feed boundaries. Existing native
font-placement tests add NUL and authored-replacement fixtures and preserve neighboring
fonts, source, selection, revision and undo. Final local checks pass 284 package tests /
55 suites, 29 ASAN tests / four suites, eight arm64 executables, native app build and all
652 CommonMark examples, with clean captured diagnostics and strict changed-Swift format.

Exact before/after release measurements use baseline `dae72fc`, identical harness and
54 fresh process samples. Ordinary workload timings are close. The deliberately dense
1 MB NUL case rises from 62.809 to 73.769 ms; 10 MB rises from 681.533 to 797.861 ms while
previously shifted source ranges become correct. The 10 MB case still exceeds one GiB
peak RSS and remains an M6 optimization target. These are render measurements, not app
typing/energy/leak acceptance. Desktop access remains locked. Full evidence, costs and
limitations are recorded in `validation/input-source-projection.json`; broader CSS/template,
productivity, document/accessibility, native performance, release and retirement gates
remain active. Hosted follow-up is recorded after the code push.


### Hosted input projection acceptance and next parity work

Run [42409052004](https://github.com/jiangshen/snowfolio/actions/runs/42409052004),
code `a11c4bc71a1789b92f1b0a92b094ff4ce58b64d9`, passed both jobs. Downloaded exact
artifacts verify 284 package tests / 55 suites, the six new normalization test methods
and expanded native font-placement case, eight arm64 executables, 652/652 CommonMark
and nine native document UI tests with zero failures. Fifteen priority diagnostics and
two App Intents metadata notices remain recorded without claiming first-party causes.
The direct desktop remains locked; no new real IME/VoiceOver/visual or M6 acceptance is
inferred. This closes the reproduced NUL source-range gate, not the full modernization.

The next independently available parity area is custom CSS/templates. Source inspection
confirms six original CSS assets; legacy folder discovery, no-style selection, reveal
and reload; separate styled/highlighted export switches; and the original template's
five context values and each/raw expressions. The current native adapter retains the
old preference keys but does not consume them. Original CSS also expects content directly
under body, so stacking it over notebook CSS behind a main wrapper would change selector
behavior. `validation/css-template-characterization.json` records exact source/assets,
current gaps and required runtime/export/resource evidence. Restore these capabilities
while retaining the liked Snowfolio notebook style as the default. Coupled legacy
renderer/template/resource retirement remains gated on verified consumer parity.


## Code-block presentation hosted acceptance — 2026-11-07

Run [42433495480](https://github.com/jiangshen/snowfolio/actions/runs/42433495480),
code `105709896ad72ce9c95fc979024e93d2fac64a3f`, passed both jobs. Exact downloaded
evidence verifies 329 package tests / 70 suites, 652/652 CommonMark examples, eight
arm64 test executables and 15 native document UI tests with zero failures. Custom
code label/number Settings and None-style initial HTML export options pass with source
and explicit native history assertions retained. All six mixed-list cases pass,
including the reported First/Second/dfdfd layout. No additional list styling changed.

The Settings and export screenshots paint the expected controls. The reading preview
is blank in the code fixture screenshot despite its successful accessibility lookup;
the cause remains unproven. This does not close glyph/number/selection visual acceptance.
A fresh direct CUA check still finds the Mac locked. Existing intermittent native caret
and preview-led zoom diagnostics remain recorded without weakened assertions. The
26 runtime priority diagnostics and two AppIntents metadata notices still need attribution.
Full document reliability, real IME/VoiceOver, remaining parity, productivity integrations,
native performance, releases and safe coupled legacy retirement remain open. Exact
results, limitations and hashes are in `validation/code-block-presentation.json`.

Four superseded agent-generated template downloads were moved to Trash after retaining
the expanded current raw evidence: 4,344 files / 290,155,859 logical bytes. Recovery
markers and destinations were verified; Trash was not emptied. Compact prior screenshots
and reports remain. See `validation/project-cleanup.json` for exact recovery paths.


## Unsaved-document asset folder and native undo — 2026-11-07

The original default-directory preference is now available as an explicit native folder
choice in Privacy & Security. The migrated URL is a suggestion until confirmed; fresh
profiles have no implicit Home resource grant. Read-only bookmarks restore off the main
actor, renew when stale, retain unavailable choices for recovery and balance scope
lifetimes across preview requests and frozen export operations. Saved documents resolve
relative files from their own folder. The existing bounded local reader is unchanged.

The native workspace regression exposed stale same-name images after switching to an
empty folder: the DOM still reported complete/naturalWidth=1 from the prior root. A
fresh resource origin per reload now separates those cache entries and validates the
current namespace before routing to the local reader. Five image transitions pass with
unchanged native view identity, source/selection/revision and undo.

The same regression exposed a model-undo race: its new document snapshot could be
overwritten by the undo observer's older NSTextView buffer before SwiftUI synchronized.
A source-revision guard preserves the model snapshot. Explicit native-window history
now verifies model undo/redo alongside the existing native editing/zoom regressions.
No source or history assertions were removed. Initial reports are retained in the
new validation ledger, including a test URL-spelling correction and a get-only
UndoManager environment compile diagnostic.

Local acceptance passes 334 tests / 71 suites, ten sanitizer tests / two suites and
21 focused tests / five suites without warnings/errors; native build and 14 changed
Swift files' strict formatting pass. App UI tests for chooser/cancel/status/history
and real untitled Save→saved-folder image export are compiled but await hosted execution.
Fresh desktop/IME/VoiceOver, full document reliability, remaining parity, integrations,
performance/releases and safe coupled legacy retirement stay open. No additional
original renderer/preferences code is retired by this independently verified slice.


The final unavailable-folder recovery path rejects only exports that actually need
relative Markdown images. Plain/remote content and copied fragments remain usable.
The final local suite passes 334 tests / 71 suites and ten ASAN tests / two suites;
17 app UI methods compile. One full run timed out in unchanged preview-led source
scrolling; the unchanged focused case and final full suite pass. Its cause is unproven;
scrolling assertions/timeouts and production scrolling code remain unchanged. Exact
reports and the final arm64/build hashes are in `validation/unsaved-asset-folder.json`.


Hosted follow-up for code `d3f5da23c5fc13f9ab1f0be67d784f52998483c7` is queued in
[run 42436504932](https://github.com/jiangshen/snowfolio/actions/runs/42436504932).
Poll this same run through completion and inspect its raw evidence; its 17 native UI
methods are not accepted merely because they compile. The full goal remains active.


## Hosted unsaved-folder and actual Save As acceptance — 2026-11-07

[Run 42436504932](https://github.com/jiangshen/snowfolio/actions/runs/42436504932),
code `d3f5da23c5fc13f9ab1f0be67d784f52998483c7`, passed both jobs. Downloaded
raw evidence verifies 334 package tests / 71 suites, 652/652 CommonMark examples,
eight arm64 executables and all 17 native document UI methods with zero failures.
The new chooser/cancel/search/clear/history case passed in 64.875 seconds. The actual
untitled Save→HTML case passed in 63.466 seconds: exact source bytes are saved in a
new folder and the export embeds that folder's distinct PNG rather than the unsaved
asset folder's image. The Settings screenshot paints the expected controls and path.

Thirty priority diagnostics and two AppIntents metadata notices remain unattributed.
Fresh user-desktop glyph/selection, real IME/VoiceOver, full document lifecycle,
remaining feature parity, M5, measured app performance/releases and safe original-code
retirement remain open. The screenshot does not establish reading-preview glyph paint.
Exact methods, scope and hashes are in `validation/unsaved-asset-folder.json`.

Two superseded agent-generated code-presentation downloads were moved to Trash after
retaining the expanded current raw bundle: 2,127 files / 144,627,380 logical bytes /
151,990,272 allocated bytes. Recovery markers and original/destination paths were
verified. Trash was not emptied. Current builds, source, compact historical screenshots
and reports, and user documents remain; see `validation/project-cleanup.json`.

The next editor margin/width work is isolated in `/private/tmp/snowfolio-editor-layout`
on `modernization/editor-layout`. It is not part of this accepted source checkpoint.
Line spacing and scroll-past-end characterization remain separate parity work.
