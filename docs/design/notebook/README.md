# Notebook document theme

An original, Notion-inspired presentation for Snowfolio’s plain Markdown documents.
Reference: [Notion’s public page styling guidance](https://www.notion.com/help/customize-and-style-your-content), inspected 2026-11-06.
The neutral page, readable hierarchy, restrained inline code, quote rules, task lists,
light table grid, Default/Serif/Mono choices and bounded reading width inform this design.
This is not a copy of Notion’s source or assets, and no Notion integration is required.

`DocumentStyle` is the shared value used by the preview and styled HTML/PDF/print
pipeline. Presentation changes patch the existing stylesheet without reloading the
page or replacing content nodes. Print uses a light paper palette. Source text and
the independently chosen source-editor font remain untouched.

`Notebook.md` is the runtime visual fixture; `Preview.png` shows the current light
native preview. Real WebKit tests cover both appearances, minimum 4.5:1 text contrast,
heading hierarchy, reading width, a 320-point layout, stable nodes and reading anchor
after style changes. Export integration verifies the captured font and size reach
WebKit even if preferences change after the snapshot.

Remaining: styled source-editor syntax, custom CSS/theme migration, real high-contrast system inspection, full light/dark visual comparison,
and typography/PDF fixture comparison for each font choice. The theme requirement
and the overall modernization are not yet complete.


## Optional callouts

`Callouts.md` demonstrates the five canonical top-level alert markers (`NOTE`, `TIP`,
`IMPORTANT`, `WARNING`, `CAUTION`), each on its own quoted line. `Callouts.png` shows
the native preview with the Default document font. Canonical syntax follows
[GitHub’s alert documentation](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts).
The quiet surfaces and original decorative text symbols keep the Notebook visual style.

The parser captures the original AST and outline before decorating recognized quotes.
Only a fixed enum label/symbol and native integer positions enter the trusted wrapper;
document children retain normal cmark HTML/URL escaping. Literal/escaped markers, code,
reference links, unknown kinds and nested quotes remain normal Markdown. Disable
“Notes, tips and warnings” in Markdown settings for ordinary quotes everywhere.
This setting also applies to styled/plain HTML, PDF and print output.

Native checks verified callout labels, ordinary quote fallback, restored Default font,
and re-enabled callouts. Closing Settings intermittently caused UI inspection timeouts;
a diagnostic sample showed an idle event loop with no crash report. Returning to the
document through the Window menu allowed inspection. This is an open UI validation
issue, not evidence that the whole settings/window workflow is finished.


## Native emoji picker and distinct MacDown direction

The user requested closer inspection of their open Notion interface, then refined the
direction: keep the current attractive content design, differentiate MacDown, and follow
Apple’s current guidelines with Liquid Glass where appropriate. The Notion page/picker
was inspected read-only as a visual reference. The fixtures and screenshots here contain
original demonstration text. Native toolbars/popovers carry the glass; document surfaces
remain opaque and readable. No additional glass layer is added to the document itself.

`RefinedCallouts.png` shows the larger icon gutter, soft type-specific surfaces and more
compact hierarchy. `EmojiPicker.png` shows the native transient NSPopover, containing
search, category selection, recent choices, callout suggestions, random choice and reset.
The picker uses system emoji glyphs and semantic native controls. It respects Reduce
Motion for presentation and uses native popover appearance rather than a custom blur.

Click a callout’s emoji to open the picker. Choosing an emoji writes a single explicit
Notebook extension on the marker line, for example `> [!IMPORTANT] 🎯`. A custom emoji
puts the content directly alongside the icon; the kind label remains accessible. Reset
removes the custom suffix and restores the canonical type icon/visible kind label.
Other Markdown viewers may display the marker/emoji as ordinary quote text; the file
remains portable plain Markdown. Exports contain inert icon spans, never editing links.

Unicode Emoji 18.0 data is bundled under Unicode License V3 (see `EmojiData.md`). Parser
validation uses the full catalog; the native picker filters choices against this Mac’s
emoji font to avoid missing-glyph boxes and decomposed sequences. Font filtering runs
off the main actor and is cached for later openings. Recent choices stay local.

Native checks covered opening from an icon, text search, selecting an emoji, undo/redo
from preview mode, saving and re-opening the chosen icon, recent choices, and final
font-filtered display. Unit/integration checks cover multi-scalar sequences, flags,
skin tones, metadata escaping, stale/mismatched source rejection, exact trailing
whitespace and CR/LF/CRLF preservation, and native undo/selection. The older Settings
inspection issue and full accessibility/keyboard/system-appearance audits remain open.
