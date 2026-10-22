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

The final attached-sheet workflow is verified in the disposable `/tmp/CauchyLearnSearch84.app` (`com.cauchy.learn-search84`), using only the authored root `/tmp/cauchy-ui-fixture-export92-native`. This bundle contains the final 403-test implementation checkpointed as `fc535f0`; its debug dylib SHA-256 is `06a0ab5559825506f6d3019d8a3465887809f2a831f5bd175b5d1923530049e6`. Export service, view and focused tests are unchanged by the later `bbc485f` delayed-action checkpoint, whose complete suite passes 408 tests.

The fixture has a 2,380-character mathematical draft with multiline text, a heading, fenced mathematics and a final marker. Before inspection, only this fixture was qualified with a revised current objective, an earlier saved source revision and a contradictory original Correct grade. The history showed two records, the newer draft selected, earlier wording available and the old result labelled Assessment needs checking. The footer's Close, Read selected work, Export work and Open saved lesson controls fit without truncation. No tutor submission or model call was made during export verification.

The final native checks observed:

- **Cancel:** set a distinct test filename in the selected-record save sheet and clicked Cancel. The history returned with the same delayed draft selected; `/tmp/cauchy-export92-sheet-cancel.md` was not created.
- **Selected record:** the native sheet displayed the selected question/answer/feedback scope. Saving `/tmp/cauchy-export92-sheet-selected.md` produced 3,668 UTF-8 bytes and exactly one record, then visibly returned to the same history selection.
- **Requirement history:** the native sheet displayed the full requirement scope. Saving `/tmp/cauchy-export92-sheet-history.md` produced 5,284 UTF-8 bytes and exactly two recent-first records, again retaining selection.
- **Reading and return:** the returned history remained inspectable. Escape closed it to the same Learning path. After quitting and confirming the disposable process had stopped, a cold launch restored both records and the exact draft. The earlier result retained its source-age warning, original Correct grade and assessment-review qualification.

Both actual files contain the complete draft as exact line-preserving block quotes through `FINAL-AUTHORED-EXPORT92-MARKER`. The selected file excludes the earlier answer/feedback. The full file includes that original answer, feedback, next step, criterion outcomes, tutor attribution, revised current goal and earlier wording; its stale source remains explicitly qualified. Checks against the fixture's actual hidden keys/hints find none in either file. Raw page text, the authored old-revision marker and unrelated closed-subset draft are absent. Source references identify supplied material without certifying the mathematics.

The entire saved `learning.json` sidecar matches `/tmp/cauchy-export92-native-before.json` after the complete cancellation/save/reading flow, after quit and after cold restart, using parsed JSON equality. This covers all sessions, drafts, help, attempts, grades, schedules and the complete map. Both output files also retain exactly the same SHA-256 after restart: selected `b93b1af8206499830b13c3966b5b3a472a943a2b459425899400f1565e04ce03`, full history `9823d3fc48cacc63d6647429590c5ccac94b6c99cdc839e0c7ab99ce6d4e4466`. The history return screenshot and accessibility snapshot are `/tmp/cauchy-export92-sheet-return.png` and `/tmp/cauchy-export92-sheet-return-ax.txt`. The disposable app was left closed.

### Limits

Earlier native retrieval timeouts prevented observing the original application-modal implementation's return. The asynchronous implementation attaches the save sheet to the history's own weakly referenced hosting window and disables duplicate exports; it orders the panel out before a local write error, following [Apple's save-sheet API documentation](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal%28for%3Acompletionhandler%3A%29). The final checks establish visible return, subsequent controls and Escape behavior. The automation used the exposed Raise action when needed before further menus; automatic app activation and exhaustive keyboard-focus behavior are not claimed. The app's write-error alert is implemented but has not been fault-injected at runtime.

The installed app, normal library and system settings remain unchanged. No live model evaluation, VoiceOver speech or alternate appearance/accessibility settings are claimed. These authored flow checks do not establish educational efficacy or model accuracy.
