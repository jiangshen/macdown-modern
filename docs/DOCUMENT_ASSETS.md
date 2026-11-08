# Document assets

Saved documents resolve relative images from the folder containing the Markdown file.
Before saving, choose **Settings → Privacy & Security → Unsaved document assets →
Choose Folder**. The selection applies to open unsaved documents and their fresh
HTML/PDF/print exports. Clearing the choice stops new unsaved-document resource loads.
Exports already in progress retain their original folder until finished.

An imported MacDown default path appears as a suggestion. Select it in the native
folder chooser to confirm access; Snowfolio does not automatically use Home. The
read-only folder bookmark restores on later launches. If a folder is unavailable,
reconnect it and Retry, or choose it again. Canceling the chooser keeps the current
choice. Failed selections keep the previous valid choice; damaged saved bookmarks
remain available for explicit recovery. If a remembered folder cannot be restored,
exports that need its relative Markdown images explain how to recover it. Plain text,
remote images and copying an HTML fragment remain usable.

Folder changes use fresh preview resource URLs, so a filename shared by two folders
cannot keep displaying the earlier image from WebKit's cache. The existing resource
type, size, directory and symlink boundaries still apply. Document bytes, selection
and undo history remain owned by the native editor and document host.

Local native workspace, export snapshot and memory-checker evidence is in
[unsaved-asset-folder.json](validation/unsaved-asset-folder.json). Native chooser/cancel/history and
actual untitled-save/export UI tests passed on the exact implementation in hosted run
42436504932. Fresh desktop and release/sandbox acceptance remain separate gates.
