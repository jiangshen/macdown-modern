# Snowfolio

A native Apple Silicon Markdown editor for macOS 27 and later, evolving from MacDown into an
independent writing app. Plain Markdown files stay local and portable. Snowfolio keeps
the glacial-blue layered app and document icons, readable notebook styling, and native
Mac controls.

The Swift app includes a TextKit 2 editor, native document tabs, linked scrolling,
configurable pane order, per-document reading zoom, live preview, syntax colors, callouts with an emoji picker,
YAML properties, a table of contents, optional highlights/superscripts, offline equations and diagrams, and shared HTML/PDF/print output. It is a development build: feature parity, accessibility,
performance measurement and release readiness are still in progress. See the
[modernization roadmap](docs/MODERNIZATION_PLAN.md) and
[source inventory](docs/SOURCE_INVENTORY.md).

## Build and test

Use an Apple Silicon Mac with Xcode 27 / Swift 6.4 or later and Tuist (`brew install tuist`):

```sh
bash Tools/validate-modernization.sh
bash Tools/build-snowfolio.sh
```

The native project is generated from `App/Project.swift` into
`App/Snowfolio.xcworkspace`. The app is written to
`Build/Snowfolio/DerivedData/Build/Products/Debug/Snowfolio.app`.
The Swift package lives in `Packages/SnowfolioCore` and uses Swift Package Manager.
The validation helper checks that all test executables are native arm64.

Use `bash Tools/build-snowfolio.sh --test` for the document lifecycle UI suite when
Xcode UI automation is available. In the current environment the suite compiles, but
execution times out while enabling automation; direct native checks and package tests
are recorded separately in `docs/validation`.

The original Objective-C application remains a migration reference until its essential
features are replaced and verified. The new app builds independently of CocoaPods.
Legacy source is progressively retired, with all required licenses preserved.

Reading zoom is in the View menu: **⌘⌥+** / **⌘⌥−** to magnify and **⌘⌥0** for
actual size. It changes the source and preview together without changing document text
or export typography. Each document remembers its own zoom. Editor settings can also
scale the preview relative to the editor's configured font size.

## Equations

Enable **Render equations** in Markdown settings. Use a `math` code block or put `$$`
on separate lines around multiline TeX. Same-line `$$…$$` and the original doubled
`\\(…\\)` inline delimiters also work. Single `$…$` is a separate optional setting.

Equations render offline in preview and HTML/PDF/print output. Exported HTML includes
its fonts and distribution notice. Unsupported TeX remains visible as source. Full
MathJax extension/macro/numbering compatibility and some mixed/multiline delimiter forms
are still being migrated; see the roadmap for the exact remaining gates.

## Diagrams

Enable **Render Mermaid diagrams** and/or **Render Graphviz diagrams** in Markdown
settings. Use a `mermaid` fence for flowcharts, sequence diagrams and other supported
Mermaid syntax. Use `dot` (or `graphviz`, `gv`, `viz`), `circo`, `fdp`, `neato`, `osage`,
`twopi`, `sfdp` or `patchwork` fences for the corresponding Graphviz layout.

Both engines run offline. Preview diagrams adapt to light/dark appearance; standalone
HTML and copied HTML fragments contain ordinary SVG, and PDF/print use the light
variant. Invalid, oversized, unsafe or timed-out diagrams retain their source code with
a preview notice. Diagram options default off and migrate existing MacDown preferences.
Remote resources, callbacks and arbitrary JavaScript are unsupported. See the
[diagram example](docs/design/notebook/DiagramDemo.md) and roadmap for remaining gates.

## Inline formatting

Enable **Highlights (==text==)** and **Superscripts (^text or ^(text))** in Markdown
settings. Both are optional and preserve existing MacDown choices. Highlights use a
quiet yellow surface that adapts to light/dark appearance. With highlights enabled,
**Format → Highlight** (**⌘=**) wraps or unwraps the selection as one undoable edit.

Use `==important==`, `x^2`, or `x^(a + b)`. Formatted text and references work inside
these spans, and parenthesized superscripts can cross a source line. Code, image alt
text and link destinations retain their normal scopes. HTML/PDF/print share the same
rendered result. Malformed empty/unclosed superscript markers stay visible; complex
input has bounded parsing with a preview notice and remaining literal markers.

The native parser remains pinned to swift-cmark 0.9.0, with three audited backports
from CommonMark/cmark 0.31.2 for numeric references, Unicode punctuation/symbols and
nested strong tags. Apple's attributed-string grammar is disabled because it can
swallow text in ordinary Markdown. Source hashes, reversible patches and original
notices are verified before builds. **All 652 published CommonMark 0.31.2 examples pass**
through the core parser audit. This is a core corpus result; the wider app/GFM,
optional-dialect and migration acceptance gates remain separate.

To reproduce the published corpus check, download its checksum-pinned fixtures and run:

```sh
curl --fail --silent --show-error https://spec.commonmark.org/0.31.2/spec.json -o /tmp/snowfolio-commonmark-spec.json
bash Tools/validate-commonmark.sh /tmp/snowfolio-commonmark-spec.json
```

The audit builds a development-only Swift executable from the exact packaged parser.
It never runs document scripts and is not part of the shipping application. CI runs
this audit and retains package logs and native UI result bundles for seven days.

## Identity and attribution

Snowfolio is based on [MacDown](https://github.com/MacDownApp/macdown), created by
Tzu-ping Chung and contributors, under the MIT License. Original copyright and
third-party notices remain in `LICENSE` and the native app's bundled notices.
The Snowfolio name does not change Markdown's standard file type or ownership.

[Branding and compatibility details](docs/BRANDING.md) explain the rename and the stable
macOS identity used to preserve app data. Older validation records retain the names and
paths observed when those checks ran.
