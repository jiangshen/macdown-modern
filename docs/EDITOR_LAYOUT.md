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
Scrolling past the end remains separate migration work.

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

## Line spacing

Settings → Editor → Layout → Line spacing accepts 0...100 native points, including
fractional values. Explicit MacDown editorLineSpacing values import; fresh Snowfolio
profiles retain zero. Spacing changes preserve source, selection and native history,
and wait until composition completes. Wrapped/cached paragraphs and empty terminal
carets are checked against native metrics across themes and zoom.

Queued preview/source scroll input now carries ordering context so an older move or
report cannot take control from a newer gesture. The controlled native regression
checks both directions. Local full suite and sanitizer results, failures retained
during investigation, exact sources and remaining visual gates are recorded in
[editor-line-spacing.json](validation/editor-line-spacing.json). Exact hosted run 42453343180 passes 347 package tests, 652 CommonMark examples and
all 19 app UI methods. Settings and the continuous light/default-font source selection
are inspected. Dark user-desktop selection, real IME/VoiceOver and actual modern caret
paint/native-reference equivalence remain open. Public caret API metrics are covered;
they do not establish rendered-indicator equivalence.
