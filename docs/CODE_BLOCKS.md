# Code blocks in reading previews and exports

Settings → Appearance → Code Blocks offers syntax colors, a code theme,
**Show code line numbers**, and **Code label**. Line numbers and labels remain
available with syntax coloring turned off. Existing `htmlLineNumbers` and
`htmlCodeBlockAccessory` values migrate to the new controls; the original accessory
values remain 0 = None, 1 = Language name, and 2 = Custom. Fresh profiles keep both
accessories off. The source editor is unchanged by these reading options.

Language name uses the human-readable names and aliases from the pinned Prism
release, such as HTML, C++, Objective-C and JavaScript. Unknown names remain visible
as text. In Custom mode, the first colon separates the language from the label:

````markdown
```swift:Snowfolio.swift
let message = "Hello"
```
````

The label can contain spaces and Unicode. It is text, never HTML. Colon metadata is
interpreted only in Custom mode, as in the original renderer. Unlabelled, unknown
and indented code blocks can also receive line numbers. Successful equation and
diagram blocks keep their own rendering; unsupported diagrams that fall back to
code can use the code options.

The parser supplies the code literal and fence metadata. A bounded Swift renderer
adds labels and logical line wrappers after AST/source-syntax collection. It never
rewrites Markdown or reparses it with regular expressions. For highlighted code,
Swift balances only the pinned highlighter's generated span envelopes, retaining
attributes and HTML entities across multiline tokens. Plain code needs no span
splitter. No Prism DOM plugin or document JavaScript executes in the preview or
standalone export.

Numbers are generated inside empty, non-selectable, `aria-hidden` elements. The
rendered code text and code-only selection stay identical to the parser's code
literal, including blank lines, Unicode, nonbreaking spaces and its terminal newline.
Wrapped logical lines keep one number aligned with their first visual line. Default
number text keeps full foreground contrast; the divider is subtle and strengthens
with Increase Contrast. The
existing isolated preview bridge restores forward/backward selections when a code
block's source position and text are unchanged through a presentation update.
Actual code edits do not reuse stale code offsets.

Standalone HTML, PDF and print snapshots contain the needed code CSS independently
of the document-style and highlighting choices. Copy HTML remains semantic fragment
output, as before; a consumer may supply its own styling. The None reading style now
starts the HTML save panel with **Include document styles** off, while code
highlighting remains independent. Choosing None also avoids an empty document-style
sheet in PDF preparation.

Numbering is bounded to 1 MiB of code and 10,000 logical rows per block, 4 MiB of
highlighter markup, 64 nested generated spans and 8 MiB of numbered output. A limit
or unsupported generated envelope retains complete ordinary code (and existing
highlighting when available) and displays a reading notice. No partial numbered
block is published. Source/AST positions and native editing history remain unchanged.
The highlighter's existing 65,536 UTF-16-unit input limit remains independent.

Language-title metadata is reproduced from the same checksum-pinned Prism 1.30.0
archive as the existing grammars. The build verifies the new JSON and retained MIT
notice; Node and network access are used only by the reproduction tool, never by
ordinary application builds. Exact tests, native selection/PDF evidence and remaining
acceptance limits are recorded in `validation/code-block-presentation.json`.
