# Current delayed-check actions — 22 October 2026

[JERRY-104](https://linear.app/jerryjin/issue/JERRY-104) fixes a stale-action bug in delayed review. An action captured before a check started could request another question after the learner already had an active draft, then select the new review. The earlier work was retained but displaced. A focused regression against `fc535f0` reproduced the extra tutor request (`2` instead of `1`, `/tmp/cauchy-review95-before.xcresult`).

`LearningViewModel.startDelayedReview` now treats the action as a request for that exact requirement and resolves the current queue from saved sessions. `LearningDocument` supplies the actual current map through a weakly captured resolver. Standalone view models resolve the same queue against their supplied unit. A newly active delayed check is selected without requesting a tutor, changing the draft/help, rewriting timestamps or saving a new session. The original recommendation's copied session and due date do not authorize new work.

Completed or rescheduled checks, removed saved records, lost independent eligibility, changed requirement wording and current source blockers cannot be restarted from an earlier action. An unavailable action explains that work is saved and directs the learner back to the learning path. The existing exact requirement identity and current-source checks remain in force. Earlier attempts, grades and schedules are retained unchanged.

Question generation also re-resolves the queue when the asynchronous response returns. A changed objective, new source obligation or missing map rejects that response without appending a session or changing selection. Course reorganization alone preserves the same requirement and allows the response. A new accepted review records the current triggering session and due date. Existing question-history, fresh-question validation and recorded help policy remain unchanged.

## Verification

Five new regression methods exercise:

- stale actions across concepts, proofs and applications: select the already active draft, preserve complete sessions and make no second tutor request or save;
- a completed review with a future schedule, a future-rescheduled immediate check, helped/ineligible evidence and removed records, including serialized restart inputs;
- suspended question generation while requirement wording, source obligations or map availability change, beside a successful course-reorganization control;
- production document wiring after serialized map changes, with old actions rejected before tutor creation while sessions, selection and the map remain unchanged;
- a real disposable fixture persistence round trip: retain the exact delayed draft, outside-help attribution, session ID, all session fields and complete map while an old action reopens it before and after cold restart.

The final complete macOS suite passes **408 tests, zero failures or skips**, with no reported runtime warnings (`/tmp/cauchy-review104-full.xcresult`, `/tmp/cauchy-review104-full.log`). Tests use an isolated `fc535f0` archive in `/tmp/cauchy-review95-validation` plus four byte-identical implementation/test inputs. SwiftMath remains pinned at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`, with the resolved package cache and automatic package resolution disabled. `git diff --check` passes. No new Swift files or generated-project changes are needed.

These are offline state-machine and real-persistence checks with authored tutor responses. No live model request, learner-data evaluation, new native GUI observation or educational-efficacy result is claimed. The normal library, installed app, reader implementation and system settings remain unchanged. The separate JERRY-92 native export-panel return/save/cancel checks remain pending because native window retrieval times out; their exact verified and unverified behavior is recorded in [saved-work export evidence](learning-work-export.md).
