# Snowfolio performance audit

Measured 2026-11-06 on an Apple M4 Mac mini (Mac16,10), 16 GiB RAM, macOS 27.2,
Swift 6.4.2, native arm64 Release. The core source baseline is commit `715565c`.
The development-only `Tools/PerformanceAudit` executable calls the actual
`MarkdownProcessor`, including the owned AST, HTML, heading/callout/GFM decoration,
code highlighting and source-syntax ranges. It is not linked or bundled into the app.

## Measurements

Each workload/size runs in a separate process: one first render and three complete
rerenders after a small edit. Times are milliseconds; memory is whole-process peak
RSS in MiB through all four renders. Sizes are decimal bytes plus a short checkpoint.
The mixed workload repeats headings, Unicode, links, inline styles, lists, callouts,
tables and Swift code fences. The long-line workload stresses a Unicode paragraph
with repeated inline spans. Three warm samples do not establish a p95.

| Workload | Fixture bytes | First render ms | Warm median ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| prose | 100,000 | 2.2 | 1.5 | 11.5 |
| prose | 1,000,000 | 19.5 | 16.0 | 37.5 |
| prose | 10,000,000 | 224.6 | 171.8 | 280.5 |
| mixed | 100,000 | 389.4 | 9.1 | 48.8 |
| mixed | 1,000,000 | 443.2 | 97.6 | 140.8 |
| mixed | 10,000,000 | 1518.2 | 1034.9 | 979.3 |
| long-line | 100,000 | 3.7 | 3.3 | 14.8 |
| long-line | 1,000,000 | 37.6 | 36.1 | 65.2 |
| long-line | 10,000,000 | 415.0 | 443.5 | 613.2 |

These measurements exclude application launch, file I/O, native typing/layout,
WebKit publication, math, diagrams and exports. They cannot establish app-level
responsiveness, energy use or a memory leak. The app already pauses automatic
preview above 1 MiB; the 10 MB manual-render workload deliberately exercises the
pipeline beyond that guardrail.

## Findings and next work

- Warm 100 KB core rendering is fast in these samples, but the first mixed render
  takes about 389 ms. Separate highlighter startup from first-paint behavior before
  claiming the roadmap's 250 ms preview target.
- A 10 MB mixed document takes about one second per warm full rerender and reaches
  about 979 MiB peak RSS. Reduce the overlapping native AST, owned nodes, syntax
  intervals/events and HTML lifetimes, then measure again. Peak RSS alone does not
  identify a leak; use Allocations and repeated open/close checks for retention.
- A 15-second Instruments CPU Profiler recording of repeated 10 MB mixed renders
  collected 47,405 samples after the first two seconds. Cycle-weighted inclusive
  shares include syntax-run construction (15.64%), native parser finish (9.20%),
  parser feeding (8.55%) and heading decoration (7.04%). Dictionary lookup/hash,
  memory movement/allocation and node traversal feature among the leaf hotspots.
  Inclusive shares overlap; these are CPU-cycle shares, not wall-clock percentages.
- The hosted document UI run also reports seven priority-inversion warnings. Its
  cause is not established by this CLI profile. Use a system trace of the actual app
  before changing task priority or attributing the warning to first-party code.
- Code inspection found no synchronous main-queue dispatch, semaphore waits or
  periodic timers in current first-party Swift. Full editor/model comparisons and
  complete DOM/AST traversals remain review targets for large documents; this is
  a code-review observation, not proof that the UI never blocks.

Full M6 remains open: native typing p95, launch/open, compositor publication, scrolling,
representative/adversarial fixtures, memory growth, cancellation, CPU/energy and release
budgets. Do not infer any of these from the core timings.

## Reproduction

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift build --package-path Tools/PerformanceAudit \
  --scratch-path /private/tmp/snowfolio-performance-build --arch arm64 -c release
/private/tmp/snowfolio-performance-build/out/Products/Release/PerformanceAudit mixed 1000000 3
```

Use `prose`, `mixed` or `long-line`, 1,000–10,000,000 bytes, and 1–100 warm iterations.
The executable emits JSON. Inspect the build's bin path if SwiftPM changes its output
layout. Run measurement processes sequentially, without Instruments attached; profile
separately. Preserve OS/hardware/toolchain and fixture details when comparing results.
Raw samples and the summarized CPU profile are in `validation/performance-baseline.json`.

## Cleanup

Ten obsolete generated folders and the retired Travis configuration/uploader were
moved with the native macOS Trash API. Trash was not emptied. Original-to-Trash paths,
logical/allocated byte totals and preservation decisions are recorded in
`validation/project-cleanup.json`. Moving bytes to Trash reduces active build clutter;
it does **not** free disk space until Trash is emptied. No instruction to empty it was
inferred. Current app output and current validation reports remain available.


## Source-coordinate mapping cost — 2026-11-07

The physical inline-coordinate correction adds a measured parsing cost. The comparison
uses exact pre-change commit `a32f279` and the updated release arm64 audit executable,
three fresh processes per version/workload/size, one first render and five warm renders
per process, with alternating version order and sequential execution. Builds and
Instruments do not overlap the timing matrix. Values below are the median of the three
process warm medians; they are not typing latency or p95.

| Workload | Bytes | Before ms | After ms |
| --- | ---: | ---: | ---: |
| prose | 100,000 | 1.53 | 2.12 |
| prose | 1,000,000 | 13.70 | 16.41 |
| prose | 10,000,000 | 150.92 | 172.32 |
| mixed | 100,000 | 8.26 | 8.66 |
| mixed | 1,000,000 | 86.77 | 92.30 |
| mixed | 10,000,000 | 895.95 | 964.09 |
| long-line | 100,000 | 3.24 | 3.34 |
| long-line | 1,000,000 | 34.89 | 35.23 |
| long-line | 10,000,000 | 397.44 | 414.73 |

The initial implementation cost about 0.9 ms for the 100 KB mixed case. A bounded CPU
profile of the 10 MB prose workload identified redundant line scanning and descendant
traversal in mapping. Native finalized single-line bounds now avoid another scan, and
verified identity maps skip descendant walks. The final mixed cost is about 0.4 ms at
100 KB and 5.5 ms at 1 MB. This is a correctness cost, not a performance improvement over
the pre-change parser. Peak RSS varies across the fresh-process samples; no memory
improvement or absence of leaks is inferred. The 10 MB full-render paths remain outside
the app’s automatic preview size guard and remain M6 optimization targets.

The profile saved and exported 35,529 CPU samples after the first two seconds of a
10.38-second bounded recording. Its command exited 54 after saving the time-limited
trace; the decoded CPU data and exit status are both retained in the ledger. Inclusive
sampled cycle shares overlap and are not wall-clock proportions. Full methodology,
per-process medians/RSS, raw artifact paths and limitations are recorded in
`validation/source-coordinates.json`. These measurements do not close native app typing,
WebKit publication, energy, memory-growth or other M6 acceptance gates.


## Table normalization provenance cost — 2026-11-07

This comparison uses exact previous core/parser commit `0ee583b` and the corrected
worktree with identical audit harness source. It includes three fresh processes per
version/workload/size, one first render plus five warm full rerenders each, alternating
version order. Timing processes run sequentially without builds or Instruments. The
values are medians of three process warm medians, not UI latency or p95.

| Workload | Bytes | Before ms | After ms |
| --- | ---: | ---: | ---: |
| prose | 100,000 | 1.83 | 2.13 |
| prose | 1,000,000 | 16.47 | 16.84 |
| prose | 10,000,000 | 176.83 | 180.54 |
| mixed | 100,000 | 8.88 | 8.82 |
| mixed | 1,000,000 | 94.51 | 94.73 |
| mixed | 10,000,000 | 977.55 | 982.69 |
| long-line | 100,000 | 3.32 | 3.27 |
| long-line | 1,000,000 | 35.63 | 35.78 |
| long-line | 10,000,000 | 416.16 | 411.97 |
| escaped-cell | 100,000 | 0.90 | 1.23 |
| escaped-cell | 1,000,000 | 9.05 | 12.37 |
| escaped-cell | 10,000,000 | 92.09 | 125.82 |

Ordinary workloads are close in these samples. The new `escaped-cell` workload puts
repeated `a\|` sequences in one large GFM cell followed by strong text. Correct source
coordinates add about 0.33 ms at 100 KB, 3.32 ms at 1 MB and 33.73 ms at 10 MB. The 10 MB
escaped case records roughly 228 MB peak RSS after the change versus 148 MB before;
sparse provenance has a cost on deliberately dense input. Peak RSS is a process high
water mark, not a leak measurement. Metadata grows geometrically and validation walks
the original native escape events linearly rather than searching each byte separately.

These render-only samples exclude actual native typing/layout, WebKit publication,
file I/O, math and diagrams. Ten MB full renders exceed the automatic-preview size
guard. No application responsiveness, energy or memory-growth acceptance is inferred.
Raw samples, process medians/RSS, methodology and checksum are retained in
`validation/table-source-coordinates.json`. The audit CLI now accepts `escaped-cell`
alongside `prose`, `mixed` and `long-line`. Full M6 remains open.


## Paragraph/table partition cost — 2026-11-07

The `table-prefix` workload is one large Unicode paragraph ending in escaped inline
code and strong text, followed immediately by a table. The previous implementation
omitted that paragraph's source ranges/styles and changed its literal backslash. This
comparison measures the complete corrected render, including the newly accurate work.

Both release arm64 versions use identical updated audit harness source; the previous
core/parser is exact commit `1c53ba3`. Three fresh processes per case/version perform
one first render and five warm full rerenders. Version order alternates; no builds or
Instruments overlap. Values are medians of process warm medians, not app latency/p95.

| Workload | Bytes | Before ms | After ms |
| --- | ---: | ---: | ---: |
| mixed | 100,000 | 8.87 | 8.83 |
| mixed | 1,000,000 | 93.47 | 95.56 |
| mixed | 10,000,000 | 990.43 | 982.50 |
| table-prefix | 100,000 | 0.60 | 0.98 |
| table-prefix | 1,000,000 | 5.63 | 9.95 |
| table-prefix | 10,000,000 | 57.54 | 100.74 |

Correct paragraph source metadata adds about 0.37 ms at 100 KB, 4.32 ms at 1 MB and
43.21 ms at 10 MB in these samples. An initial implementation also mapped the complete
prefix during the split; native recognition already proves its full-line endpoint, so
the final split callback maps only the suffix. The initial and final raw matrices are
retained for review. Ordinary mixed samples are close; no speedup is inferred.

Peak RSS varies across process samples and cannot establish leaks or memory-growth
acceptance. These render-only measurements exclude native input/layout, WebKit
publication, file I/O, math and diagrams. Ten MB renders exceed the automatic-preview
guard. Full M6 remains open. Methodology, raw checksums, per-process timings and RSS
are in `validation/table-paragraph-split.json`.


## Automatic-link provenance cost — 2026-11-07

The `autolinks` workload contains an encoded email, a Unicode URL and ordinary text.
The corrected renderer now creates exact email source/style ranges that were absent
before. This comparison measures the complete corrected workload.

The before core/parser is exact commit `f86d87f`, with identical updated audit harness
source in both release arm64 builds. Three fresh processes per case/version perform
one first render and five warm full rerenders. Version order alternates; timing
processes run sequentially, without builds or Instruments. Values below are medians
of process warm medians, not app latency or p95.

| Workload | Bytes | Before ms | After ms |
| --- | ---: | ---: | ---: |
| prose | 100,000 | 1.77 | 1.78 |
| prose | 1,000,000 | 16.86 | 17.24 |
| prose | 10,000,000 | 188.15 | 184.33 |
| mixed | 100,000 | 9.18 | 9.09 |
| mixed | 1,000,000 | 96.57 | 95.86 |
| mixed | 10,000,000 | 996.31 | 1004.71 |
| autolinks | 100,000 | 5.60 | 7.32 |
| autolinks | 1,000,000 | 60.55 | 79.09 |
| autolinks | 10,000,000 | 650.46 | 879.55 |

Ordinary workloads are close in these samples. Link-heavy corrected rendering adds
about 1.72 ms at 100 KB, 18.54 ms at 1 MB and 229.09 ms at 10 MB. It retains owned
decoded provenance and builds additional email syntax intervals; these are correctness
costs. Full decoded-buffer identity is checked once before recognized offset partitions,
rather than scanning the remaining suffix for every address.

Peak RSS varies across processes and cannot establish leaks or memory growth. These
render-only measurements exclude native input/layout, WebKit publication, file I/O,
math and diagrams. Ten MB renders exceed the automatic-preview guard. Full M6 remains
open. Methodology, per-process timings/RSS, harness checksum and all 54 raw process
samples are recorded in `validation/automatic-link-source.json`.


## Native input normalization source cost — 2026-11-07

Exact baseline `dae72fc` and the final worktree use the same release arm64 harness.
Three fresh processes per version/case each render once, then perform five full warm
rerenders; version order alternates. Measurement processes run sequentially without
builds or Instruments. Values are medians of three process warm medians, in ms.

| Workload | Bytes | Before ms | After ms |
| --- | ---: | ---: | ---: |
| prose | 1,000,000 | 17.162 | 16.965 |
| prose | 10,000,000 | 188.771 | 184.977 |
| mixed | 1,000,000 | 97.735 | 97.966 |
| long-line | 1,000,000 | 37.033 | 36.590 |
| table-prefix | 1,000,000 | 10.273 | 10.125 |
| autolinks | 1,000,000 | 80.159 | 78.599 |
| nul | 100,000 | 6.110 | 7.110 |
| nul | 1,000,000 | 62.809 | 73.769 |
| nul | 10,000,000 | 681.533 | 797.861 |

Ordinary samples remain close. The `nul` workload repeats authored U+FFFD, two input
NULs, Unicode strong text and inline code in short paragraphs. Its source ranges are
incorrect before the change and correct afterward, despite matching syntax-run counts.
Correct placement costs about 11 ms at 1 MB and 116 ms at 10 MB in this matrix. The 10 MB
case remains above one GiB peak process RSS in both versions; a high-water mark does not
establish a leak, and small RSS differences do not establish a memory improvement.

These measurements exclude native app typing/layout, WebKit publication, file IO,
math/diagrams and exports; they do not establish p95, energy or full M6 acceptance.
Raw samples, binary/harness hashes and limitations are recorded in
`validation/input-source-projection.json`. The standalone harness also accepts `nul`.


## Reading-style bridge and byte identity — 2026-11-07

The separate development-only `ReadingStyleAudit` executable compares the exact
`dd69d88` style-update script with the current script in a hidden 700×400 native
WKWebView host. Nine fresh processes run sequentially, three per HTML size. Each
process alternates version order and 16/18px Notebook typography, takes ten samples
per version, discards its first sample and retains the median. The table reports
the median of those three process medians. Selection remains checked throughout.
No build or Instruments run overlaps the timing matrix.

| Artificial HTML bytes | Before ms | After ms |
| --- | ---: | ---: |
| 100,000 | 6 | 6 |
| 1,000,000 | 58 | 57 |
| 10,000,000 | 621 | 615 |

These values cover isolated-world JavaScript and forced CSS layout only. Observed
`performance.now` resolution is one millisecond; the differences do not establish
an improvement. They exclude root-transition cost, publication IPC, painting,
parsing, real typing, app launch, memory retention and energy. Raw samples, fixture
sizes, script/binary hashes and scope are in
[reading-style-timing.json](validation/reading-style-timing.json).

Exact CSS/HTML identity must compare UTF-8 bytes because Swift String equality
normalizes Unicode equivalence. An initial collection comparison cost about
2.213 ms per unchanged 1 MB string. The actual `UTF8Text` helper now borrows both
contiguous buffers, returns immediately for shared storage and otherwise performs
a bounded byte comparison, retaining a safe collection fallback for foreign storage.
A separate Release arm64 external-library probe rotates 64 native strings and
makes 1,000 calls per mode: stdlib shared-storage comparison totals 2,212.750 ms,
helper shared-storage calls total 0.003458 ms, and helper independent-buffer calls
total 30.884 ms. All 3,000 answers are checked. These are helper timings, not
end-to-end typing latency or p95. Byte-boundary/foreign-storage regression tests
and Address Sanitizer pass. Probe details are recorded in
[reading-styles.json](validation/reading-styles.json).

The original core benchmark source remains unchanged; this separate executable
keeps WebKit style experiments out of its dispatch and workload logic. Full M6
app performance and memory/energy acceptance remain open.


## Validation-artifact cleanup — 2026-11-07

After the custom-style checkpoint passed 307 package tests and 11 native app UI tests,
four exact agent-generated scratch/download directories were moved with the native
Trash API: three superseded native validation bundles and the initial temporary CSS
parser build dependency folder. This removed 424,496,368 logical
bytes (447,733,760 allocated bytes) from active scratch paths.
Trash was not emptied, so this does not claim recovered disk space.

The current app output, current hosted evidence, source, pinned build inputs, compact
historical logs/screenshots and user documents remain available. Original-to-Trash
paths, marker hashes, reasons and verified destinations are appended to
[project-cleanup.json](validation/project-cleanup.json). This is artifact housekeeping;
full app performance, energy, memory retention and priority-warning attribution remain
open.


## Native test-host animation correction and template cleanup — 2026-11-07

The initial full template regression run timed out in the unchanged native diagram
workers. A one-second sample of that exact test helper reached the dispatch soft
limit of 64 in all 640 samples: 64 AppKit `NSAnimation _runBlocking` workers were
waiting while the main thread stayed in its run loop. The run was interrupted after
capturing the evidence. Setting `animationBehavior = .none` in 49 fixture windows
preserves the behavioral assertions and leaves application window behavior unchanged.
The complete rerun passed 318 tests / 67 suites in 32.639 seconds including build;
11 template sanitizer tests / four suites also passed. These observations concern
test-host reliability, not end-to-end app typing or painting performance.

The final hosted checkpoint passed the same package totals, 652 CommonMark examples,
and 13 native app UI tests. It still records 24 priority diagnostics and two AppIntents
metadata notices; attribution and full M6 memory/energy/latency gates remain open.
See `validation/html-template-exports.json` for exact scope, samples and raw hashes.

After the expanded checkpoint passed, three superseded custom-CSS validation folders
were moved to Trash: 2,153 files, 141,866,410 logical bytes and 149,331,968 allocated
bytes. Their recovery markers and destinations were verified. Trash was not emptied;
this removes duplicate active scratch files and does not claim recovered disk space.
Exact recovery paths are appended in `validation/project-cleanup.json`.


## Code-presentation validation and artifact cleanup — 2026-11-07

The final contrast-corrected checkpoint passes 329 package tests / 70 suites, 652
CommonMark examples and 15 native app UI tests. Twenty-six priority diagnostics and
two AppIntents metadata notices remain unattributed. One existing native caret metric
case differed intermittently from its native reference; unchanged focused cases and
the final complete suite pass. Failure diagnostics now include font/typing attributes;
production font code and assertions are unchanged. A preview-led zoom timeout in an
earlier concurrent local run also has no proven cause. These are preserved in
`validation/code-block-presentation.json`; full app latency/energy/memory acceptance
and desktop painting/IME/VoiceOver remain open.

Four superseded agent-generated template download folders were moved to native Trash
with original/destination marker verification: 4,344 files, 290,155,859 logical bytes
and 305,160,192 allocated bytes. Current raw evidence, builds/source and compact prior
reports/screenshots remain. Trash was not emptied, so no disk-space recovery is claimed.
Recovery paths are recorded in `validation/project-cleanup.json`.


## Unsaved asset access and validation cleanup — 2026-11-07

The read-only folder grant survives frozen export snapshots and individual asynchronous
preview reads, then releases when its owners finish. Native tests verify that switching
roots no longer reuses a previous same-name decoded image. These establish lifetime
and cache correctness, not lower typing latency or whole-app memory/energy acceptance.
The accepted run passes 334 package tests and 17 native UI methods; 30 priority diagnostics
and two AppIntents metadata notices remain without proven first-party attribution.

Two superseded code-presentation downloads moved to native Trash with hash/destination
verification: 2,127 files, 144,627,380 logical bytes and 151,990,272 allocated bytes.
Current raw evidence and compact historical screenshots/reports remain. Trash was not
emptied, so this does not claim disk-space recovery. Exact recovery paths are recorded
in `validation/project-cleanup.json`.


## Source-column layout and reading-anchor correctness — 2026-11-07

Layout derives bounded native-point geometry without inspecting document contents.
The native text container updates only when its geometry changes. Full native
regression passes 339 package tests / 73 suites in 45.704 seconds including build;
17 sanitizer tests / four suites pass. These totals cover different workloads than
prior runs and do not establish an app latency or memory/energy improvement.

A linked/unlinked workspace regression reproduced a paragraph shift when a column
widened. Keeping the original source-character anchor instead of adopting an earlier
wrapped-line start fixes that reproduction. An existing preview-led source zoom
timeout occurred in one full run; focused and final complete runs pass. Cause remains
unproven. Failure diagnostics now retain native driver/anchor state and DOM scroll
facts without changing assertions/timeouts. Exact evidence and limitations are in
`validation/editor-column-layout.json`; full M6 measurements remain open.


The final main-checkout run reproduced the earlier typography mismatch. A language-tagged
system-font base converted to a named Helvetica face yields a 22-point caret versus
a 26-point native reference; named Menlo bases pass. Native face-descriptor construction
with a forwarded valid fallback-language hint corrects the controlled case. The final
complete run passes 340 tests / 73 suites in 44.626 seconds, and 18 ASAN tests / four
suites pass in 23.841 seconds, including build. These are correctness/test timings,
not app latency or energy measurements. The earlier preview-led source timeout remains
unproven; real IME, desktop typography and full M6 acceptance remain open.

### Persistent scrollbar column correction

The hosted column-layout diagnostics and an explicit persistent-scrollbar fixture
reproduce a stale 440-point column in a 463-point native editor. The existing
geometry function now runs immediately after width changes; height-only changes
remain outside this path. Setting needsLayout alone did not schedule another pass.
Focused scrolling/zoom and all 340 package tests pass locally. This is a correctness
fix; no runtime performance improvement or source-selection visual acceptance is claimed.
Exact hosted run 42443442151 passes 340 package tests, 652 CommonMark examples and
all 18 native UI methods. Its raw log retains 31 priority diagnostics and two
AppIntents metadata notices; runtime attribution remains open.
See validation/editor-column-layout.json for exact before/after logs and source hashes.


## Line spacing and scroll input correctness — 2026-11-07

The default zero-spacing editor avoids paragraph copies unless earlier typing metadata
requires normalization. Preference refresh invalidates cached presentation without
explicitly laying out offscreen text. Terminal insertion metrics are cached per font.
Input reporting sends a small immediate gesture message and retains frame-coalesced
position updates. Sequence checks prevent an older queued movement or report from
overwriting newer pane input. These are bounded correctness changes, not a measured
latency/energy improvement.

Final local suite passes 347 tests /74 suites in 49.145 seconds including build;
28 sanitizer tests /six suites pass in 26.322 seconds including build. Sanitizer
acceptance does not establish leak or whole-app memory/performance acceptance.
Native app build-for-testing passes; 19 UI methods compile. Exact hosted execution,
new screenshots and runtime warning attribution remain pending. Earlier scroll/caret
failures and corrected fixture readiness are retained in validation/editor-line-spacing.json.
Full M6 measurements and fresh source-selection/real IME/VoiceOver stay open.


### Exact hosted line-spacing follow-up

422da99/run42453343180 passes 347 package tests /74 suites, 652 CommonMark examples
and all 19 native UI methods. Twenty-eight priority runtime warnings and two AppIntents
metadata warnings remain unattributed; changes in warning counts between runs do not
establish a performance improvement. The source selection image is continuous in
light/default-font presentation. Actual modern caret paint/native-reference and dark
desktop checks remain open even though native rectangle metrics pass.

A screenshot download hit a full volume. Standard clean actions removed only
regenerable output from the isolated agent-created Xcode/SwiftPM build folders, after
architecture and passing results were recorded. Source, raw result bundles, logs and
recovery records remain. The partial download moved to native Trash; Trash was not
emptied and no space recovery is attributed to that move. Details are in
validation/project-cleanup.json. This is capacity maintenance, not an app performance
measurement or a claim that the Mac's general storage audit is complete.
