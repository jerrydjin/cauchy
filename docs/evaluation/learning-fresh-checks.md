# Exit-check history across saved attempts

Tracked by [JERRY-83](https://linear.app/jerryjin/issue/JERRY-83). Ordinary exits previously used the initial generated question without checking other saved lessons, and retries excluded only the current lesson's diagnostic/practice and exit attempts. Delayed checks already excluded other sessions for their target. This left a cross-attempt gap in ordinary checks.

Ordinary first exits, retries and delayed checks now share question-history collection. A mapped requirement includes all saved ordinary/delayed lesson questions and attempts with its exact target ID. Standalone passages include standalone sessions with the same complete source snapshot. Unrelated target IDs and chapter challenges are excluded. Saved generated questions are included conservatively even if unattempted. Normalized duplicate strings are deduplicated without dropping older distinct questions.

A distinct first exit is retained without another request. If that proposed exit already occurs in the history, Learn requests a replacement. Both ordinary and delayed returned questions pass a shared validator that binds the required study kind, validates question/answer fields and proof rubrics, rejects embedded hints, and rejects exact repeats after whitespace normalization. Rejection preserves the original question, draft, feedback, help, attempts and scheduling, allowing another request. The existing source-arrival check still applies before saving any result.

The production request includes the complete exclusion history or reports capacity before sending. Its total input, including schema allowance, is bounded by the existing clarification-style application limits of 6,000 characters on device and 64,000 otherwise. Exclusion history is not silently shortened. These are application request limits, not a claim about every model's native context capacity.

This policy prevents normalized exact repetition within the stated scope. It cannot identify reworded duplicates, certify a new transfer problem, validate mathematical depth beyond structural proof requirements, or establish mastery. No provider configuration, persistence schema, reader behavior or UI layout changed.

## Verification — 20 October 2026

Five new flow tests first ran on checkpoint `7b6ed3c`: **four failed and the unrelated-requirement control passed** (`/tmp/cauchy-fresh83-before.xcresult`; `/tmp/cauchy-fresh83-before.log`). The cross-session gaps affect the production history inputs; hinted/repeated/proof-rubric rejection tests also exercise the view model with tutor doubles, where production transport-specific checks previously could be bypassed.

After implementation and a sixth request-capacity regression, the **complete macOS suite passed 365 tests, zero failures or skips** (`/tmp/cauchy-fresh83-final.xcresult`; `/tmp/cauchy-fresh83-final.log`). New coverage verifies:

- Diagnostic-to-exit and practice-to-exit transitions avoid other ordinary/delayed saved questions for the same requirement, including historical practice attempts, while preserving the other session.
- An unrelated target does not replace a distinct first exit or cause an extra generation request. Standalone history is scoped to the same source snapshot.
- A whitespace-varied repeat, a question from another saved lesson and a hinted replacement leave the entire current session unchanged and invoke no save callback. A subsequent valid question succeeds without erasing earlier attempts.
- A proof retry cannot proceed without its rubric; a structurally valid return retains the required proof kind, original complete proof and earlier attempt history.
- Prompt construction retains all supplied history or fails its capacity check for cloud/on-device limits; a small history remains usable.

Existing delayed repeat rejection, source invalidation/cancellation, proof grading, bounded-session coordination and real temporary persistence/restart checks remain green in the full suite. These are production-policy and authored-tutor tests on macOS. No new manual native walkthrough, live-provider mathematical evaluation or semantic novelty claim is made. The separately prepared external feedback evaluation remains unrun pending its existing approval.
