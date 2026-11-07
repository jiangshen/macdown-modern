# MacDown modernization plan

Status: **Milestone 1 complete; Milestone 2 validation continues; Milestone 3 parser/preview implementation in progress. The application rewrite is not complete.**

## Scope and source of truth

The checked-out `macdown-modern` repository, not another fork, defines legacy behavior.
Preserve its source and resources until replacements pass characterization and integration
tests. All new application-owned code uses Swift 6 language mode and the installed Swift
6.4 toolchain. Third-party C/JavaScript may remain behind explicit boundaries when needed.
Native AppKit selectors and Objective-C interoperability are permitted in Swift; this does
not mean keeping first-party Objective-C implementations.

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
| Essential | Open/new/save/save-as, UTF-8 contents, dirty state, native autosave/Versions, multiple windows | Pending app integration |
| Essential | Undo/redo, selection, Unicode, Chinese/Japanese marked text, spellchecking, native find | Pending |
| Essential | Source, preview and split modes; resize, swap sides, linked scrolling and zoom | Native modes/resize verified; swap, linked scrolling and zoom pending |
| Essential | Formatting, headings 1–6/paragraph, lists, indent/unindent, links/images, paired delimiters | Common source commands/input integrated; remaining legacy dialect and advanced editing gates pending |
| Essential | Live/manual HTML preview, HTML copy/export, styled export, PDF and native printing | Core paths verified; advanced renderer/export fidelity pending |
| Essential | Custom editor `.style` themes, CSS, templates, syntax themes, typography and layout preferences | Notebook typography and all eight built-in Prism code themes implemented; custom source `.style`, CSS/templates and remaining layout preferences pending |
| Essential | MathJax-compatible math, Mermaid, Graphviz, task lists, front matter tables and TOC | Pending |
| Essential | Existing Markdown extension toggles: tables/fences/autolinks/strike/underline/superscript/highlight/footnotes/quote/smart punctuation/intraword emphasis | Pending |
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
- `Packages/MacDownCore`: independent `DocumentCore` and `EditorCore` initially;
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

### M4 — Native workspace and design

- SwiftUI toolbar/sidebar/outline/settings, split/solo modes, focus and typography.
- Native tabs/windows, restoration, keyboard focus, light/dark/high-contrast appearance,
  Reduce Motion, VoiceOver and Retina layout validation with runtime screenshots.
- Gate: keyboard-only open/edit/search/export, theme/window restoration and IME tests.

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

- Added `MacDownUI` as a separately testable native adapter target.
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

- Ship an original layered Liquid Glass app icon. `Modern/Resources/AppIcon.icon` is
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

The generated `Modern/MacDownModern.xcworkspace` builds a real `.app` with the local
Swift package. `Tools/build-modern-app.sh` reproduces generation/build and verifies
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

Product name confirmed: **MacDown**. Keep the original glacial-blue icon
style and M↓ Markdown mark. The user chose to keep **MacDown** for now. Use MacDown for visible branding and the app
bundle; retain stable internal identifiers and preference migration history. Preserve
all copyright and license notices.

## Markdown command engine and document icons

`EditorCore/MarkdownEditing.swift` now produces local UTF-16-safe transactions for
inline formatting, heading/paragraph conversion, list/quote conversion, indentation,
links/images, task toggling, list/quote/indent continuation, tab stops and optional paired
delimiters. Fixtures characterize selection-preserving toggles and the legacy emphasis
versus bold distinction. Mixed CR/LF/CRLF and multi-digit list prefixes use corrected
selection mapping. This engine is tested but **not yet wired into the native editor or
Format menu**; native undo/input/IME integration remains the next required editing step.
Latest core validation: **63 tests across 13 suites**, seven arm64 executables, all passed.

MacDown is the retained product name. The modern bundle is now `MacDown.app`, with
`CFBundleName` and `CFBundleDisplayName` set to MacDown. Stable bundle identifiers and
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
while MacDown must develop its own visual identity and follow Apple's current design
guidelines. Use native Liquid Glass in appropriate toolbars, controls and popovers;
keep writing/reading surfaces quiet, opaque and legible. Preserve the established
glacial-blue app identity and native Mac behavior rather than reproducing Notion's
interface. Respect system light/dark, Increase Contrast, Reduce Transparency and Reduce
Motion. Avoid a wholesale redesign of the current content styling. This refinement is
an explicit requirement of the active modernization goal and applies to the emoji
picker now being completed and later workspace/UI work.


## Native callout emoji picker — 2026-11-06

The requested picker and refined callout layout are implemented. After read-only visual
inspection of the authorized Notion reference, MacDown now uses a larger icon gutter,
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

The new MacDown theme adapts to light/dark appearance and printing, with a contrast
fallback. All eight original built-in Prism themes are available: Prism, Coy, Dark,
Funky, Okaidia, Solarized Light, Tomorrow and Twilight. Legacy theme names are matched
case-insensitively; empty/default names and unknown-name fallback preserve the original
Prism default behavior. Existing explicit `htmlSyntaxHighlighting` and theme preferences
are migrated without replacing user choices. Theme changes update CSS in place and keep
existing code nodes and reading anchors. New installs use the adaptive MacDown theme.

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
