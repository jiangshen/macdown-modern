# MacDown modernization plan

Status: **Milestone 1 complete; Milestone 2 in progress. The application rewrite is not complete.**

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
| Essential | Source, preview and split modes; resize, swap sides, linked scrolling and zoom | Pending |
| Essential | Formatting, headings 1–6/paragraph, lists, indent/unindent, links/images, paired delimiters | Pending |
| Essential | Live/manual HTML preview, HTML copy/export, styled export, PDF and native printing | Pending |
| Essential | Custom editor `.style` themes, CSS, templates, syntax themes, typography and layout preferences | Pending |
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
- New package has no external dependencies, uses macOS 27 baseline and Swift 6 mode;
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
