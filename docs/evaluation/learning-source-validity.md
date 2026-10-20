# Source validity when tutor responses arrive

Tracked by [JERRY-82](https://linear.app/jerryjin/issue/JERRY-82). Learn previously checked source validity before starting every request, but only clarification and delayed-question paths checked it again on arrival. Ordinary lessons, assessments, prerequisite refresher assessments, chapter generation and fresh exit questions could apply a validly formatted result after the source-validity callback had changed.

Every call to the shared tutor-operation path now supplies its exact source snapshot. After the await, cancellation check and operation-token check, that path revalidates the source before applying a result. Chapter generation additionally rechecks its current source obligations. A rejected result does not insert teaching, replace a question, append an attempt, clear a draft/help record or reschedule review. The operation clears its busy state and reports the existing source recovery error. Clarification retains its separate error field. Repeated per-operation arrival checks were removed from clarification and delayed generation in favor of this shared gate.

Initial source checks remain in place. New chapter preparation also checks current chapter obligations before generation; selecting existing chapter work remains possible without creating new teaching. Saved work remains available for inspection. The change is confined to Learn state logic, with no reader, persistence schema, provider configuration or UI-layout changes.

## Verification — 20 October 2026

Five new suspended-response regressions first ran against checkpoint `9b77812`; **all five failed** because late results changed saved state or created work. Result: `/tmp/cauchy-source82-before.xcresult`, log: `/tmp/cauchy-source82-before.log`. After adding the shared gate, the connected Learn suites passed. A sixth regression then explicitly covered delayed-question rejection and recovery.

The final **complete macOS suite passed 359 tests, zero failures or skips**, including all six new regressions (`/tmp/cauchy-source82-final.xcresult`; `/tmp/cauchy-source82-final.log`). Coverage includes:

- A lesson returning after source invalidation creates no session, selection or persistence callback.
- Diagnostic, practice, ordinary exit and delayed exit grades returning after invalidation preserve the complete existing session: draft, previous attempts, help and review timing. They invoke no save callback.
- A retry question cannot replace the original exit question or erase the successful practice feedback after source invalidation.
- A late delayed question leaves the prior evidence/due date intact. Retrying once the source is current creates the expected separate review without changing the original session.
- New and fresh chapter generation reject both changed source and newly open source obligations, preserving complete chapter records and invoking no save callback.
- Chapter and prerequisite-refresher grading preserve the exact draft, rescue state and attempts when the source changes during assessment.
- Existing clarification source-change/cancellation checks, feedback evidence preservation, source reconciliation, connected sessions, real temporary-storage restarts, workspace/reader persistence compatibility and provider readiness remain covered by the full suite.

The suspended tutors exercise production view-model transitions on macOS while changing authoritative validity callbacks before resuming results. These are deterministic state regressions, not a GUI reproduction of changing a PDF or transcription during a live provider request. No new native layout, live-model mathematical accuracy or alternate accessibility/appearance claim is made. The previously prepared external feedback prompt evaluation remains unrun pending its separate authorization; no external model was called for this milestone.
