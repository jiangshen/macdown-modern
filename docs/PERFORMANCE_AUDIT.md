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
