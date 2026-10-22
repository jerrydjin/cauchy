# Portable saved learning work

Tracked by [JERRY-92](https://linear.app/jerryjin/issue/JERRY-92). **Review my work** now has an **Export work** menu for saving either the selected record or the exact requirement's full history as local UTF-8 Markdown. The standard save panel identifies the scope and suggested `.md` filename; cancellation returns without writing, and a write error is shown locally in the history view. No provider request, sharing or upload is involved.

`LearningRequirementHistoryExport` builds on the existing learner-visible history projection. It includes the full displayed question or learning goal, answer or unsubmitted draft, original tutor grade, feedback, reasoning checks, next step, recorded date/help and tutor attribution. Export time and original record times are distinct ISO-8601 UTC timestamps. Recent-first ordering and record scope match the history view; an unknown selected ID produces no file content rather than falling back to exporting everything.

Earlier requirement wording remains qualified, original optimistic grades with unsupported criteria remain labelled as needing assessment review, and missing/different question kinds are not presented as current evidence. Source references identify supplied page numbers and the saved source quote's exact normalized location when available. Transcriptions are attributed to the user's saved revision time, with a separate source-age warning derived from the current document. A missing source/quote or invalid legacy index stays explicit; page labels do not overflow. Source references do not verify the tutor's mathematical judgement.

The export deliberately excludes expected answers, unrevealed hints, unseen diagnostic/exit prompts, unrelated targets or kinds, chapter work, whole source-page text and raw transcription records. Markdown block quotes preserve complete multiline mathematics, headings and fenced code within each content section. Exporting does not select a lesson, mark help, create an attempt, change a grade, alter a schedule or write the learning map. Actual file output is an atomic local write after the learner chooses a destination.

## Automated verification — 22 October 2026

The six focused export checks pass. The final complete macOS suite passes **403 tests, zero failures or skips**, with no reported runtime warnings (`/tmp/cauchy-export92-full.xcresult`, `/tmp/cauchy-export92-full.log`). New coverage includes:

- a long mathematical draft with Markdown/fenced content and a final marker, while sentinel keys, hints, unseen prompts, raw notes and unrelated/chapter records stay absent;
- original Correct grades retained beside inconsistent criteria, original feedback/next step/help/date/tutor, earlier wording, missing kinds and stale-source qualifications, including an unmatched maximum integer criterion index;
- deterministic recent-first ordering, exact selected-record scope and empty/missing-selection handling;
- supplied pages, located quotes and user transcription dates without raw original/corrected pages or correction notes;
- empty and malformed legacy source locations without invented citations or overflow;
- a real disposable persistence flow containing an earlier application exit and a delayed draft: selected/all export, an exact UTF-8 file round trip and cold reload preserve every session field, schedule and the complete map. Export also leaves the current lesson selection unchanged.

Tests use an isolated archive of `b7ccda5` plus five byte-identical implementation/test/project inputs in `/tmp/cauchy-export92-validation`. The generated project adds only the export service and its focused test file. SwiftMath remains at `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7`, using the resolved package cache with automatic package resolution disabled. `git diff --check` passes.

The final save-sheet lifecycle change was tested separately from an isolated archive of `4d83e5e` plus the byte-identical history-view change in `/tmp/cauchy-export92-sheet-validation`. The final complete suite again passes **403 tests, zero failures or skips**, with no reported runtime warnings (`/tmp/cauchy-export92-sheet-final.xcresult`, `/tmp/cauchy-export92-sheet-final.log`). The SwiftMath pin and package-resolution configuration are unchanged.

## Native verification — 22 October 2026

After manual unlock, the disposable `/tmp/CauchyLearnSearch84.app` (`com.cauchy.learn-search84`) opened the fresh authored root `/tmp/cauchy-ui-fixture-export92-native`. The history sheet showed both the unsubmitted delayed check and an earlier ordinary application result, with the newer draft selected. The footer's Close, Read selected work, Export work and Open saved lesson controls fit without truncation. The export menu exposed separate selected-record and full-history actions. The selected-record native save panel showed the correct scope message and an editable filename.

This fixture contains a 2,380-character mathematical draft with multiline text, a heading, fenced mathematics and a final marker. Before inspection, only this disposable fixture was qualified with a revised current objective, an earlier saved source revision and a contradictory original Correct grade. The history retained both earlier records and labelled the old result Assessment needs checking. No tutor submission or model call was made.

The original app-modal implementation saved `/tmp/cauchy-export92-selected.md` through the real native Export button. The resulting 3,668-byte UTF-8 file contains exactly one record and the complete draft as line-preserving block quotes, including the final marker. It retains earlier wording beside the revised current goal and excludes the prior result's answer and feedback. Parsed comparison of the entire `learning.json` sidecar against `/tmp/cauchy-export92-native-before.json` remained equal after inspection, attempted cancellation, the actual file save and relaunch. A cold launch before the file save also visibly restored the exact draft and both saved records.

However, after either Cancel or Export, native window retrieval timed out (`-10005`) instead of exposing the return to history. A short process sample showed the app idle in its normal event loop; the saved file and state comparisons establish output/preservation, but do not establish usable focus or cancellation return. Only the disposable verification process was stopped for recovery. Native retrieval continued timing out on a later fresh launch, so this cannot yet be attributed solely to the app.

The final implementation replaces the nested application-wide `runModal()` event loop with a save sheet attached to the history view's own hosting window, using the existing `WindowAccessor` and a weak reference. Duplicate exports are disabled while the panel is open. The Markdown snapshot and atomic UTF-8 write remain unchanged. The completion handler orders the panel out before showing a local write error, following [Apple's save-sheet API documentation](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal%28for%3Acompletionhandler%3A%29). This change is intended to let native sheet handling restore the owning history; that return still needs observation.

### Remaining native checks

The final sheet implementation still needs an observed Cancel return and selected/full exports to distinct temporary files, with unchanged history selection and complete state/file comparisons after cold restart. The full native history file and write-error alert have not been exercised. The user has been asked to bring the temporary app's Learn window forward because native controls cannot currently retrieve it. Keep JERRY-92 In Progress until this workflow is observed.

The installed app, normal library and system settings remain unchanged. No live model evaluation, VoiceOver speech or alternate appearance/accessibility settings are claimed.
