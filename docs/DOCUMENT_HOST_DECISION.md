# Document host decision

Status: native `NSDocument` is the leading candidate. The shipping default has not
changed; final acceptance remains open.

The modernization brief allows SwiftUI Document APIs or `NSDocument` after
evaluation. Both candidates use Swift 6, the same byte-preserving snapshots,
TextKit 2 editor, SwiftUI workspace and preview. This decision concerns ownership
of documents, file coordination, native Undo, Versions and window restoration.

| Evidence | SwiftUI DocumentGroup host | Swift NSDocument host |
| --- | --- | --- |
| Complete accepted comparison | Latest full33 at `7d0923b`:29pass/4fail (same3lifecycle cases and invalid-read handling; CLI passes) | 43/43 at `1d6bd22`, no failures or skips; complete current44 pending |
| Autosave and saved edit Undo | Acceptance fails | Passes, including exact encoded bytes |
| Clean external changes after autosave | Two cases fail | Both pass |
| Dirty conflicts and Versions | Full acceptance remains open | All conflict choices and native Versions/Restore pass |
| Scripting | Not implemented for this host | Three real-event methods pass |
| Native tabs, separate groups, carets and independent reading positions | Partial evidence; lifecycle acceptance remains open | Actual Quit/relaunch acceptance passes |
| New counter and document links | Focused flows pass | Focused flows pass |
| Terminal installation controls | Actual chooser/link/copy/remove/collision flow passes at `d7f410e` | Same complete focused flow passes at `d7f410e` |
| Packaged command-line helper | Whole CLI method passes in full2e54294;4other host gates fail | Whole warm/byte-exact Save/normal Quit/cold native-tab method1/1passes atc0c6e6f |
| Generic text viewer and invalid encoding | Positive source/bytes pass; invalid-read handling fails in full f219e25 | Complete focused1/1passes at f219e25 |

Exact source versions, run links and limitations are recorded in
[the roadmap](MODERNIZATION_PLAN.md) and `docs/validation`. Results from different
revisions are not combined into a newer full-suite acceptance claim.

The recurring SwiftUI-host failures concern the framework's document lifecycle.
The native candidate already preserves those behaviors using normal
`NSDocumentController`/`NSDocument` ownership. A second custom autosave or external
file-watcher stack is not justified to keep DocumentGroup.

Before selecting the native host as the source default:

1. **Passed:** complete43/43 at1d6bd22, retaining all prior methods and adding plug-in/update acceptance. Current44, including the new real Finder method, remains pending.
2. Physical native basic painting, inactive mixed-list selection and committed Chinese
   Undo/Redo/exact Save are observed at `7d0923b`. Active blue selection/caret, preferred
   Snowfolio style, marked Pinyin candidate phase and VoiceOver still require acceptance.
   See [native-desktop-check.json](validation/native-desktop-check.json).
3. Recheck launch/restoration, preferences, all encoding and export contracts, and
   the arm64 packaged app/helper.
4. Record the decision and remove the comparison-only DocumentGroup host after
   its remaining consumers migrate. Keep current user documents, licenses and
   the app in use protected throughout.

Making this architecture decision does not establish parser/export parity,
plugin compatibility, accessibility, performance or release readiness. Those
milestones remain separate acceptance gates.

## Historical comparison increments

The newer full native41 at f219e25 reports39pass/2fail, none skipped: CLI cold
readiness searched inactive tab contents, and reading verification repeats the system
ThemeWidgetControlViewService screenshot exception. These do not establish full41
acceptance. Tests now select normal cold-launch tabs explicitly and capture the
public main screen cropped to the same visible editor/window. Pixel samples, negative
control, restoration tolerances and all behavioral deadlines are unchanged; runtime
verification of these test corrections remains pending. The cold AX File menu also
contains two Open Recent entries (Cocoa and manual). Inspect/deduplicate ownership
before the host switch; no menu behavior was changed in this verification correction.

At2e54294 the focused reading flow now passes1/1 in67.746seconds. Actual source
glyph difference is0.0 with0.93927negative control; independent preview position,
normal Quit/relaunch, exact bytes and caret/Undo pass. Both cropped window images
were inspected. Two internal runtime warnings remain; physical preview painting and
whole41 acceptance are separate gates. The focused CLI fails earlier at warm global
source readiness with exactly overlapping windows. Verification now selects each
document before current-window source equality in both warm/cold phases. The duplicate
manual Open Recent implementation is also removed using documented Cocoa ownership;
this builds locally, with latest actual-app verification pending.

The complete focused native CLI flow passes1/1 atc0c6e6f in94.290seconds, including
all strict warm and cold source/encoded-byte checks. Its final native File menu has
one Cocoa Open Recent entry and Clear Menu; duplicate manual ownership is retired.
The exact source also passes434/91core,652CommonMark and9arm64 executables with zero
compiler diagnostics. Whole native41 run42653830905 is active at this source. Keep
native36 as the fully accepted complete baseline until that run passes; physical
Pinyin/VoiceOver/preview gates remain open because the Mac is locked.

Latest complete native acceptance is now41/41 atc0c6e6f in1844.364seconds
(run42653830905). This supersedes native36; all36old methods remain in the41-method
set. The exact code also passes434core/91suites,652CommonMark and9arm64 executables.
Six relevant full-suite screenshots were inspected.58runtime warnings remain:
57internal QoS warnings and one XCTest UTF8 string-attachment encoding warning;
functional/pixel/byte assertions all pass. Full regular at the same source is27/32.

A current native physical-check app is ready at
/private/tmp/snowfolio-native-physical-check/Snowfolio.app (~24MB including records).
It has not launched or installed. Codesign/arm64/resource/native-class checks pass;
temporary486MB build intermediates were cleaned and the regular generated project
restored. The Mac remains locked, so physical marked Pinyin, VoiceOver and native
preview/selection gates still precede the source-default/installation decision.


Current isolated physical-check app is now running at
/private/tmp/snowfolio-native-check-current/Snowfolio Native Check.app (exact `7d0923b`).
The former c0 staging path above is historical and retired. New physical evidence and
remaining limitations are recorded in native-desktop-check.json. The final focused
Finder run fails before any observed drop callback; current44 remains unaccepted.
Do not infer a source-default/install/release decision from basic desktop painting.
