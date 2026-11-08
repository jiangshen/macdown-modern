# Standalone document host diagnostic

This test-only app compares Apple's documented macOS 27 `Document`,
`FileWrapperDocumentReader`/`Writer` and `TextEditor` migration pattern with
a Swift `NSDocument`/TextKit 2 control. It has no Snowfolio or third-party
dependencies, no merge guard and no production target changes. It is never
bundled with Snowfolio.

Run `bash Tools/probe-document-host.sh` for SwiftUI, or
`SNOWFOLIO_DOCUMENT_HOST_PROBE_KIND=appkit bash Tools/probe-document-host.sh`
for AppKit, on an available macOS 27 test desktop. The hosted workflow exposes
matching `document-host-probe` and `document-host-probe-appkit` scopes. Both
variants reuse Build/DocumentHostProbe; the selected host is compiled separately.

The checks use only UUID-owned temporary UTF-8 text files. They compare clean
external replacement before/after autosave and Undo persistence after an edited
checkpoint has actually autosaved. The Undo edit is one character so the sample's
per-character model Undo registration and native typing coalescing are comparable.
The new controls compare coordinated atomic replacement in canonical temporary
and ordinary home-folder paths. Each UUID-owned fixture directory is deleted;
no user documents are modified. The old uncoordinated cases remain. Native
presenter-change/revert callbacks are traced without file paths or source text.
Autosave checks use deactivation plus35s; clean external reload uses8s. These
controls do not establish Snowfolio acceptance, encoding/dirty-conflict parity,
or restoration. Existing production acceptance assertions are unchanged.

The SwiftUI model deliberately follows Apple's `.onChange` Undo sample. The
AppKit control uses the document's native undo manager; its nonisolated read
updates a Mutex-protected snapshot, and main-actor revert updates the view.
Metadata logs contain operation/length values only. Keep compact results and
clean this isolated build after the host investigation finishes.

Reference: https://developer.apple.com/documentation/swiftui/updating-your-document-based-app
