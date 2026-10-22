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

## Native verification pending

The final tested executable was copied only into the existing disposable `/tmp/CauchyLearnSearch84.app` bundle (`com.cauchy.learn-search84`), configured for fresh authored root `/tmp/cauchy-ui-fixture-export92-native`. Native launch/inspection reported that the Mac was locked and automatic unlock failed. Manual unlock was requested; the save/cancel dialogs, final footer layout, selected/full file destinations and write-error presentation have not yet been observed. The test suite establishes format/content and persistence behavior, not native save-panel behavior.

Finish this check after unlock: create an authored delayed draft, open its requirement history, cancel an export, save one record and all history to distinct temporary Markdown files, inspect their actual contents and compare the complete session/map sidecar before/after and after a cold restart. Include an earlier-objective/source-qualified record. Keep the installed app, normal library and system settings unchanged. No live model evaluation, VoiceOver speech or alternate appearance/accessibility settings are claimed.
