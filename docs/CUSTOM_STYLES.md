# Custom document styles

In Settings → Appearance, **Document style** controls the reading preview and styled
HTML/PDF/print output. Snowfolio keeps the current notebook design by default. None,
the six original bundled styles, local styles, MacDown styles and imported styles
remain separate choices. Source-editor themes and code-block highlighting are independent.

Choose **Import… → CSS File…** for a standalone stylesheet. Choose **Style Folder…**
when it has local images, fonts or other stylesheets. The folder chooser lists CSS
files, including nested files; select the main stylesheet. Its relative paths can
refer to supporting files anywhere inside the selected folder. Files outside that
folder and symbolic links are refused.

Imports copy the original main CSS and referenced local files into Snowfolio’s Styles
folder. They preserve source bytes and do not change the originals. **Show in Finder**
opens that folder. Imported copies are editable; **Reload** rebuilds the selected
appearance and refreshes the catalog. Existing CSS files placed directly in the
Styles folder and edited MacDown styles can also be selected and reloaded.

The resolved presentation freezes local resources together. An open preview and a
fresh styled export use that presentation even if the original import folder is
moved or deleted. A later reload can pick up changes to the copied files. A failed
reload retains the last valid appearance and saved selection, with an error in Settings.
Changing styles does not edit Markdown or add a source undo action.

Local CSS imports retain their layer, supports and media conditions. Resource URLs,
escaped filenames, custom properties, image-set strings, fonts and SVG fragments are
resolved through the CSS parser. Authored selectors, comments and other source text
are preserved. CSS feature-test URLs and namespace names are not treated as fetches.
Embedded CSS imports are parsed recursively too.

Remote stylesheet imports and remote fonts are not loaded. Store those resources
inside the selected folder and use local links. HTTPS images retain the existing
remote-images preference; importing a style does not enable it. Styles cannot execute
scripts or open an unrestricted native/network bridge.

Limits: UTF-8 CSS up to 1 MiB per sheet; fewer than 16 import levels; 128 referenced
local files and 32 MiB of original resource bytes; 64 MiB maximum resolved CSS; 2,048
resource references per sheet and bounded parser complexity. The folder chooser scans
up to 512 entries and 32 levels. Unsupported syntax, missing resources and limits are
reported instead of silently replacing an edited style with a bundled style.

This implementation supplies frozen styles and embedded local assets. Complete
legacy linked/omitted asset export modes, separate user-provided license sidecars,
template compatibility, fresh desktop/accessibility acceptance and full app performance
remain in the modernization plan. App-owned third-party parser, bundled style and
font notices remain preserved and verified by the build.
