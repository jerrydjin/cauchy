# Upcoming reviews across notes

Tracked by [JERRY-127](https://linear.app/jerryjin/issue/JERRY-127), extending the [cross-notes overview](learning-review-overview.md) and its [compact schedules](learning-review-performance.md).

## Behavior

The overview now includes notes with eligible future checks. **Due and in progress** stays first; **Scheduled for later** follows in date order. Each note appears once. Mixed notes show current counts, an upcoming count and the next future date/time. An unfinished draft stays in the current section even if its original scheduled date is later than the current clock. Future-only selection explains that the review is not due and offers the existing **Open learning path** action to continue other work.

The schedule's existing binary search now also provides the remaining future count and first future date. The overview explicitly opts into these rows; default due/unfinished projections and the actual delayed-review queue retain their earlier behavior. A date equal to the current clock is due. Moving the clock backward restores the future classification from the same prepared schedule. No persisted field or review interval changes.

Eligibility still comes from the shared candidate selector: exact requirement identity, usable source and independent immediate evidence. Set-aside, helped, superseded and source-blocked records cannot become upcoming evidence. Existing active drafts remain inspectable. Showing dates never generates a question, grades an answer or grants progress. Refresh and live revision invalidation keep their existing boundaries.

The native list uses two labelled sections, persistent selection and the existing glass action, following [Apple's lists guidance](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) and [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials), rechecked on 25 October 2026. Scheduled content remains ordinary text; no new custom glass surface is introduced. Dates describe the saved schedule, not a validated memory model or retention guarantee.

## Automated verification — 25 October 2026

All **447 normal macOS tests pass**, with zero failures/skips and no reported runtime warnings. This includes two new regressions and extended schedule checks:

* Mixed due/future/active schedules preserve queue counts while exposing future counts and dates across exact boundaries and backward clock movement; an empty schedule stays empty.
* Upcoming schedules preserve requirement, assistance, set-aside and source gates. A future check remains absent from the real queue until due.
* Actual saved closed notes sort after current work, respect hidden notes and change classification at the boundary without another file refresh. Live restoration and assessment exclusion invalidate the same cache. Read-only inspection preserves the current task, selected lesson, complete sessions and map. Explicit future-note navigation opens the path without creating a review, and both saved learning sidecars remain byte-for-byte unchanged after navigation/flush.

Existing stale-action tests continue to reject completed, rescheduled or ineligible delayed work before generating a question. Existing cache Observation, source-change, record compatibility and reader/Learn synchronization regressions also pass.

The isolated archive `/tmp/cauchy-review127-validation` starts at `1b6c283` and overlays five exact implementation/test files recorded in `/tmp/cauchy-review127-inputs.json`. The standard unoptimized Debug test host uses `/Applications/Xcode.app`, pinned SwiftMath `fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7` and the existing package cache with automatic resolution disabled. Result bundle: `/tmp/cauchy-review127-tests.xcresult`; summary: `/tmp/cauchy-review127-summary.json`; log: `/tmp/cauchy-review127-tests.log`. No ordinary Swift file was added, so project regeneration is unnecessary.

## Native verification — 25 October 2026

The exact 447-test dylib was observed in the disposable `CauchyChapterFeedback112.app` against the separate authored four-record library at `/tmp/cauchy-ui-fixture-review127-native`. It is pinned at `/tmp/cauchy-review127-tested.dylib` with SHA-256 `0b1c8eb903c8f50875014e764c3270193d2d85e41cd7f5b8013790312a7ea02a`; the implementation is checkpoint `c7a69c0`.

The overview showed the mixed original notes as **1 in progress · 1 upcoming**, the second notes as **1 due**, the future-only notes as **1 upcoming**, and one unreadable record. Current rows preceded the **Scheduled for later** section. The mixed row retained its earlier scheduled date and separate next future date/time. The future-only row showed its next date/time and the explanation that it was not due. The rendered sheet was visually inspected with the future row selected. Refresh kept that selection and all counts.

Opening the future-only notes reached the current learning path with ordinary saved work available, without opening a delayed question. The **Review only** plan explicitly reported no due checks and disabled **Start session**. Cancelling that plan and returning through the overview to the original notes restored the complete delayed-check reasoning. Opening the overview from that draft and moving down with the keyboard selected the due row and then the future row, skipping section headings. Closing the overview returned to the same draft.

After the first quit was confirmed by process absence, all four complete parsed learning sidecars matched `/tmp/cauchy-review127-native-before.json`. A cold restart restored the selected delayed check and exact saved answer. Reopening the overview reproduced the same mixed, due, future and unreadable counts. A second comparison after restart again matched all four original records. No grading, tutor request or answer editing was performed. Clock-boundary behavior is established by automated checks; no OS clock change was made for native verification.

Final cleanup completed after manual unlock. A quit shortcut sent while the review sheet was open did not terminate the app; the first on-disk runtime handoff was mistakenly attempted before handling that result. The sheet was then closed through the native control and quit was repeated. Process absence was asserted inside the restoration command before any further handoff. The original plist/dylib backups at `/tmp/cauchy-review127-original.info.plist` and `/tmp/cauchy-review127-original.dylib` were restored byte-for-byte, and all four learning records still matched their complete before-snapshots. The subsequent offline-prerequisite check used a separate fixture; after that check the stopped app was again restored to these same original bytes.

These results establish the stated automated and authored native behavior, with final cleanup verified. Real mixed-library performance, Release timing, comprehensive accessibility and educational efficacy remain unproven. The installed app, normal learner library, reader and system settings are unchanged. No live model evaluation, push, merge or release occurred.
