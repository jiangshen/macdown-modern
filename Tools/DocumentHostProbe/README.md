# Standalone document and WebKit diagnostic

This test-only app compares macOS document hosts and preview embedding. It is never
bundled with Snowfolio. Select a variant with `SNOWFOLIO_DOCUMENT_HOST_PROBE_KIND`:

| Variant | Implementation |
| --- | --- |
| `swiftui` (default) | Independent documented `Document`/FileWrapper reader/writer and TextEditor sample |
| `swiftui-url` | Independent direct-URL reader/writer sample |
| `appkit` | Independent Swift NSDocument/TextKit 2 control |
| `native` | Snowfolio's shared native document adapter with a minimal native editor |
| `native-workspace` | Shared document adapter and complete Snowfolio workspace/menus, plus isolated WebKit controls |

Run `bash Tools/probe-document-host.sh` on an available macOS 27 test desktop;
append `build-for-testing` for compilation only. The default output is
`Build/DocumentHostProbe`. Set `SNOWFOLIO_DOCUMENT_PROBE_BUILD_DIR` to the current
reusable app build location when a different diagnostic bundle is still running.
Do not overwrite the app/cache in use. Hosted workflow diagnostic scopes choose
the corresponding variant, and retain their normal output path.

Fixtures use UUID-owned temporary directories or an ordinary home-folder fixture
parent. Tests preserve source/encoding bytes, require an actual edited autosave
before checking Undo persistence, and compare coordinated/uncoordinated atomic
replacement. Existing waits remain unchanged. The full workspace also covers
UTF-16LE/BOM/CRLF/Unicode staged autosaves and Undo/Redo, menus, exact dual-type
Copy HTML, Settings and dirty/manual-Save conflict handling. Only the dirty fixture
uses a bounded30-second autosave delay to stage unsaved local content; other native
methods retain2seconds. It does not accept standard-periodic dirty conflicts,
user-choice resolution, Versions, real IME/VoiceOver or complete app parity.

The full workspace's WebKit paint comparison opens only when the test supplies
`SNOWFOLIO_PROBE_PAINT_OUTPUT`. It hosts plain WKWebView and the exact shared preview
configuration/coordinator/MarkdownPreviewWebView in a direct AppKit stack. The latter
uses `@testable import` against the Debug library, without adding a shipping API.
It retains production data-store/script policy, local resource handler, isolated-world
scroll script and reading style. The plain control uses nonpersistent storage,
disabled document JavaScript and self-contained HTML.

The test records accessibility readiness, native frames/visible rectangles/layers,
loading/error state, each WebKit-native snapshot, a window screenshot and a full-screen
screenshot. Geometry is saved before snapshots so a failed/hung snapshot does not
hide placement evidence. These compare embedding, WebKit rendering and screenshot
capture; successful assertions alone do not establish visible preview painting.
Inspect the images. Only synthetic content is used. Output is attached to XCTest,
then the UUID-owned directory is removed; no historical image copies accumulate.

Native presenter/revert callbacks log operation metadata without file paths/source.
Keep compact findings and relevant screenshots, retain one useful raw result by
default, and clean obsolete comparison downloads/builds after the investigation.
The independent controls do not establish Snowfolio feature parity. Actual app
acceptance runs separately through the full `native-document-app` scope.

Reference: [Apple's document migration guide](https://developer.apple.com/documentation/swiftui/updating-your-document-based-app).
