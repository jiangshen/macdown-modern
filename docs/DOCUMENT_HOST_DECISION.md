# Document host decision

Status: native `NSDocument` is the leading candidate. The shipping default has not
changed; final acceptance remains open.

The modernization brief allows SwiftUI Document APIs or `NSDocument` after
evaluation. Both candidates use Swift 6, the same byte-preserving snapshots,
TextKit 2 editor, SwiftUI workspace and preview. This decision concerns ownership
of documents, file coordination, native Undo, Versions and window restoration.

| Evidence | SwiftUI DocumentGroup host | Swift NSDocument host |
| --- | --- | --- |
| Complete accepted comparison | 26/29 at `4791020`; repeated same three lifecycle failures at `3b68499` | 36/36 at `2bc01b2`, no failures or skips |
| Autosave and saved edit Undo | Acceptance fails | Passes, including exact encoded bytes |
| Clean external changes after autosave | Two cases fail | Both pass |
| Dirty conflicts and Versions | Full acceptance remains open | All conflict choices and native Versions/Restore pass |
| Scripting | Not implemented for this host | Three real-event methods pass |
| Native tabs, separate groups, carets and independent reading positions | Partial evidence; lifecycle acceptance remains open | Actual Quit/relaunch acceptance passes |
| New counter and document links | Focused flows pass | Focused flows pass |
| Terminal installation controls | Actual chooser/link/copy/remove/collision flow passes at `d7f410e` | Same complete focused flow passes at `d7f410e` |
| Packaged command-line helper | Current full followup running | Warm acknowledged delivery passes; Save/cold acceptance pending |

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
