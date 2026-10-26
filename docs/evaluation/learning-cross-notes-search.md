# Find saved learning work across notes

Tracked by [JERRY-132](https://linear.app/jerryjin/issue/JERRY-132), extending [saved-lesson search](learning-history-search.md).

## Behavior

The existing Find a Saved Lesson command, toolbar button and ⇧⌘F now offer **These notes** and **All saved notes**. Each presentation starts in These notes with an empty query. All-notes results identify their source notes, activity, exact saved lesson, date and matching excerpt. The original notes and reasoning remain in place until an explicit Open, Return or double-click. Cancel/Escape returns focus to the original editor. Notes with no local lessons can still open the panel to search other saved notes.

All-notes matching includes the notes title alongside the existing permitted lesson fields. It retains the case/diacritic-insensitive, all-query-terms semantics. Answer keys, hints, future questions, PDF contents and other excluded fields remain outside the search projection. Nothing is sent to an assistant or external service; queries and scope are transient.

The store reads closed saved records without opening PDFs or installing documents. Current in-memory sessions take precedence, with revision checks if a live draft changes during background matching. Hidden notes are excluded from the all-notes scope. The UI debounces typing by 180 ms, cancels superseded work, rejects cancelled/partial pages and displays at most 100 recent matches, with the complete count and a refine-search prompt when truncated. Results use a composite workspace/session identity because different notes may legitimately contain the same saved session ID. Sorting has stable workspace/session tie breaks. Unreadable or mismatched saved records are named separately rather than silently treated as no matches.

Opening re-resolves the exact current session before committing navigation. A missing record, unavailable PDF, changed destination, busy task or cancelled request cannot substitute another lesson or create a new workspace. Failed/cancelled opens release their pending navigation state. The new path uses the existing Learn document installation and persistence readers; it does not alter the reader, storage format, provider configuration, shared commands or persistence service.

## Automated verification — 26 October 2026

Five new regressions cover:

* Closed records remain searchable while their PDF is temporarily unavailable, without opening/installing documents or changing destination, selection, saved learning bytes or summary bytes. Live drafts override saved snapshots. Notes-title terms combine with visible work; hidden notes are excluded. Shared session IDs remain distinct across notes.
* Global result bounds, total count, stable ordering, cancellation and named unreadable records.
* Exact saved-session opening, rejection of missing IDs and unavailable PDFs, return to prior notes, and complete session/map preservation through real persistence/restart.
* Cancellation and the authored fixture's location boundary, plus opening a normal local saved record without a fixture-only path restriction.
* Notes-title context does not expose hidden answer keys, hints or future prompts.

All **463 normal macOS tests pass**, without failures/skips or reported runtime warnings. The authoritative final artifacts are `/tmp/cauchy-search132-checkpoint.xcresult`, `/tmp/cauchy-search132-checkpoint.log` and `/tmp/cauchy-search132-checkpoint-summary.json`.

The isolated archive `/tmp/cauchy-search132-validation` starts at `1458037` with four declared source/test overlays in `/tmp/cauchy-search132-inputs.json`. The unoptimized Debug host uses `/Applications/Xcode.app`, pinned SwiftMath `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` and the existing resolved package cache, with automatic resolution disabled. No ordinary Swift files were added, so project regeneration was unnecessary. Fixture checks use a selected editable lesson and a canonical saved baseline before structural comparisons. The complete suite passed all 463 tests before and after the pending-navigation cleanup.

## Native verification

The disposable app uses `/tmp/cauchy-ui-fixture-search132-native`: two authored saved-note records with intentionally shared session IDs, an unsent draft marker in the second notes, and a summary whose record is unavailable. No normal learner notes or live model are involved.

On the tested runtime `/tmp/cauchy-search132-verified-tested.dylib` (SHA-256 `3be0c6a0c55c54d6ac0170eb515609815f492312c7ff88f9cea0d65841b1b5e4`), native checks established:

* ⇧⌘F opened These notes from an existing guided-practice draft. Searching the second notes' draft marker found nothing locally; All saved notes found its exact lesson, notes title and draft excerpt. The unreadable disclosure identified the missing record. Visual inspection confirmed a readable scope selector, result and fixed footer.
* Cancel returned to the unchanged original draft with editor focus. A subsequent panel again defaulted to These notes with an empty query. A temporary tool focus failure was resolved by rebinding the same running app; it was not treated as an application regression or a reason to relaunch.
* The hidden answer-key marker yielded no matches across notes. Return did not activate a stale result. Replacing the query with the draft marker and pressing Return opened the second notes and its exact unsent draft.
* A query matching both copies of the same titled lesson displayed both notes separately. Down selected the second copy while focus remained in the search field, and Return opened that exact record. Escape from another search returned focus to its unchanged saved reasoning.
* After a confirmed quit and cold restart, the authored fixture reopened its initial path. A fresh All saved notes search found the preserved second-note draft and Return reopened it exactly. This checks saved-work/search recovery; it does not claim that the fixture restores the last cross-note selection.

Both complete parsed learning files matched `/tmp/cauchy-search132-native-before.json` after search and explicit opens. Their bytes matched `/tmp/cauchy-search132-native-pre-restart-hashes.json` across cold restart, further search/open and final quit. The app was confirmed stopped inside the cleanup command before restoring its original plist and dylib byte-for-byte from `/tmp/cauchy-search132-original.info.plist` and `/tmp/cauchy-search132-original.dylib`.

The final checkpoint runtime `/tmp/cauchy-search132-checkpoint-tested.dylib` has SHA-256 `cd9ba61decd8283db50d1c283edd681005b718cc31478c0d7eccec29129b6034`. It adds only pending-request cleanup after the walkthrough above; presentation/search code is unchanged. A matched-code recheck opened the default scope and found the second note's draft across notes. Temporarily holding that task-owned PDF caused an inline opening error while the search and original task stayed in place. Restoring the PDF byte-for-byte and retrying opened the exact draft successfully. Both complete learning files again matched the original snapshots and pre-restart hashes. Final cleanup confirmed process absence, the recovered PDF and exact original app files.

The installed app, normal library and system settings remain unchanged. Large-library latency, exhaustive bookmark/provider combinations and comprehensive accessibility remain unmeasured. These checks do not establish mathematical grading quality or improved learning outcomes. No live evaluation, push, merge or release occurred.
