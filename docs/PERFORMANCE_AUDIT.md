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
