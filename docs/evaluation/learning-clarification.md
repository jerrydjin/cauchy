# Contextual Learn questions — 18 October 2026

The [20 October saved-feedback extension](learning-feedback.md) adds a distinct discussion for an assessed attempt while preserving its submitted evidence. The original pre-answer context and help rules below remain in effect; historical question explanations remain read-only after assessment.

JERRY-62 adds **Ask about this step** to teaching and a contextual question action to assessment help. The course page remains focused on its next action. The panel starts compact, with the current step visible, one question field and an explicit return action. After a reply, its context and source details collapse; earlier exchanges are disclosed rather than shown as a growing transcript.

## State and evidence boundaries

Each exchange retains the exact visible context, question, reply, supplied page indices, the IDs of the last two context-specific exchanges supplied to the request, provider/model and time. Drafts are saved per context. A fresh assessment question has a different context key; an earlier question cannot submit new teaching against the current step. The source is checked before sending and again before accepting a late reply. Cancellation, malformed references and provider errors preserve the question and original answer without fabricating a reply.

Teaching questions do not create attempts or learning credit. A valid reply exposed during an unanswered assessment, or reopening a saved explanation while answering, records help. Revision keeps that help. A new ordinary independent question starts a new help record; delayed review retains its separate sticky help record. Already graded answers allow saved replies to be inspected read-only, without changing the submitted evidence. Clarification requests never include hidden diagnostic, practice or exit answer keys.

The model declares one of three bases: supplied notes, additional explanation or insufficient source. A notes-based reply needs at least one exact, continuous quote from a supplied page. Every citation is checked against that page, and a correction ID is assigned from the actual supplied transcription rather than trusted from model output. Matching quotations establish source location, **not mathematical entailment**. The panel states that distinction in Source details. Additional explanation and insufficient-source replies carry their label with the reply.

Existing session decoding remains compatible because the new fields are optional. The existing learning sidecar and reading-session Codable archive retain them without changes to reader persistence. Current lesson position, answer drafts and assessment rules remain separate from clarification state. The complete reader workstream is outside this change; the generated project adds only the new Learn model, view and test file references.

## Automated verification

An isolated source snapshot based on `e29c97e`, excluding unrelated shared reader/connector/website edits, passes **276 macOS tests, zero failures or skips** (`/tmp/cauchy-clarification-final-tests.xcresult`). The subsequent final assessment guards, recorded-live-response replay and focus refinements are covered by the targeted checkpoint checks below. No empty layout-mirroring tests were added.

Clarification regressions cover per-part drafts and legacy decode; exact context and bounded history; unchanged teaching/answer/source records; assessment and delayed help; revision; cancelled late responses; provider failure; stale source before and during a request; invalid page/quote references and trusted correction provenance; read-only assessed answers; and a real temporary-storage restart. The restart assertion compares every field in the sidecar’s actual epoch-based date encoding, avoiding a reference-epoch floating-point rounding difference in direct Date equality. Earlier red runs were caused by that assertion, not missing saved content.

## Live prompt checks

`python3 scripts/evaluate_learning_clarification.py --model gpt-6.1-sol` sends only three authored synthetic sources and the production instructions/schema. [Recorded replies](learning-clarification-results.json) retain the complete inputs and outputs. All three pass quote-location/basis checks and a replay through the production Swift source validator.

Review of the actual answers found:

- The closedness explanation correctly distinguishes a subsequence limit belonging to the ambient space from belonging to the subset, and locates the exact closedness hypothesis.
- The omitted-proof response declines to invent an argument from a source that explicitly omits the proof and definitions.
- The faulty generated teaching case rejects “continuous implies linear,” using the supplied square-function counterexample and its failed scalar-multiplication identity.

These are three observed prompt responses, not a general mathematical accuracy estimate. The live script invokes the existing Codex CLI adapter used by the repository’s evaluators. It does not drive a live provider through the native panel; native interaction checks use the offline tutor described below. On-device and other provider output quality are not inferred from this run.

## Native verification

`build/verification/CauchyLearnQuestions.app` uses `com.cauchy.learn-questions` and the isolated root `/tmp/cauchy-ui-fixture-questions-20261018`. Its authored deterministic responses test navigation and persistence, not mathematics. The normal app and learner notes are not replaced.

Observed in a 1,000-point dark window:

- The saved practice answer remains intact after opening help, asking and returning with Escape. The answer editor regains focus and the collapsed help label identifies the viewed tutor reply.
- A simulated provider failure retains the question and shows its error inside the panel. The final refinement returns focus to the question field for correction.
- A slow request can be cancelled; its draft remains and no cancelled reply is saved.
- A roughly 5,000-character reply scrolls while the question field and return action remain available. Source details disclose the supplied page, exact quote and model metadata.
- Teaching exposes a quiet Ask action. A step-specific reply and unsent follow-up survive quitting and reopening; the current step remains unchanged. Final focus/restart observations are recorded below.

The first binding to the uniquely named app took approximately 379 seconds despite a shorter requested timeout. A later `noWindowsAvailable` observation recovered on the same live app without relaunching it. Native checks have not exercised VoiceOver speech, alternate appearances or system accessibility preferences. Large production proofs, real learner outcomes and other models require broader evaluation.

## Final checkpoint checks

The subsequent **56 targeted Learn tests pass with no failures or skips** (`/tmp/cauchy-clarification-checkpoint-tests.xcresult`), including 12 clarification tests and the recorded live replies passing the production Swift validator. These cover the final assessment guards and focusable action. The final Space/Return event handler then builds in Debug (`/tmp/cauchy-questions-keyboard-final.log`) and Release (`/tmp/cauchy-clarification-final-release.log`). Native verification confirms Escape returns focus to the teaching Ask button, Space reopens its panel, and Command-Return still advances the lesson after dismissal. The first handler attempt used the wrong SwiftUI overload and failed to build; the final code uses the SDK’s key-set overload with modifier filtering so Command-Return remains available to the lesson.

The final native cold restart restores **Worked example**, its saved exchange and its own unsent follow-up. The earlier idea’s separate unsent draft remains saved. After viewing that restored panel and quitting, the complete `learning.json` (sessions and map) equals its pre-restart snapshot. All checkpoint Swift files, generated project references, tests and recorded live responses match the isolated source snapshot. A screenshot of the actual authored fixture panel is retained in the chat artifacts as `learn_step_question_panel.png`.

This is a local Learn checkpoint, ready for the separately coordinated reader integration. No push, merge, reader-PR adoption or shared-checkout branch change is part of this milestone.

## Integrated-baseline smoke check

After the coordinator handed back `d8bb040`, the combined Debug app from `/tmp/cauchy-sync-build-20261018` was copied into the same separately named fixture bundle. The combined test result was independently read: **304 passed, zero failed or skipped**. The adopted app/test source matches the tested `cec0fb2` tree; the coordinator also records its Release build in [workstream synchronization](workstream-sync.md).

In the native 1,000-point dark window, Learn restored the exact worked-example step, its reply and unsent follow-up. Escape returned focus to Ask, and Space reopened it. Source details opened PDF page 1 in the notes inspector without changing the teaching step. Closing the inspector and returning to the path retained the single due-review action and collapsed course details. After quit, the entire persisted `learning.json` still matched the pre-integration fixture snapshot. This is a narrow integrated Learn smoke check; it does not extend the earlier model-quality or accessibility claims.
