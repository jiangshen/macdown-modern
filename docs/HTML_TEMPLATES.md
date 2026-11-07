# HTML templates and export snapshots

Snowfolio preserves MacDown’s bundled `Default.handlebars` resource byte for byte,
with its MIT attribution. A Swift adapter renders its title, stylesheet, body and
script context ordering. The app ships no Handlebars runtime. Build tools verify the
template, provenance and notice in both the repository and the app bundle.

The original renderer loads the saved `htmlTemplateName` from `bundle/Templates`
once. The repository contains only Default; no user-template folder or import UI is
exposed by that code. Snowfolio migrates the saved name without replacing an unknown
value. A missing name stops HTML/PDF/print before a save/print panel opens, with an
explicit recovery message. Settings → Appearance → HTML template shows the saved
name and offers **Use Default**. Only that action changes the saved choice. Copy HTML
remains a fragment operation, independent of the document template.

The Swift compatibility program recognizes root `title`, `titleTag` and `body`, plus
`each styleTags` / `each scriptTags` with `this`. Double values escape HTML; triple
values insert already typed markup. Unsupported helpers, partials, paths, scopes,
nested loops, malformed blocks and invalid encoding fail explicitly. It is a bounded
adapter for the observed bundled grammar, not a full Handlebars implementation or a
new custom-template importer. Input is limited to 64 KiB and 2,048 expressions;
rendered output is limited to 256 MiB with cancellation checks. Escaped values check
the limit as they expand.

Production assembly inserts the resource policy into the audited literal template
before rendering any context. The four root/remote-image combinations are cached.
Titles are escaped; CSS cannot close a style element; authored styles retain direct
body-child selectors. Notebook retains its own content wrapper. Live preview uses a
shared typed Swift shell with the same title/CSS/body boundaries. Script context is
empty in production: code colors, equations and diagrams are generated offline.
Document scripts, connections, frames, objects, base URLs and form actions remain
disabled. The remote-images preference controls HTTPS image loading.

HTML export offers independent **Include document styles** and **Include code
highlighting** choices. All four combinations are supported. Math layout resources
remain present when needed for generated equations. Original call sites confirm that
`MPAssetFullLink` served preview assembly (`MPRenderer.m`, `render`); export
`HTMLForExportWithStyles:highlighting:` chose embedded or omitted assets. The source
helper’s three enum values do not establish a third user-facing export mode.

An export captures source, rendering options, resolved CSS/assets, title, directory,
resource policy and template name before opening a panel. It renders that immutable
snapshot rather than reading the live preview. Manual preview mode, later edits and
later preference changes cannot substitute stale content or change an in-flight
export. Existing native PDF/print preparation uses the same generated document.

The original renderer/dependency graph is still retained for remaining parity and
original-target consumers. Template migration alone does not authorize coupled
legacy deletion or establish full desktop, accessibility, performance or release
acceptance. Exact verification is recorded in `validation/html-template-exports.json`.
