# Document host decision

Status: native `NSDocument` is the leading candidate. The shipping default has not
changed; final acceptance remains open.

The modernization brief allows SwiftUI Document APIs or `NSDocument` after
evaluation. Both candidates use Swift 6, the same byte-preserving snapshots,
TextKit 2 editor, SwiftUI workspace and preview. This decision concerns ownership
of documents, file coordination, native Undo, Versions and window restoration.

| Evidence | SwiftUI DocumentGroup host | Swift NSDocument host |
| --- | --- | --- |
| Complete accepted comparison | Latest full32 at `2e54294`:28pass/4fail (same3lifecycle failures plus invalid-read handling) | 36/36 at `2bc01b2`, no failures or skips |
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

1. Pass its complete newest UI suite, including counter, URL and CLI additions.
2. Verify the current native build physically: preview painting, active/inactive
   selection, caret, marked Pinyin composition and Undo/Redo, and VoiceOver.
3. Recheck launch/restoration, preferences, all encoding and export contracts, and
   the arm64 packaged app/helper.
4. Record the decision and remove the comparison-only DocumentGroup host after
   its remaining consumers migrate. Keep current user documents, licenses and
   the app in use protected throughout.

Making this architecture decision does not establish parser/export parity,
plugin compatibility, accessibility, performance or release readiness. Those
milestones remain separate acceptance gates.

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
