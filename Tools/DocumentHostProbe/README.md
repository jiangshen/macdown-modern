# Standalone document host diagnostic

This test-only app compares Apple's documented macOS 27 `Document`,
`FileWrapperDocumentReader`/`Writer` and `TextEditor` migration pattern with
Snowfolio's lifecycle failures. It has no Snowfolio or third-party dependencies,
no merge guard and no custom editing surface. It is never bundled with Snowfolio.

Run `bash Tools/probe-document-host.sh` on an available macOS 27 test desktop,
or select `document-host-probe` in the hosted workflow. The checks use only
UUID-owned temporary UTF-8 text files. They compare clean external replacement
before/after autosave and immediate Undo persistence. They do not establish
Snowfolio acceptance, encoding/dirty-conflict parity, or restoration.

Model undo follows Apple's `.onChange` sample deliberately; its behavior is
part of the experiment, not a proposed production editor replacement. Metadata
logs contain operation/length values only. Preserve compact results and clean
this isolated build after the host investigation finishes.

Reference: https://developer.apple.com/documentation/swiftui/updating-your-document-based-app
