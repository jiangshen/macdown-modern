# Editor column layout

Settings → Editor → Layout controls side margins, top/bottom margins and a maximum
writing-column width. Type a point value directly or use the stepper. Enable Limit editor width to center the column in wider panes.
Narrow panes retain the selected minimum margins. Values are native points; document
magnification changes the text while this layout remains stable.

Fresh Snowfolio profiles retain the existing 24-point margins. Imported MacDown
settings keep their original keys and values within the original UI ranges. The
centered column honors the selected maximum instead of the original 45% inset
heuristic's approximate limit. These settings never rewrite document source.

Layout changes preserve selection, native undo and the source paragraph being read.
Changed geometry waits until marked text commits. Automated native composition cases
are covered; real Chinese/Japanese IME and desktop visual acceptance remain required.
Line spacing and scrolling past the end remain separate migration work.

Exact local evidence, initial fixture corrections and the reproduced reading-anchor
fix are in [editor-column-layout.json](validation/editor-column-layout.json). The
app Settings UI test passes in exact hosted run 42443442151: direct 450-point entry,
reopen persistence, enable/disable and unchanged source/history.

Named theme fonts use their own native metrics, including empty and terminal-line
carets. Valid fallback-language hints are passed to the native font constructor. A
regression covers named/system font bases with English, Japanese, Chinese and empty
language hints; it does not replace real IME and desktop acceptance.

Persistent scrollbars can consume editor width during a native layout pass. The
column recalculates immediately after that width change; both overlay and persistent
scrollbar fixtures exercise resize, source/history and composition preservation.
The exact hosted follow-up passes both modes; source-selection visual acceptance
on the user’s desktop remains open.
